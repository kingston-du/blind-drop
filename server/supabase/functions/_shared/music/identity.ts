// _shared/music/identity.ts — `track_key`, ISRC, and what counts as a song link.
// docs/06 §3, docs/14 §7. tasks/E07-03.
//
// This file is small and it decides two things the rest of the game rests on.
//
// **`track_key` is the dedupe identity.** It is what the duplicate-track scoring rule
// (docs/02 §4.3) joins on: if Ana and Ben both drop *Ribs*, naming either of them on either
// card is correct, and that only works if both submissions carry one key. ISRC comes first
// because the same recording has different Apple catalogue ids across storefronts and across
// single/album releases, and two members in different countries dropping the same song must
// land on the same key. Titles and artists are never compared — "Ribs" by "Lorde" and "Ribs"
// by "Lorde " are not a matching problem worth having.
//
// **The URL allowlist is an SSRF control.** `POST /tracks/resolve` takes a URL typed by a
// user. Parsing here decides what is even a candidate; `upstream.ts` independently refuses
// to fetch anything off its own host list. Two locks, because this is the one place in the
// API where a user's string reaches a network call.

/** docs/06 §3: `^[A-Z]{2}[A-Z0-9]{3}\d{7}$` — country, registrant, year and designation. */
const ISRC_PATTERN = /^[A-Z]{2}[A-Z0-9]{3}\d{7}$/;

/**
 * An ISRC in the one form this app stores: uppercase, no hyphens, or `null`.
 *
 * ISRCs are written `US-UM7-17-03861` as often as `USUM71703861`, and Apple has been seen to
 * return either. Normalising on the way in is what makes `track_key` stable — a hyphenated
 * copy of an ISRC already in the database would otherwise become a second, silently different
 * track, and the duplicate rule would miss it.
 */
export function normaliseIsrc(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const cleaned = raw.replace(/[\s-]/g, "").toUpperCase();
  return ISRC_PATTERN.test(cleaned) ? cleaned : null;
}

/** docs/06 §3: `isrc ? 'isrc:' + isrc : 'am:' + apple_music_id`. */
export function trackKey(isrc: string | null, appleMusicId: string): string {
  return isrc ? `isrc:${isrc}` : `am:${appleMusicId}`;
}

/** Apple catalogue ids are digits. Used to validate the `apple_music_id` input before it is
 *  ever put in a URL. */
export function isAppleMusicId(value: string): boolean {
  return /^\d{1,20}$/.test(value);
}

// ─── what a pasted link may be ───────────────────────────────────────────────

export type LinkTarget =
  | { kind: "apple"; appleMusicId: string }
  | { kind: "spotify"; spotifyId: string }
  | { kind: "isrc"; isrc: string };

/** Spotify track ids are base62, always 22 characters in practice. Kept slightly loose on
 *  length and strict on alphabet, because the alphabet is what keeps a path traversal or a
 *  query string out of the URL we build from it. */
const SPOTIFY_ID = /^[A-Za-z0-9]{16,32}$/;

/** Hosts a song link may legitimately carry, per service. Anything else is not a song link,
 *  which is a user-facing `resolve.error.badlink`, not a server error. */
const SPOTIFY_HOSTS: ReadonlySet<string> = new Set(["open.spotify.com", "play.spotify.com"]);
const APPLE_HOSTS: ReadonlySet<string> = new Set(["music.apple.com", "geo.music.apple.com"]);

/**
 * A pasted string → what to look up, or `null` if it is not a song link at all.
 *
 * Accepts the three forms docs/06 §4 lists and nothing else:
 *
 *   · `https://open.spotify.com/track/{id}` and `spotify:track:{id}`, with any `?si=` tail —
 *     every Spotify share link has one
 *   · `https://music.apple.com/{sf}/song/{slug}/{id}` and the `…/album/{slug}/{id}?i={song}`
 *     form, which is what the Apple Music app's share sheet actually produces
 *   · a bare ISRC
 *
 * A `null` here means the string never becomes a URL and never reaches `fetch`.
 */
export function parseSongLink(raw: string): LinkTarget | null {
  const input = raw.trim();
  if (input === "") return null;

  // A bare ISRC, before any URL parsing — it is the only form with no scheme.
  const bare = normaliseIsrc(input);
  if (bare) return { kind: "isrc", isrc: bare };

  // `spotify:track:{id}`, the URI the desktop app copies.
  const uri = input.match(/^spotify:track:([A-Za-z0-9]+)$/);
  if (uri) return SPOTIFY_ID.test(uri[1]) ? { kind: "spotify", spotifyId: uri[1] } : null;

  let url: URL;
  try {
    url = new URL(input);
  } catch {
    return null;
  }
  // http is upgraded rather than refused — people paste what their browser gave them — but
  // nothing else is a song link.
  if (url.protocol !== "https:" && url.protocol !== "http:") return null;
  const host = url.hostname.toLowerCase();

  if (SPOTIFY_HOSTS.has(host)) {
    // `/track/{id}` and the localised `/intl-de/track/{id}`.
    const track = url.pathname.match(/^(?:\/intl-[a-z]{2})?\/track\/([A-Za-z0-9]+)\/?$/);
    if (!track || !SPOTIFY_ID.test(track[1])) return null;
    return { kind: "spotify", spotifyId: track[1] };
  }

  if (APPLE_HOSTS.has(host)) {
    // The album form carries the song in `?i=`; the song form carries it as the last path
    // segment. `?i=` wins where both are present, because that is the specific one.
    const i = url.searchParams.get("i");
    if (i && isAppleMusicId(i)) return { kind: "apple", appleMusicId: i };
    const song = url.pathname.match(/\/song\/(?:[^/]+\/)?(\d+)\/?$/);
    if (song) return { kind: "apple", appleMusicId: song[1] };
    return null;
  }

  return null;
}
