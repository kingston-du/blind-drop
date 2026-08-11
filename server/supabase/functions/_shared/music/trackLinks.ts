// _shared/music/trackLinks.ts — the cross-service identity cache. docs/06 §5. tasks/E07-04.
//
// `track_links` is keyed by `track_key`, so a Spotify lookup happens once per distinct track
// for the lifetime of the app rather than once per submission. Eight people dropping *Ribs*
// over three months is one lookup.
//
// The contract with the caller is the important part: **`linkTrack` never throws for an
// upstream reason and never takes longer than its budget.** Sealing a song must not fail
// because Spotify was slow (docs/06 §5), so everything in here that can go wrong resolves to
// "no Spotify link yet" and leaves a row for the backfill to pick up.

import type { Db } from "../db.ts";
import type { TrackDTO } from "../dto.ts";
import { findByIsrc, SUBMIT_BUDGET_MS } from "./spotify.ts";

/** docs/06 §5: three misses and we stop. A fourth attempt has never once helped. */
export const MAX_RESOLVE_ATTEMPTS = 3;

interface LinkRow {
  spotify_id: string | null;
  spotify_url: string | null;
  resolve_attempts: number;
  unresolvable: boolean;
}

/**
 * Returns the track with `spotify_id`/`spotify_url` filled in if they can be, and keeps
 * `track_links` up to date either way.
 *
 * The order matters and is not an optimisation: the cache is consulted first, so the common
 * case — a track somebody has already dropped — costs one indexed read and no network at all.
 * Only a genuinely new track pays the 700ms.
 */
export async function linkTrack(
  db: Db,
  track: TrackDTO,
  opts: { budgetMs?: number; now?: Date } = {},
): Promise<TrackDTO> {
  const budgetMs = opts.budgetMs ?? SUBMIT_BUDGET_MS;
  const now = opts.now ?? new Date();

  const cached = await readLink(db, track.track_key);
  if (cached?.spotify_id) {
    return { ...track, spotify_id: cached.spotify_id, spotify_url: cached.spotify_url };
  }

  // No ISRC: there is no reliable way to match this on Spotify, so it is `unresolvable` from
  // the first moment rather than after three futile lookups (docs/06 §5). A title/artist
  // search returns the wrong recording often enough to be worse than nothing.
  if (!track.isrc) {
    await writeLink(db, track, { unresolvable: true, attempts: cached?.resolve_attempts ?? 0, now });
    return track;
  }

  // Already given up. Don't spend the budget re-proving it.
  if (cached?.unresolvable) return track;

  const match = await findByIsrc(track.isrc, { budgetMs, now });
  const attempts = (cached?.resolve_attempts ?? 0) + 1;
  await writeLink(db, track, {
    match,
    attempts,
    // The give-up decision is made here rather than in the backfill so that both callers
    // agree on it, and so the invariant docs/15 §2 asserts — every scored submission either
    // has a Spotify URL or is flagged `unresolvable`, never in limbo — holds from the first
    // attempt onwards.
    unresolvable: !match && attempts >= MAX_RESOLVE_ATTEMPTS,
    now,
  });

  if (!match) return track;

  await patchExistingSubmissions(db, track.track_key, match.spotify_id, match.spotify_url);
  return { ...track, spotify_id: match.spotify_id, spotify_url: match.spotify_url };
}

async function readLink(db: Db, trackKey: string): Promise<LinkRow | null> {
  const { data, error } = await db
    .from("track_links")
    .select("spotify_id, spotify_url, resolve_attempts, unresolvable")
    .eq("track_key", trackKey)
    .maybeSingle();
  // A cache read that fails is a cache miss, not a failed submission.
  if (error) {
    console.error(`track_links read ${trackKey}: ${error.code ?? "?"} ${error.message}`);
    return null;
  }
  return data;
}

async function writeLink(
  db: Db,
  track: TrackDTO,
  opts: {
    match?: { spotify_id: string; spotify_url: string } | null;
    attempts: number;
    unresolvable: boolean;
    now: Date;
  },
): Promise<void> {
  const { error } = await db.from("track_links").upsert(
    {
      track_key: track.track_key,
      isrc: track.isrc,
      apple_music_id: track.apple_music_id,
      apple_music_url: track.apple_music_url,
      spotify_id: opts.match?.spotify_id ?? null,
      spotify_url: opts.match?.spotify_url ?? null,
      resolved_at: opts.match ? opts.now.toISOString() : null,
      resolve_attempts: opts.attempts,
      unresolvable: opts.unresolvable,
    },
    { onConflict: "track_key" },
  );
  if (error) console.error(`track_links write ${track.track_key}: ${error.code ?? "?"} ${error.message}`);
}

/**
 * docs/06 §5: when an ISRC finally resolves, patch every existing submission carrying that
 * `track_key`, so a song someone dropped last week gains its Spotify link too.
 *
 * `track_meta` is otherwise a write-once snapshot — that is what makes The Record survive
 * catalogue churn (docs/06 §2) — and `spotify_id`/`spotify_url` are the documented exception.
 * The patch is a merge of exactly those two keys, done in SQL, so nothing else in the snapshot
 * can be rewritten by this path even by accident.
 */
async function patchExistingSubmissions(
  db: Db,
  trackKey: string,
  spotifyId: string,
  spotifyUrl: string,
): Promise<void> {
  const { error } = await db.rpc("patch_track_meta_spotify", {
    p_track_key: trackKey,
    p_spotify_id: spotifyId,
    p_spotify_url: spotifyUrl,
  });
  if (error) console.error(`patch_track_meta_spotify ${trackKey}: ${error.code ?? "?"} ${error.message}`);
}
