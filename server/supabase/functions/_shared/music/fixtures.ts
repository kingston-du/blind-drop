// _shared/music/fixtures.ts — a stand-in for Apple Music and Spotify, for the local stack.
//
// **What this replaces is the network hop, and nothing else.** The payloads below are in
// Apple's and Spotify's own wire shapes, so the developer-token signing, the DTO mapping, the
// URL allowlist, the ISRC rules and the 700ms budget all still execute for real when the suite
// runs. A fixture that returned Track DTOs would be testing the fixture.
//
// It is reachable only when `MUSIC_FIXTURES` is set, which happens in exactly one place —
// `supabase/config.toml`, the local stack. A deployed function has no such variable, so a
// missing Apple credential in production is a loud failure and never a quiet fall back to
// eight songs somebody picked in 2026.
//
// The catalogue is the same eight songs as `supabase/seed.sql` and `ios/Fixtures/payloads`,
// so the three fixture worlds agree and a track resolved through this file is byte-identical
// to the one the seed already holds. Everything numbered `90000000xx` is a deliberate edge
// case; each one says which rule it exists to exercise.

import { UpstreamError } from "./errors.ts";
import type { UpstreamOptions } from "./upstream.ts";

/** Read lazily, never cached: a test may set it after this module is first imported. */
export function fixturesEnabled(): boolean {
  return (Deno.env.get("MUSIC_FIXTURES") ?? "").toLowerCase() === "on";
}

// ─── the catalogue, in Apple's shape ─────────────────────────────────────────
// Only the attributes docs/06 §2 maps. Apple sends many more; leaving them out here is a
// reminder that the mapper must not depend on them.

interface FixtureSong {
  id: string;
  attributes: {
    name: string;
    artistName: string;
    albumName: string;
    durationInMillis: number;
    isrc?: string;
    url: string;
    artwork?: { url: string; bgColor?: string; width?: number; height?: number };
    previews?: { url: string }[];
  };
}

function song(
  id: string,
  name: string,
  artistName: string,
  albumName: string,
  durationInMillis: number,
  isrc: string | null,
  bgColor: string,
  opts: { preview?: boolean } = {},
): FixtureSong {
  return {
    id,
    attributes: {
      name,
      artistName,
      albumName,
      durationInMillis,
      ...(isrc === null ? {} : { isrc }),
      url: `https://music.apple.com/us/song/${id}`,
      artwork: {
        url: `https://is1-ssl.mzstatic.com/image/thumb/fixture/${id}/{w}x{h}bb.jpg`,
        bgColor,
        width: 3000,
        height: 3000,
      },
      ...(opts.preview === false
        ? {}
        : { previews: [{ url: `https://audio-ssl.itunes.apple.com/fixture/${id}.m4a` }] }),
    },
  };
}

