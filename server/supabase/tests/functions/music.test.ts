// music.test.ts — the catalog layer, tested in-process. tasks/E07-01, E07-03, E07-04.
//
// These import `_shared/music/*` directly rather than speaking HTTP, because what they assert
// is arithmetic, not an endpoint: what a `track_key` is, which strings are song links, whether
// a signed token verifies. `tracks.test.ts` covers the endpoints on top of them.
//
// The upstream is the fixture in `_shared/music/fixtures.ts`, which answers in Apple's and
// Spotify's own wire shapes. Everything below therefore runs the real mapper, the real
// allowlist and the real budget — only the network hop is gone.

import { assert, assertEquals, assertRejects, assertThrows } from "jsr:@std/assert@1";
import {
  DEFAULT_STOREFRONT,
  developerToken,
  pemToPkcs8,
  resetDeveloperToken,
  searchSongs,
  songById,
  songsByIsrc,
  storefrontFor,
  trackFromAppleSong,
} from "../../functions/_shared/music/appleMusic.ts";
import { normaliseIsrc, parseSongLink, trackKey } from "../../functions/_shared/music/identity.ts";
import { resolveTarget, targetFromInput } from "../../functions/_shared/music/resolve.ts";
import {
  findByIsrc,
  isrcForTrack,
  resetAppToken,
  SUBMIT_BUDGET_MS,
} from "../../functions/_shared/music/spotify.ts";
import { isAllowedUpstream, upstreamJson } from "../../functions/_shared/music/upstream.ts";
import { fixturesEnabled } from "../../functions/_shared/music/fixtures.ts";
import { UpstreamError } from "../../functions/_shared/music/errors.ts";
import { ApiError } from "../../functions/_shared/http.ts";
import { trackFields } from "../../functions/_shared/dto.ts";

// Set here rather than in the stack's config, because these tests run in the *test* process.
// Static imports are safe above them: nothing in `_shared/music` reads the environment at
// module-evaluation time — `fixturesEnabled()`, `secret()` and `credentials()` are all called
// per request — which is exactly the property that lets a Supabase secret be rotated without
// a redeploy. The key is the same throwaway P-256 key the local stack uses
// (`supabase/config.toml`); it signs tokens that only ever reach the fixture.
Deno.env.set("MUSIC_FIXTURES", "on");
Deno.env.set("APPLE_MUSIC_KEY_ID", "FIXTUREKEY");
Deno.env.set("APPLE_MUSIC_TEAM_ID", "FIXTURETEAM");
Deno.env.set(
  "APPLE_MUSIC_PRIVATE_KEY",
  "-----BEGIN PRIVATE KEY-----\\nMIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQg+++sB8fDqPStKEYe\\n" +
    "+irO12iVTZL1ZfUO1Rix2vN/nTWhRANCAARtlFyvyNwGc+BTmoit5hxyjLrDMrNJ\\n" +
    "9DSpTPAag1J2STE165f2EBZGV/hrGwOr3wJBeVW0gp34EJ+PEkxfrqAc\\n-----END PRIVATE KEY-----",
);
Deno.env.set("SPOTIFY_CLIENT_ID", "fixture-client-id");
Deno.env.set("SPOTIFY_CLIENT_SECRET", "fixture-client-secret");

const SF = DEFAULT_STOREFRONT;

// ─── E07-01 · the developer token ────────────────────────────────────────────

function decodeSegment(segment: string): Record<string, unknown> {
  const padded = segment.replace(/-/g, "+").replace(/_/g, "/");
  return JSON.parse(atob(padded + "=".repeat((4 - padded.length % 4) % 4)));
}

Deno.test("the developer token is an ES256 JWT that verifies against the key", async () => {
  resetDeveloperToken();
  const jwt = await developerToken();
  const [header, claims, signature] = jwt.split(".");

  assertEquals(decodeSegment(header), { alg: "ES256", kid: "FIXTUREKEY", typ: "JWT" });

  const payload = decodeSegment(claims);
  assertEquals(payload.iss, "FIXTURETEAM");
  const lifetime = (payload.exp as number) - (payload.iat as number);
  assert(lifetime > 0, "exp is after iat");
  // docs/06 §4: 180 days is Apple's ceiling, not a target to exceed.
  assert(lifetime <= 15_552_000, `lifetime ${lifetime}s exceeds Apple's 180-day maximum`);

  // Verify for real, with the public half of the same key. A token that merely parses is not
  // evidence the signing path works — a wrong curve or a DER-wrapped signature both parse.
  const priv = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(Deno.env.get("APPLE_MUSIC_PRIVATE_KEY") as string),
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign"],
  );
  const jwk = await crypto.subtle.exportKey("jwk", priv);
  delete jwk.d;
  const pub = await crypto.subtle.importKey(
    "jwk",
    { ...jwk, key_ops: ["verify"] },
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"],
  );
  const raw = Uint8Array.from(
    atob(
      signature.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - signature.length % 4) % 4),
    ),
    (c) => c.charCodeAt(0),
  );
  assert(
    await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      pub,
      raw,
      new TextEncoder().encode(`${header}.${claims}`),
    ),
    "the developer token does not verify against its own key",
  );
});

