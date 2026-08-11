// tracks/index.ts — the catalog proxy. docs/04 §6, docs/06 §4. tasks/E07-02, E07-03.
//
//   GET  /search?q=&limit=    Apple Music catalog search, mapped to Track DTOs
//   POST /resolve             a pasted Spotify or Apple link, or a bare ISRC, → one Track
//
// **Neither route touches group data, and neither reveals anything about a round.** They are
// a catalog proxy: available in every phase, to any member, with the same answer for
// everybody. That is worth stating because it is the one pair of endpoints in this API that
// legitimately returns another user's *song* — it just has no idea that is what it is doing,
// because nothing here reads `submissions`.
//
// Both are behind `requireProfile` rather than `requireUser`. Search is billed against our
// Apple quota, and an account that has not finished onboarding has no reason to spend it.

import { ApiError, ok, optional, parseBody, serveFunction, str } from "../_shared/http.ts";
import { enforceRateLimit, requireProfile, requireUser } from "../_shared/auth.ts";
import { searchSongs, storefrontFor } from "../_shared/music/appleMusic.ts";
import { resolveTrack } from "../_shared/music/resolve.ts";
import { UpstreamError } from "../_shared/music/errors.ts";

// docs/04 §8. Thirty a minute is roughly a search every two seconds sustained, which is faster
// than anyone types with a 250ms client debounce — it is an Apple-quota guard, not a UX limit.
const SEARCH_LIMIT_PER_MINUTE = 30;
const ONE_MINUTE_IN_SECONDS = 60;

/** docs/06 §4: minimum two characters, debounced client-side at 250ms. Enforced here too,
 *  because a one-character search is a full catalogue scan we pay Apple for. */
const MIN_QUERY_LENGTH = 2;
const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 25;

/** docs/06 §4: the edge caches for 10 minutes on `(storefront, normalised q)`. The catalogue
 *  does not change in ten minutes, and this cache is what keeps search p95 under 400ms — 30%
 *  of the 90-second budget in docs/00 §7. */
const SEARCH_CACHE_SECONDS = 600;

serveFunction("tracks", {
  // ─── search ────────────────────────────────────────────────────────────────
  "GET /search": async (req, route) => {
    const ctx = await requireProfile(await requireUser(req, route));
    await enforceRateLimit(
      ctx.db,
      `search:u:${ctx.userId}`,
      SEARCH_LIMIT_PER_MINUTE,
      ONE_MINUTE_IN_SECONDS,
    );

    const url = new URL(req.url);
    // The cache key normalisation and the query the user typed are the same string, so
    // normalise once and use it for both.
    const q = (url.searchParams.get("q") ?? "").trim();
    if ([...q].length < MIN_QUERY_LENGTH) throw new ApiError("INVALID_INPUT", { field: "q" });

    const requested = Number(url.searchParams.get("limit") ?? DEFAULT_LIMIT);
    if (!Number.isInteger(requested) || requested < 1 || requested > MAX_LIMIT) {
      throw new ApiError("INVALID_INPUT", { field: "limit" });
    }

    try {
      const results = await searchSongs(storefrontFor(req), q, requested);
      // An empty result is a 200 with an empty array, never a 404: "No songs matched that"
      // is a state of the search screen, not a failed request (docs/11 `search.empty`).
      return ok({ results }, 200, {
        // Private, because the storefront comes from the caller's own header — a shared cache
        // keyed only on the URL would serve a German storefront's answer to an American.
        "cache-control": `private, max-age=${SEARCH_CACHE_SECONDS}`,
        vary: "x-storefront, authorization",
      });
    } catch (err) {
      // docs/06 §7: Apple down means "Search is down. Paste a Spotify or Apple Music link
      // instead." — which is what `UPSTREAM_UNAVAILABLE` renders as. A missing developer
      // token lands here too, as an ordinary Error, and gets the same answer: from the user's
      // side an unsigned request and a dead API are the same outage.
      if (err instanceof UpstreamError) throw new ApiError("UPSTREAM_UNAVAILABLE");
      console.error(`tracks.search failed: ${err instanceof Error ? err.message : String(err)}`);
      throw new ApiError("UPSTREAM_UNAVAILABLE");
    }
  },

  // ─── resolve ───────────────────────────────────────────────────────────────
  // The paste-a-link path, for people who search in Spotify by habit. Every URL it will
  // consider is checked against a host allowlist twice: once in `parseSongLink`, which decides
  // whether the string is a song link at all, and once in `upstream.ts`, which refuses to
  // fetch anything off its own list. No string a client sends ever becomes a URL we call
  // (docs/14 §7).
  "POST /resolve": async (req, route) => {
    const ctx = await requireProfile(await requireUser(req, route));
    await enforceRateLimit(
      ctx.db,
      `resolve:u:${ctx.userId}`,
      SEARCH_LIMIT_PER_MINUTE,
      ONE_MINUTE_IN_SECONDS,
    );

    const body = await parseBody(req, {
      spotify_url: optional(str({ min: 1, max: 512 })),
      apple_music_id: optional(str({ min: 1, max: 32 })),
      isrc: optional(str({ min: 1, max: 24 })),
    });

    // `resolveTrack` returns the track without a Spotify link. Filling it in is `linkTrack`'s
    // job and it happens at submission (docs/06 §5), not here: this endpoint exists to answer
    // "is this a real song" in the search sheet, and spending 700ms on a link the user may
    // never seal would be 700ms off the 90-second budget for nothing.
    return ok(await resolveTrack(storefrontFor(req), body));
  },
});
