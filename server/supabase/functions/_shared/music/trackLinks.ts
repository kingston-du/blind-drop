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

/** docs/06 §5: up to twenty rows a minute. Small enough that a stuck upstream costs one
 *  minute's work rather than a worker that never finishes, and large enough that a backlog
 *  from an hour of Spotify being down clears in a few minutes. */
export const BACKFILL_BATCH = 20;

/** The backfill is nobody's foreground. It is not racing a person sealing a song, so it can
 *  afford to wait longer than the 700ms budget the submission path lives under — a slow answer
 *  here is a link that arrives, where the same slow answer inline is a person watching a
 *  spinner. */
export const BACKFILL_BUDGET_MS = 2_500;

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

// ─── the backfill — docs/06 §5 step 3, tasks/E07-05 ──────────────────────────
// The second caller `writeLink` was written for. Everything about *when to give up* stays in
// this file so the two paths cannot drift: the invariant docs/15 §2 asserts — every scored
// submission either carries a Spotify URL or is flagged `unresolvable`, never in limbo — is
// only true while the inline path and the backfill agree on what three failures means.

/** A row the backfill can act on: it has an ISRC to look up, no link yet, and has not been
 *  given up on. */
export interface DueLink {
  track_key: string;
  isrc: string;
  apple_music_id: string | null;
  apple_music_url: string | null;
  resolve_attempts: number;
}

/**
 * Up to `limit` rows still worth a lookup, oldest-in-effort first.
 *
 * Ordering by `resolve_attempts` ascending is docs/06 §5's, and it is the kind way round: a
 * track that has missed once is far likelier to resolve than one that has missed twice, so the
 * cheap wins go first and the near-hopeless rows are the ones that wait. `track_links_needs_resolve`
 * (0007) is a partial index on exactly this predicate, so the scan never touches the rows that
 * are already linked — which, in a healthy database, is nearly all of them.
 *
 * A row with no ISRC is never due. `linkTrack` marks those `unresolvable` on sight, because a
 * title/artist search returns the wrong recording often enough to be worse than nothing — and
 * the filter here says so a second time rather than trusting that it happened.
 */
export async function dueForBackfill(db: Db, limit = BACKFILL_BATCH): Promise<DueLink[]> {
  const { data, error } = await db
    .from("track_links")
    .select("track_key, isrc, apple_music_id, apple_music_url, resolve_attempts")
    .is("spotify_id", null)
    .eq("unresolvable", false)
    .not("isrc", "is", null)
    .order("resolve_attempts", { ascending: true })
    .order("track_key", { ascending: true })
    .limit(limit);
  if (error) {
    console.error(`track_links due: ${error.code ?? "?"} ${error.message}`);
    return [];
  }
  return data as DueLink[];
}

export type BackfillOutcome = "resolved" | "retry" | "gave_up";

/**
 * One row's worth of backfill: look the ISRC up, record the attempt, and — on a hit — patch
 * every submission already carrying that `track_key`.
 *
 * That last part is the point of the whole exercise (docs/06 §5). A link that arrived three
 * days late is worth nothing if it only lands on the next person to drop the song; it has to
 * reach the eight rows already in The Record, which is why `patch_track_meta_spotify` matches on
 * `track_key` and not on a submission id.
 *
 * Like `linkTrack`, this never throws for an upstream reason. A worker that dies on the fourth
 * of twenty rows leaves sixteen unexamined and no record of why.
 */
export async function backfillTrack(
  db: Db,
  row: DueLink,
  opts: { budgetMs?: number; now?: Date } = {},
): Promise<{ outcome: BackfillOutcome; patched: number }> {
  const now = opts.now ?? new Date();
  const match = await findByIsrc(row.isrc, { budgetMs: opts.budgetMs ?? BACKFILL_BUDGET_MS, now });
  const attempts = row.resolve_attempts + 1;

  await writeLink(
    db,
    {
      track_key: row.track_key,
      isrc: row.isrc,
      apple_music_id: row.apple_music_id ?? "",
      apple_music_url: row.apple_music_url ?? "",
    },
    { match, attempts, unresolvable: !match && attempts >= MAX_RESOLVE_ATTEMPTS, now },
  );

  if (!match) {
    return { outcome: attempts >= MAX_RESOLVE_ATTEMPTS ? "gave_up" : "retry", patched: 0 };
  }
  return {
    outcome: "resolved",
    patched: await patchExistingSubmissions(db, row.track_key, match.spotify_id, match.spotify_url),
  };
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

/** The four fields a `track_links` row is built from. Narrower than `TrackDTO` on purpose: the
 *  backfill has a row, not a resolved track, and widening the parameter would invite somebody to
 *  write a whole snapshot's worth of fields into the cache. */
type LinkIdentity = Pick<TrackDTO, "track_key" | "isrc" | "apple_music_id" | "apple_music_url">;

async function writeLink(
  db: Db,
  track: LinkIdentity,
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
): Promise<number> {
  const { data, error } = await db.rpc("patch_track_meta_spotify", {
    p_track_key: trackKey,
    p_spotify_id: spotifyId,
    p_spotify_url: spotifyUrl,
  });
  if (error) {
    console.error(`patch_track_meta_spotify ${trackKey}: ${error.code ?? "?"} ${error.message}`);
    return 0;
  }
  // The row count, so the backfill can report how much of The Record it repaired rather than
  // just that it ran.
  return typeof data === "number" ? data : 0;
}
