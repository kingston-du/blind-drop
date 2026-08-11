// _shared/music/appleMusic.ts — the catalog proxy. docs/06 §2, §4, §8. tasks/E07-01, E07-02.
//
// Apple Music is the search and preview engine (ADR-002), and it is server-side for one
// reason: `attributes.previews[0].url` is a plain HTTPS `.m4a` that `AVPlayer` will play with
// no MusicKit authorization, no subscription and no permission prompt. Doing the search on the
// device would need all three.
//
// Nothing in this file is user-supplied except a search term and an id that has already been
// validated as digits. Every URL it builds is constructed from an allowlisted host plus
// `encodeURIComponent`, never by interpolating a string a client sent.

import { UpstreamError } from "./errors.ts";
import { upstreamJson } from "./upstream.ts";
import { normaliseIsrc, trackKey } from "./identity.ts";
import type { TrackDTO } from "../dto.ts";

const API = "https://api.music.apple.com";

// ─── the developer token ─────────────────────────────────────────────────────
// ES256 JWT signed with the MusicKit `.p8`. docs/06 §4.

/** 180 days is Apple's ceiling for a MusicKit developer token. */
const TOKEN_LIFETIME_SECONDS = 180 * 24 * 60 * 60;
/** Regenerate at 80% of lifetime, so a token is never handed out close to its own expiry. */
const REFRESH_AT = 0.8;

interface CachedToken {
  jwt: string;
  /** Epoch seconds after which this module stops handing the token out. */
  staleAt: number;
}
let cached: CachedToken | null = null;

function secret(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    // Loud, and it stays loud: there is no fallback path for a missing Apple credential.
    // Search returning `UPSTREAM_UNAVAILABLE` is the correct outcome of this throw.
    throw new Error(`${name} is not set; the Apple Music proxy cannot sign a developer token`);
  }
  return value;
}

function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/**
 * PEM → the DER bytes Web Crypto's `pkcs8` import wants.
 *
 * Both environments store the key as a single line with the newlines escaped as the two
 * characters `\` and `n` — that is what `server/.env.example` documents and what the local
 * stack's config carries, because the CLI's docker env file cannot hold a real newline. So
 * unescape first, then strip the armour and all whitespace.
 */
export function pemToPkcs8(pem: string): Uint8Array<ArrayBuffer> {
  const body = pem
    .replace(/\\n/g, "\n")
    .replace(/-----BEGIN [A-Z ]+-----/, "")
    .replace(/-----END [A-Z ]+-----/, "")
    .replace(/\s+/g, "");
  const binary = atob(body);
  // Backed by a plain `ArrayBuffer` explicitly: Web Crypto's `importKey` will not accept the
  // `SharedArrayBuffer`-compatible view type `new Uint8Array(length)` infers.
  const bytes = new Uint8Array(new ArrayBuffer(binary.length));
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

/** Signs and caches a developer token. `now` is injectable so a test can prove the refresh
 *  boundary without waiting 144 days. */
export async function developerToken(now: Date = new Date()): Promise<string> {
  const issuedAt = Math.floor(now.getTime() / 1000);
  if (cached && issuedAt < cached.staleAt) return cached.jwt;

  const header = base64url(
    new TextEncoder().encode(
      JSON.stringify({ alg: "ES256", kid: secret("APPLE_MUSIC_KEY_ID"), typ: "JWT" }),
    ),
  );
  const claims = base64url(
    new TextEncoder().encode(
      JSON.stringify({
        iss: secret("APPLE_MUSIC_TEAM_ID"),
        iat: issuedAt,
        exp: issuedAt + TOKEN_LIFETIME_SECONDS,
      }),
    ),
  );

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(secret("APPLE_MUSIC_PRIVATE_KEY")),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  // Web Crypto's ECDSA output is already the raw r‖s pair JWS wants — no DER unwrapping.
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      key,
      new TextEncoder().encode(`${header}.${claims}`),
    ),
  );

  const jwt = `${header}.${claims}.${base64url(signature)}`;
  cached = { jwt, staleAt: issuedAt + Math.floor(TOKEN_LIFETIME_SECONDS * REFRESH_AT) };
  return jwt;
}

/** Tests only: forget the cached token so the next call re-signs. */
export function resetDeveloperToken(): void {
  cached = null;
}

// ─── storefronts ─────────────────────────────────────────────────────────────

/** Apple Music's storefront ids, which are ISO 3166-1 alpha-2 lowercased. An id outside this
 *  set is not an error — the client derives it from `Locale.current.region`, and a region
 *  Apple does not sell in is an ordinary thing for a traveller to have. docs/06 §4: fall back
 *  to `us` rather than failing the search. */
const STOREFRONTS: ReadonlySet<string> = new Set(
  ("ae ag ai al am ao ar at au az ba bb be bf bg bh bj bm bn bo br bs bt bw by bz ca cd cg ch ci cl cm cn co cr cv cy " +
    "cz de dk dm do dz ec ee eg es fi fj fm fr ga gb gd ge gh gm gr gt gw gy hk hn hr hu id ie il in iq is it jm jo jp " +
    "ke kg kh kn kr kw ky kz la lb lc lk lr lt lu lv md me mg mk ml mm mn mo mr ms mt mu mw mx my mz na ne ng ni nl no " +
    "np nz om pa pe pg ph pk pl pt py qa ro rs ru rw sa sb sc se sg si sk sl sn sr sv sz tc td th tj tm tn tr tt tw tz " +
    "ua ug us uy uz vc ve vg vn ye za zm zw").split(" "),
);