const CATALOGUE: readonly FixtureSong[] = [
  song("1440818664", "Ribs", "Lorde", "Pure Heroine", 249000, "USUM71311296", "1d2b3a"),
  song("1440765580", "Nights", "Frank Ocean", "Blonde", 307000, "USQX91600321", "2b2b2b"),
  song("1452874255", "Redbone", "Childish Gambino", "“Awaken, My Love!”", 326000, "USQX91601480", "6b3a1f"),
  song("1440830827", "Motion Sickness", "Phoebe Bridgers", "Stranger in the Alps", 239000, "USDW11700831", "3d4a52"),
  song("1442571948", "Sunflower", "Post Malone & Swae Lee", "Spider-Man: Into the Spider-Verse", 158000, "USUM71812409", "c46a2a"),
  song("1656689279", "Kill Bill", "SZA", "SOS", 153000, "USRC12204245", "1a1a2e"),
  song("1468055107", "Bags", "Clairo", "Immunity", 258000, "USQX91901234", "93a7c4"),
  song("1440908896", "Time to Pretend", "MGMT", "Oracular Spectacular", 261000, "GBAYE0601498", "4a2b6b"),

  // A second Apple catalogue id for the *same recording* — the single release beside the
  // album one. docs/06 §3: both must produce `isrc:USUM71311296`, or the duplicate-track
  // scoring rule (docs/02 §4.3) misses a genuine duplicate.
  song("1440818665", "Ribs", "Lorde", "Pure Heroine - Single", 249000, "USUM71311296", "1d2b3a"),

  // A different *recording* of the same song. Different ISRC, therefore a different key, and
  // the duplicate rule correctly does not fire. docs/06 §3 says this is right.
  song("9000000004", "Ribs (Live)", "Lorde", "Live at Vector Arena", 271000, "USUM71311297", "1d2b3a"),

  // No ISRC at all: keys as `am:9000000001` and is `unresolvable` on Spotify from the start,
  // because a title/artist search returns the wrong recording often enough to be worse than
  // nothing (docs/06 §5).
  song("9000000001", "Untitled Sketch", "Anonymous", "Bandcamp Rip", 121000, null, "555555"),

  // Has an ISRC that Spotify's catalogue does not carry — a regional exclusive. Submitting it
  // must succeed with `spotify_id: null` (docs/06 §7).
  song("9000000002", "Regional Exclusive", "Someone Local", "Only Here", 184000, "GBXXX0000001", "334455"),

  // Spotify answers for this one, but slowly. The 700ms budget must cut it off and the
  // submission must still succeed (docs/06 §5, E07-04).
  song("9000000003", "Slow Lookup", "The Timeouts", "Eventually", 200000, "GBXXX0000002", "445566"),

  // No preview. docs/06 §7: the card renders with no play control, and this is not an error.
  song("9000000005", "No Preview Available", "Silent Partner", "Rights Issues", 195000, "GBXXX0000004", "667788", { preview: false }),
];

/** ISRCs Spotify has no track for. Everything else in the catalogue resolves. */
const SPOTIFY_MISSES: ReadonlySet<string> = new Set(["GBXXX0000001", "GBXXX0000003", "GBXXX0000004"]);
/** ISRCs whose Spotify lookup takes longer than any budget this app allows. */
const SPOTIFY_SLOW: ReadonlySet<string> = new Set(["GBXXX0000002"]);

/** The Spotify id the fixture assigns to an ISRC. The eight seeded songs keep the exact ids
 *  already in `seed.sql`; anything else gets a deterministic 22-character stand-in. */
const SEEDED_SPOTIFY_IDS: Record<string, string> = {
  USUM71311296: "2QjOHCTQ1JF3zJyfWY7EMU",
  USQX91600321: "7eqoqGkKwgOaWNNHx90uEZ",
  USQX91601480: "0wXuerDYiBnERgIpbb3JBR",
  USDW11700831: "0YSjKUbxJYuJ4Zk9CWjWLu",
  USUM71812409: "3KkXRkHbMCARz0aVfEt68P",
  USRC12204245: "1Qrg8KqiBpW07V7PNxwwwL",
  USQX91901234: "3AwF0Ea5jUqLDWWDaXocxT",
  GBAYE0601498: "1jJci4qxiYcOHhQR247Ns1",
};

function spotifyIdFor(isrc: string): string {
  const seeded = SEEDED_SPOTIFY_IDS[isrc];
  if (seeded) return seeded;
  // 22 base62-ish characters, like a real Spotify id, and stable for a given ISRC.
  return `fx${isrc}`.padEnd(22, "0").slice(0, 22);
}

/** Spotify track ids the fixture knows, mapped to the ISRC `GET /v1/tracks/{id}` reports.
 *  Derived from the catalogue so the two cannot drift, plus one orphan. */
const SPOTIFY_TRACKS: ReadonlyMap<string, string> = new Map([
  ...CATALOGUE.filter((s) => s.attributes.isrc !== undefined)
    .map((s) => [spotifyIdFor(s.attributes.isrc as string), s.attributes.isrc as string] as const),
  // Real on Spotify, absent from the Apple catalogue. docs/06 §4 wants `INVALID_INPUT` and the
  // `resolve.error.notfound` copy, never a stored Spotify-only track.
  ["4orphanORPHANorphan01", "GBXXX0000003"] as const,
]);

// ─── the handler ─────────────────────────────────────────────────────────────

/** Answers as the upstream would, honouring the caller's budget. `upstreamJson` has already
 *  checked the allowlist, so a URL arriving here is one of the three hosts. */