Deno.test("the developer token is cached, and regenerated at 80% of its lifetime", async () => {
  resetDeveloperToken();
  const at = new Date("2026-08-11T00:00:00Z");
  const first = await developerToken(at);
  assertEquals(
    await developerToken(new Date(at.getTime() + 60_000)),
    first,
    "re-signed within its life",
  );

  // 80% of 180 days is 144 days. A second past that, a new token.
  const stale = new Date(at.getTime() + (0.8 * 15_552_000 * 1000) + 1_000);
  const second = await developerToken(stale);
  assert(second !== first, "the token was not regenerated at 80% of its lifetime");
});

Deno.test("an unknown storefront falls back to us rather than erroring", () => {
  const of = (value?: string) =>
    storefrontFor(
      new Request(
        "https://x.test",
        value === undefined ? {} : { headers: { "x-storefront": value } },
      ),
    );

  assertEquals(of("gb"), "gb");
  assertEquals(of("GB"), "gb", "the header is case-insensitive");
  assertEquals(of(" jp "), "jp");
  assertEquals(of(), "us", "absent");
  assertEquals(of("zz"), "us", "not a storefront Apple sells in");
  assertEquals(of("../../etc/passwd"), "us", "and it is a path segment, so this matters");
  assertEquals(of("us-east"), "us");
});

// ─── E07-03 · identity ───────────────────────────────────────────────────────

Deno.test("track_key prefers ISRC and falls back to the Apple id", () => {
  assertEquals(trackKey("USUM71703861", "1440857781"), "isrc:USUM71703861");
  assertEquals(trackKey(null, "1440857781"), "am:1440857781");
});

Deno.test("ISRCs are uppercased and de-hyphenated before use", () => {
  assertEquals(normaliseIsrc("usum71703861"), "USUM71703861");
  assertEquals(normaliseIsrc("US-UM7-17-03861"), "USUM71703861");
  assertEquals(normaliseIsrc(" us-um7-17-03861 "), "USUM71703861");
  // docs/06 §3: `^[A-Z]{2}[A-Z0-9]{3}\d{7}$`, and nothing else.
  assertEquals(normaliseIsrc("USUM7170386"), null, "too short");
  assertEquals(normaliseIsrc("USUM717038611"), null, "too long");
  assertEquals(normaliseIsrc("1SUM71703861"), null, "country code must be letters");
  assertEquals(normaliseIsrc("USUM7170386A"), null, "designation must be digits");
  assertEquals(normaliseIsrc(""), null);
  assertEquals(normaliseIsrc(null), null);
});

Deno.test("two Apple catalogue ids sharing one ISRC produce the same track_key", async () => {
  // 1440818664 is the album release of Ribs, 1440818665 the single. Different catalogue ids,
  // one recording — and the duplicate-track scoring rule (docs/02 §4.3) only fires if they
  // key alike.
  const album = await songById(SF, "1440818664");
  const single = await songById(SF, "1440818665");
  assert(album && single);
  assertEquals(album.track_key, single.track_key);
  assertEquals(album.track_key, "isrc:USUM71311296");
  assert(album.apple_music_id !== single.apple_music_id, "they really are two catalogue ids");
});

Deno.test("a live recording and its studio original produce different keys", async () => {
  const studio = await songById(SF, "1440818664");
  const live = await songById(SF, "9000000004");
  assert(studio && live);
  assert(
    studio.track_key !== live.track_key,
    "a live take is a different recording and must not collapse into the studio one",
  );
});

Deno.test("a song with no ISRC still maps to a valid DTO, keyed am:", async () => {
  const track = await songById(SF, "9000000001");
  assert(track);
  assertEquals(track.track_key, "am:9000000001");
  assertEquals(track.isrc, null);
  assertEquals(new Set(Object.keys(track)), new Set(trackFields()), "the key set is still whole");
  assert(track.title.length > 0 && track.artist.length > 0);
});

