// _shared/music/spotify.ts — the identity bridge. docs/06 §5, §8. tasks/E07-04.
//
// Spotify is never the source of a track in this app. It answers exactly one question —
// "which Spotify id is this ISRC?" — so that every song in The Record is exportable to a
// Spotify playlist (owner amendment A2). Search, artwork and previews all come from Apple.
//
// Two credentials rules, and they are not the same rule:
//
//   · `SPOTIFY_CLIENT_SECRET` is used here and nowhere else. It never reaches the app bundle.
//     PKCE exists precisely so it does not have to (docs/06 §6).
//   · The user's own Spotify token is never seen by this server at all. Playlist creation is
//     the client's job, with the user's credentials (docs/06 §6). There is no code here that
//     writes to a Spotify account, and there should never be.

import { UpstreamError } from "./errors.ts";
import { upstreamJson } from "./upstream.ts";
import { normaliseIsrc } from "./identity.ts";

const ACCOUNTS = "https://accounts.spotify.com";
const API = "https://api.spotify.com";

/** docs/06 §5: at submission time the lookup is inline and gets 700ms. Missing the link is a
 *  cosmetic loss the backfill repairs; making somebody wait to seal a song is not. */
export const SUBMIT_BUDGET_MS = 700;
/** The token hop is part of the same budget, so it gets a slice rather than its own. */
const TOKEN_BUDGET_MS = 2_000;

// ─── the app token ───────────────────────────────────────────────────────────
// Client-credentials flow, cached for its full hour (docs/06 §5).

interface CachedToken {
  token: string;
  /** Epoch milliseconds. A minute of slack, so a token is never used as it expires. */
  expiresAt: number;
}
let cached: CachedToken | null = null;

function credentials(): { id: string; secret: string } | null {
  const id = Deno.env.get("SPOTIFY_CLIENT_ID");
  const secret = Deno.env.get("SPOTIFY_CLIENT_SECRET");
  // Unlike the Apple key, absent Spotify credentials are survivable: every track simply has
  // no Spotify link, which docs/06 §7 already requires the UI to handle. Degrade, don't fail.
  return id && secret ? { id, secret } : null;
}

async function appToken(now: Date): Promise<string | null> {
  if (cached && now.getTime() < cached.expiresAt) return cached.token;

  const creds = credentials();
  if (!creds) return null;

  const body = await upstreamJson<{ access_token?: string; expires_in?: number }>(
    `${ACCOUNTS}/api/token`,
    {
      budgetMs: TOKEN_BUDGET_MS,
      method: "POST",
      headers: {
        authorization: `Basic ${btoa(`${creds.id}:${creds.secret}`)}`,
        "content-type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({ grant_type: "client_credentials" }).toString(),
    },
  );
  if (!body.access_token) throw new UpstreamError("network");

  cached = {
    token: body.access_token,
    expiresAt: now.getTime() + Math.max(0, (body.expires_in ?? 3600) - 60) * 1000,
  };
  return cached.token;
}

/** Tests only: forget the cached token. */
export function resetAppToken(): void {
  cached = null;
}

// ─── the lookup ──────────────────────────────────────────────────────────────

export interface SpotifyMatch {
  spotify_id: string;
  spotify_url: string;
}

/**
 * The Spotify track for an ISRC, or `null`.
 *
 * `null` covers every way this can not work — no credentials, a timeout, a 500, or a genuine
 * catalogue miss — because every one of them means the same thing to the caller: no link on
 * this track yet. Distinguishing them would only tempt a caller into failing a submission
 * over it, and docs/06 §5 is explicit that sealing a song must never fail because Spotify was
 * slow. What the caller *can* tell apart is `null` from a match, and that is all it needs.
 *
 * A track with no ISRC never gets here: `trackLinks.ts` marks it `unresolvable` on sight,
 * because a title/artist search returns the wrong recording often enough to be worse than
 * nothing (docs/06 §5).
 */
export async function findByIsrc(
  rawIsrc: string,
  opts: { budgetMs: number; now?: Date } = { budgetMs: SUBMIT_BUDGET_MS },
): Promise<SpotifyMatch | null> {
  const isrc = normaliseIsrc(rawIsrc);
  if (!isrc) return null;

  try {
    const token = await appToken(opts.now ?? new Date());
    if (!token) return null;

    const query = new URLSearchParams({ q: `isrc:${isrc}`, type: "track", limit: "1" });
    const body = await upstreamJson<{
      tracks?: { items?: { id?: string; external_urls?: { spotify?: string } }[] };
    }>(`${API}/v1/search?${query}`, {
      budgetMs: opts.budgetMs,
      headers: { authorization: `Bearer ${token}` },
    });

    const hit = body.tracks?.items?.[0];
    if (!hit?.id) return null;
    return {
      spotify_id: hit.id,
      // Build the URL rather than trusting `external_urls`, so a malformed upstream field
      // cannot become a link the app opens.
      spotify_url: `https://open.spotify.com/track/${hit.id}`,
    };
  } catch (err) {
    if (err instanceof UpstreamError) {
      console.log(`spotify isrc lookup ${isrc}: ${err.reason}`);
      return null;
    }
    throw err;
  }
}

/**
 * The ISRC behind a Spotify track id, for the paste-a-Spotify-link path (docs/06 §4).
 *
 * Unlike `findByIsrc`, this one is allowed to fail loudly: the user asked for this specific
 * track by pasting it, and answering "we couldn't check" is honest where silently resolving
 * to nothing would not be.
 */
export async function isrcForTrack(
  spotifyId: string,
  opts: { budgetMs?: number; now?: Date } = {},
): Promise<string | null> {
  const token = await appToken(opts.now ?? new Date());
  if (!token) throw new UpstreamError("network");

  try {
    const body = await upstreamJson<{ external_ids?: { isrc?: string } }>(
      `${API}/v1/tracks/${encodeURIComponent(spotifyId)}`,
      {
        budgetMs: opts.budgetMs ?? TOKEN_BUDGET_MS,
        headers: { authorization: `Bearer ${token}` },
      },
    );
    return normaliseIsrc(body.external_ids?.isrc);
  } catch (err) {
    // An id Spotify does not have is a bad link, not an outage — the caller turns this into
    // `resolve.error.notfound` rather than `UPSTREAM_UNAVAILABLE`.
    if (err instanceof UpstreamError && err.status === 404) return null;
    throw err;
  }
}