export async function fixtureUpstream<T>(url: string, opts: UpstreamOptions): Promise<T> {
  const target = new URL(url);
  const body = target.hostname === "api.music.apple.com"
    ? apple(target)
    : await spotify(target, opts);
  return body as T;
}

// ─── Apple Music ─────────────────────────────────────────────────────────────

function apple(url: URL): unknown {
  // /v1/catalog/{storefront}/search
  const search = url.pathname.match(/^\/v1\/catalog\/([a-z]{2})\/search$/);
  if (search) {
    const term = (url.searchParams.get("term") ?? "").trim().toLowerCase();
    const limit = Number(url.searchParams.get("limit") ?? "20");
    const hits = term === ""
      ? []
      : CATALOGUE.filter((s) =>
        `${s.attributes.name} ${s.attributes.artistName} ${s.attributes.albumName}`
          .toLowerCase()
          .includes(term)
      ).slice(0, limit);
    // Apple omits the `songs` key entirely when nothing matched, rather than sending an empty
    // array. The mapper has to survive that, so the fixture reproduces it.
    return hits.length === 0 ? { results: {} } : { results: { songs: { data: hits } } };
  }

  // /v1/catalog/{storefront}/songs?filter[isrc]=…
  const byIsrc = url.pathname.match(/^\/v1\/catalog\/([a-z]{2})\/songs$/);
  if (byIsrc) {
    const wanted = url.searchParams.get("filter[isrc]");
    if (!wanted) throw new UpstreamError("status", 400);
    // Apple returns *every* catalogue id carrying that ISRC. Two of ours do.
    return { data: CATALOGUE.filter((s) => s.attributes.isrc === wanted) };
  }

  // /v1/catalog/{storefront}/songs/{id}
  const byId = url.pathname.match(/^\/v1\/catalog\/([a-z]{2})\/songs\/(\d+)$/);
  if (byId) {
    const hit = CATALOGUE.find((s) => s.id === byId[2]);
    // Apple 404s an unknown catalogue id rather than returning an empty list.
    if (!hit) throw new UpstreamError("status", 404);
    return { data: [hit] };
  }

  throw new UpstreamError("status", 404);
}

// ─── Spotify ─────────────────────────────────────────────────────────────────

async function spotify(url: URL, opts: UpstreamOptions): Promise<unknown> {
  if (url.hostname === "accounts.spotify.com") {
    if (url.pathname !== "/api/token") throw new UpstreamError("status", 404);
    return { access_token: "fixture-app-token", token_type: "Bearer", expires_in: 3600 };
  }

  // /v1/search?q=isrc:XX&type=track&limit=1
  if (url.pathname === "/v1/search") {
    const q = url.searchParams.get("q") ?? "";
    const isrc = q.startsWith("isrc:") ? q.slice("isrc:".length) : null;
    if (!isrc) throw new UpstreamError("status", 400);
    if (SPOTIFY_SLOW.has(isrc)) await overBudget(opts);
    if (SPOTIFY_MISSES.has(isrc)) return { tracks: { items: [] } };
    if (!CATALOGUE.some((s) => s.attributes.isrc === isrc)) return { tracks: { items: [] } };
    const id = spotifyIdFor(isrc);
    return {
      tracks: {
        items: [{ id, external_urls: { spotify: `https://open.spotify.com/track/${id}` } }],
      },
    };
  }

  // /v1/tracks/{id}
  const byId = url.pathname.match(/^\/v1\/tracks\/([A-Za-z0-9]+)$/);
  if (byId) {
    const isrc = SPOTIFY_TRACKS.get(byId[1]);
    if (!isrc) throw new UpstreamError("status", 404);
    return { id: byId[1], external_ids: { isrc } };
  }

  throw new UpstreamError("status", 404);
}

/** Burns the caller's whole budget and then times out, exactly as a real slow upstream does
 *  once `upstreamJson`'s AbortController fires. Sleeping the full budget rather than raising
 *  at once matters: the point of the test is that the *caller* still returns in time. */
async function overBudget(opts: UpstreamOptions): Promise<never> {
  await new Promise((resolve) => setTimeout(resolve, opts.budgetMs));
  throw new UpstreamError("timeout");
}