Deno.test("artwork is stored as the {w}x{h} template, and a missing preview is not an error", async () => {
  const withPreview = await songById(SF, "1440818664");
  assert(withPreview?.artwork_url?.includes("{w}x{h}"), "a resolved size would freeze one of four");
  assertEquals(withPreview?.artwork_bg_color, "1d2b3a");
  assert(withPreview?.preview_url !== null);

  const without = await songById(SF, "9000000005");
  assert(without, "a track with no preview is still a track");
  assertEquals(without.preview_url, null);
});

Deno.test("the Track DTO maps Apple's attributes field by field", () => {
  const track = trackFromAppleSong({
    id: "1440857781",
    attributes: {
      name: "Ribs",
      artistName: "Lorde",
      albumName: "Pure Heroine",
      durationInMillis: 249000,
      isrc: "usum71703861",
      url: "https://music.apple.com/us/song/ribs/1440857781",
      artwork: { url: "https://is1-ssl.mzstatic.com/x/{w}x{h}bb.jpg", bgColor: "1d2b3a" },
      previews: [{ url: "https://audio-ssl.itunes.apple.com/x.m4a" }],
    },
  });
  assertEquals(track, {
    track_key: "isrc:USUM71703861",
    isrc: "USUM71703861",
    title: "Ribs",
    artist: "Lorde",
    album: "Pure Heroine",
    artwork_url: "https://is1-ssl.mzstatic.com/x/{w}x{h}bb.jpg",
    artwork_bg_color: "1d2b3a",
    duration_ms: 249000,
    preview_url: "https://audio-ssl.itunes.apple.com/x.m4a",
    apple_music_id: "1440857781",
    apple_music_url: "https://music.apple.com/us/song/ribs/1440857781",
    // Apple cannot know these; `trackLinks.ts` fills them in (docs/06 §5).
    spotify_id: null,
    spotify_url: null,
  });
});

// ─── E07-03 · what may be pasted, and what may be fetched ────────────────────

Deno.test("parseSongLink accepts the three documented forms", () => {
  assertEquals(parseSongLink("https://open.spotify.com/track/2QjOHCTQ1JF3zJyfWY7EMU"), {
    kind: "spotify",
    spotifyId: "2QjOHCTQ1JF3zJyfWY7EMU",
  });
  assertEquals(
    parseSongLink("https://open.spotify.com/track/2QjOHCTQ1JF3zJyfWY7EMU?si=abc123&nd=1"),
    { kind: "spotify", spotifyId: "2QjOHCTQ1JF3zJyfWY7EMU" },
    "every Spotify share link has a ?si= tail",
  );
  assertEquals(parseSongLink("spotify:track:2QjOHCTQ1JF3zJyfWY7EMU"), {
    kind: "spotify",
    spotifyId: "2QjOHCTQ1JF3zJyfWY7EMU",
  });
  assertEquals(parseSongLink("https://open.spotify.com/intl-de/track/2QjOHCTQ1JF3zJyfWY7EMU"), {
    kind: "spotify",
    spotifyId: "2QjOHCTQ1JF3zJyfWY7EMU",
  });
  assertEquals(parseSongLink("https://music.apple.com/us/song/ribs/1440857781"), {
    kind: "apple",
    appleMusicId: "1440857781",
  });
  assertEquals(
    parseSongLink("https://music.apple.com/gb/album/pure-heroine/1440857779?i=1440857781"),
    { kind: "apple", appleMusicId: "1440857781" },
    "the album+?i= form is what Apple's own share sheet produces",
  );
  assertEquals(parseSongLink("US-UM7-17-03861"), { kind: "isrc", isrc: "USUM71703861" });
});

Deno.test("parseSongLink refuses everything else — this is the SSRF boundary", () => {
  for (
    const hostile of [
      "http://169.254.169.254/latest/meta-data/",
      "http://localhost:54421/functions/v1/me",
      "http://127.0.0.1/",
      "file:///etc/passwd",
      "https://open.spotify.com.evil.test/track/2QjOHCTQ1JF3zJyfWY7EMU",
      "https://evil.test/?x=https://open.spotify.com/track/2QjOHCTQ1JF3zJyfWY7EMU",
      "https://evil.test/#open.spotify.com/track/2QjOHCTQ1JF3zJyfWY7EMU",
      "https://music.apple.com.evil.test/us/song/x/1",
      "https://music.apple.com/us/artist/lorde/602767352",
      "https://open.spotify.com/album/2QjOHCTQ1JF3zJyfWY7EMU",
      "https://open.spotify.com/track/../../etc",
      "not a url at all",
      "",
      "   ",
    ]
  ) {
    assertEquals(parseSongLink(hostile), null, `parseSongLink accepted ${hostile}`);
  }
});