export const DEFAULT_STOREFRONT = "us";

/** The storefront for a request, from `X-Storefront` (docs/06 §4). Anything unrecognised
 *  becomes `us`; this never throws, because a bad header must not cost the user their search. */
export function storefrontFor(req: Request): string {
  const header = (req.headers.get("x-storefront") ?? "").trim().toLowerCase();
  return STOREFRONTS.has(header) ? header : DEFAULT_STOREFRONT;
}

// ─── the wire shape, and the mapping to ours ─────────────────────────────────

export interface AppleSong {
  id: string;
  attributes?: {
    name?: string;
    artistName?: string;
    albumName?: string;
    durationInMillis?: number;
    isrc?: string;
    url?: string;
    artwork?: { url?: string; bgColor?: string };
    previews?: { url?: string }[];
  };
}

/**
 * Apple's song attributes → the Track DTO of docs/06 §2, field by field.
 *
 * Three of the mappings are rules rather than copies:
 *
 *   · `artwork_url` keeps Apple's literal `{w}x{h}` template. Resolving a size here would
 *     freeze one, and the app needs four (docs/06 §2.1) — 120 in a search row up to 900 on a
 *     share card. The client substitutes.
 *   · `preview_url` absent is normal, not an error: the card simply renders with no play
 *     control (docs/06 §7). Never a placeholder, never a disabled button.
 *   · `isrc` absent falls back to `am:` keying and is worth noticing, because it costs that
 *     track its Spotify link forever (docs/06 §5).
 *
 * `spotify_id` / `spotify_url` are always `null` here. Apple cannot know them; `trackLinks.ts`
 * fills them in, at submission time or in the backfill.
 */
export function trackFromAppleSong(song: AppleSong): TrackDTO {
  const a = song.attributes ?? {};
  const isrc = normaliseIsrc(a.isrc);
  if (!isrc) {
    console.log(`apple song ${song.id} has no ISRC; keying as am: and unresolvable on Spotify`);
  }

  return {
    track_key: trackKey(isrc, song.id),
    isrc,
    title: a.name ?? "",
    artist: a.artistName ?? "",
    album: a.albumName ?? "",
    artwork_url: a.artwork?.url ?? null,
    artwork_bg_color: a.artwork?.bgColor ?? null,
    duration_ms: a.durationInMillis ?? 0,
    preview_url: a.previews?.[0]?.url ?? null,
    apple_music_id: song.id,
    apple_music_url: a.url ?? `https://music.apple.com/${DEFAULT_STOREFRONT}/song/${song.id}`,
    spotify_id: null,
    spotify_url: null,
  };
}

// ─── the three calls ─────────────────────────────────────────────────────────
// Search is 30% of the 90-second budget (docs/00 §7), so 3s is already generous; the point of
// the number is that a hung Apple becomes `UPSTREAM_UNAVAILABLE` and a "search is down" screen
// rather than a spinner nobody can cancel.
const CATALOG_BUDGET_MS = 3_000;

async function catalog<T>(path: string, budgetMs = CATALOG_BUDGET_MS): Promise<T> {
  return await upstreamJson<T>(`${API}${path}`, {
    budgetMs,
    headers: { authorization: `Bearer ${await developerToken()}` },
  });
}

export async function searchSongs(
  storefront: string,
  term: string,
  limit: number,
): Promise<TrackDTO[]> {
  const query = new URLSearchParams({ term, types: "songs", limit: String(limit) });
  const body = await catalog<{ results?: { songs?: { data?: AppleSong[] } } }>(
    `/v1/catalog/${storefront}/search?${query}`,
  );
  // Apple omits `songs` entirely when nothing matched. An empty result is not a failure.
  return (body.results?.songs?.data ?? []).map(trackFromAppleSong);
}

/** One catalogue id. `null` when Apple does not have it, which a 404 is how it says. */
export async function songById(storefront: string, appleMusicId: string): Promise<TrackDTO | null> {
  try {
    const body = await catalog<{ data?: AppleSong[] }>(
      `/v1/catalog/${storefront}/songs/${encodeURIComponent(appleMusicId)}`,
    );
    const song = body.data?.[0];
    return song ? trackFromAppleSong(song) : null;
  } catch (err) {
    if (err instanceof UpstreamError && err.status === 404) return null;
    throw err;
  }
}

/**
 * Every catalogue id carrying `isrc`, mapped. Apple returns more than one — the single and
 * the album release of the same recording are separate catalogue ids — and they all key to
 * the same `track_key`, which is the entire point of preferring ISRC (docs/06 §3).
 *
 * The first is taken. Which of two identical recordings we store is arbitrary and the
 * `track_key` is the same either way, so it cannot affect scoring.
 */
export async function songsByIsrc(storefront: string, isrc: string): Promise<TrackDTO[]> {
  const query = new URLSearchParams({ "filter[isrc]": isrc });
  const body = await catalog<{ data?: AppleSong[] }>(`/v1/catalog/${storefront}/songs?${query}`);
  return (body.data ?? []).map(trackFromAppleSong);
}