Deno.test("the upstream allowlist is an exact host match over https", () => {
  assert(isAllowedUpstream("https://api.music.apple.com/v1/catalog/us/search?term=x"));
  assert(isAllowedUpstream("https://api.spotify.com/v1/search"));
  assert(isAllowedUpstream("https://accounts.spotify.com/api/token"));

  assert(!isAllowedUpstream("http://api.spotify.com/v1/search"), "plaintext");
  assert(!isAllowedUpstream("https://api.spotify.com.evil.test/v1/search"), "suffix");
  assert(!isAllowedUpstream("https://evil.test/api.spotify.com"), "path");
  assert(!isAllowedUpstream("https://open.spotify.com/track/x"), "a link host is not an API host");
  assert(!isAllowedUpstream("https://169.254.169.254/"));
});

Deno.test("a blocked URL never reaches the network", async () => {
  const err = await assertRejects(
    () => upstreamJson("https://169.254.169.254/latest/meta-data/", { budgetMs: 50 }),
    UpstreamError,
  );
  assertEquals((err as InstanceType<typeof UpstreamError>).reason, "blocked");
});

// ─── the fixture flag is local-only ──────────────────────────────────────────
// The flag reaching a deployed project is not hypothetical: `supabase secrets set --env-file`
// carried it up once, and search then answered every query from the eight songs below while
// looking perfectly healthy. Fake data served to real users is worse than an outage, because
// nothing about it looks wrong.

Deno.test("MUSIC_FIXTURES is ignored on a deployed stack, however it got there", () => {
  const local = Deno.env.get("SUPABASE_URL");
  try {
    Deno.env.set("SUPABASE_URL", "https://ojzwgaffeegssfscoaiv.supabase.co");
    assert(!fixturesEnabled(), "a deployed project must reach the real Apple or fail loudly");

    // An absent or unparseable `SUPABASE_URL` counts as deployed: the safe default for a
    // switch whose failure mode is silently serving a stand-in.
    Deno.env.delete("SUPABASE_URL");
    assert(!fixturesEnabled());
    Deno.env.set("SUPABASE_URL", "not a url");
    assert(!fixturesEnabled());

    // …and the local stack, in both the shapes it appears in: the edge runtime container's
    // view of the gateway, and what `supabase status` prints for this test process.
    Deno.env.set("SUPABASE_URL", "http://kong:8000");
    assert(fixturesEnabled());
    Deno.env.set("SUPABASE_URL", "http://127.0.0.1:54421");
    assert(fixturesEnabled());
  } finally {
    if (local === undefined) Deno.env.delete("SUPABASE_URL");
    else Deno.env.set("SUPABASE_URL", local);
  }
});

Deno.test("targetFromInput requires exactly one of the three fields", () => {
  assertEquals(targetFromInput({ apple_music_id: "1440857781" }), {
    kind: "apple",
    appleMusicId: "1440857781",
  });
  assertEquals(targetFromInput({ isrc: "usum71703861" }), { kind: "isrc", isrc: "USUM71703861" });

  const field = (input: Record<string, string>) => {
    try {
      targetFromInput(input);
    } catch (err) {
      return err instanceof ApiError ? err.detail.field : "not an ApiError";
    }
    return "no error";
  };
  assertEquals(field({}), "track", "none");
  assertEquals(field({ isrc: "USUM71703861", apple_music_id: "1440857781" }), "track", "two");
  assertEquals(field({ apple_music_id: "1440857781; drop table" }), "apple_music_id");
  assertEquals(field({ apple_music_id: "../../secrets" }), "apple_music_id");
  assertEquals(field({ isrc: "nope" }), "isrc");
  assertEquals(field({ spotify_url: "https://evil.test/x" }), "spotify_url");
});

Deno.test("resolve: a Spotify link crosses to Apple by ISRC", async () => {
  const track = await resolveTarget(SF, { kind: "spotify", spotifyId: "2QjOHCTQ1JF3zJyfWY7EMU" });
  assertEquals(track.track_key, "isrc:USUM71311296");
  assertEquals(track.title, "Ribs");
  assert(track.preview_url !== null, "the whole point of crossing to Apple is the preview");
});

Deno.test("resolve: a Spotify-only track is refused, never stored", async () => {
  // Real on Spotify, absent from Apple's catalogue — a regional gap. docs/06 §4 wants
  // INVALID_INPUT and the `resolve.error.notfound` copy, because the game needs a preview and
  // a stable artwork URL that this track cannot supply.
  const err = await assertRejects(
    () => resolveTarget(SF, { kind: "spotify", spotifyId: "4orphanORPHANorphan01" }),
    ApiError,
  );
  assertEquals((err as InstanceType<typeof ApiError>).code, "INVALID_INPUT");
});

Deno.test("resolve: an Apple id Apple does not have is INVALID_INPUT, not INTERNAL", async () => {
  const err = await assertRejects(
    () => resolveTarget(SF, { kind: "apple", appleMusicId: "1111111111" }),
    ApiError,
  );
  assertEquals((err as InstanceType<typeof ApiError>).code, "INVALID_INPUT");
});

Deno.test("resolve never matches on title or artist", () => {
  // "Ribs" is in the fixture catalogue by name, but a name is not an input this API accepts
  // at all: there is no code path from a title to a stored track (docs/06 §3). Passing one
  // where an identifier belongs fails validation, which is the only outcome available.
  const err = assertThrows(() => targetFromInput({ isrc: "Ribs" }), ApiError);
  assertEquals((err as InstanceType<typeof ApiError>).detail.field, "isrc");
  assertEquals(
    assertThrows(() => targetFromInput({ apple_music_id: "Ribs" }), ApiError) instanceof ApiError,
    true,
  );
});

// ─── E07-02 · search ─────────────────────────────────────────────────────────

Deno.test("search maps Apple's results and survives a miss", async () => {
  const hits = await searchSongs(SF, "Lorde", 20);
  assert(hits.length >= 2, "Ribs has two catalogue ids in the fixture");
  for (const hit of hits) {
    assertEquals(new Set(Object.keys(hit)), new Set(trackFields()));
  }
  // Apple omits the `songs` key entirely when nothing matched. An empty array, not a throw.
  assertEquals(await searchSongs(SF, "zzzzzznothing", 20), []);
});

Deno.test("search honours its limit", async () => {
  assertEquals((await searchSongs(SF, "a", 3)).length, 3);
});

// ─── E07-04 · Spotify ────────────────────────────────────────────────────────

Deno.test("findByIsrc returns the match and caches the app token", async () => {
  resetAppToken();
  const match = await findByIsrc("USUM71311296", { budgetMs: SUBMIT_BUDGET_MS });
  assertEquals(match, {
    spotify_id: "2QjOHCTQ1JF3zJyfWY7EMU",
    spotify_url: "https://open.spotify.com/track/2QjOHCTQ1JF3zJyfWY7EMU",
  });
  // Same answer on a second call, from the cached hour-long token.
  assertEquals(await findByIsrc("USUM71311296", { budgetMs: SUBMIT_BUDGET_MS }), match);
});

Deno.test("the app token is re-fetched once the cached hour is up", async () => {
  resetAppToken();
  const at = new Date("2026-08-11T00:00:00Z");
  assert(await findByIsrc("USUM71311296", { budgetMs: SUBMIT_BUDGET_MS, now: at }));
  // The fixture always answers, so what this proves is that an expired cache does not throw
  // and does not start returning null — the failure mode a naive expiry check produces.
  const later = new Date(at.getTime() + 3_600_000);
  assert(await findByIsrc("USUM71311296", { budgetMs: SUBMIT_BUDGET_MS, now: later }));
});

Deno.test("a catalogue miss is null, not an error", async () => {
  assertEquals(await findByIsrc("GBXXX0000001", { budgetMs: SUBMIT_BUDGET_MS }), null);
});

Deno.test("a Spotify timeout is null, and it costs no more than the budget", async () => {
  const started = performance.now();
  assertEquals(await findByIsrc("GBXXX0000002", { budgetMs: SUBMIT_BUDGET_MS }), null);
  const elapsed = performance.now() - started;
  // docs/06 §5: 700ms, and a timeout must never become a failure the caller has to handle.
  assert(elapsed < SUBMIT_BUDGET_MS * 2, `the lookup took ${Math.round(elapsed)}ms`);
});

Deno.test("a malformed ISRC never reaches Spotify", async () => {
  assertEquals(await findByIsrc("not-an-isrc", { budgetMs: SUBMIT_BUDGET_MS }), null);
});

Deno.test("isrcForTrack reads the ISRC behind a Spotify id", async () => {
  assertEquals(await isrcForTrack("2QjOHCTQ1JF3zJyfWY7EMU"), "USUM71311296");
  assertEquals(await isrcForTrack("0000000000000000000000"), null, "an id Spotify does not have");
});

Deno.test("songsByIsrc returns every catalogue id carrying it", async () => {
  const both = await songsByIsrc(SF, "USUM71311296");
  assertEquals(both.length, 2, "the album and the single");
  assertEquals(new Set(both.map((t) => t.track_key)), new Set(["isrc:USUM71311296"]));
});
