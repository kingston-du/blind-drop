// tracks.test.ts — `GET /tracks/search` and `POST /tracks/resolve` over HTTP.
// tasks/E07-02, E07-03.
//
// Black box, against the running stack, with real access tokens — so what is asserted is what
// a device receives, envelope and status included. The mapping arithmetic underneath is
// covered in `music.test.ts`; this file is about the endpoints.

import { assert, assertEquals } from "jsr:@std/assert@1";
import { call, isRfc3339Z, keysOf, newNamedUser, newUser } from "./_harness.ts";

const TRACK_KEYS = [
  "apple_music_id",
  "apple_music_url",
  "album",
  "artist",
  "artwork_bg_color",
  "artwork_url",
  "duration_ms",
  "isrc",
  "preview_url",
  "spotify_id",
  "spotify_url",
  "title",
  "track_key",
].sort();

/** The suite is useless if the stack is not in fixture mode — every catalog call would go to
 *  the real Apple with a throwaway key and fail for the wrong reason. Say so once, loudly,
 *  rather than letting twelve tests fail with a 502. */
async function assertFixtureMode(token: string): Promise<void> {
  const res = await call("tracks", "/search?q=Ribs", { token });
  if (res.status === 502) {
    throw new Error(
      "The stack is not serving music fixtures. `supabase/config.toml` sets MUSIC_FIXTURES; " +
        "run `npm run db:restart` so the edge runtime picks it up.",
    );
  }
}

Deno.test("GET /tracks/search returns Track DTOs and nothing else", async () => {
  const user = await newNamedUser("Ana");
  await assertFixtureMode(user.token);

  const res = await call("tracks", "/search?q=Lorde", { token: user.token });
  assertEquals(res.status, 200);
  assertEquals(keysOf(res.body), ["data", "server_now"]);
  assert(isRfc3339Z(res.body.server_now));
  assertEquals(keysOf(res.body.data), ["results"]);

  const results = res.body.data.results as Record<string, unknown>[];
  assert(results.length > 0);
  for (const track of results) {
    assertEquals(keysOf(track), TRACK_KEYS, "a Track carries exactly the docs/06 §2 keys");
    // docs/06 §2.1: the template, never a resolved size — the app needs four different ones.
    assert(String(track.artwork_url).includes("{w}x{h}"));
    // Search is a catalog proxy. It has no idea what a group is, so it cannot be asked to
    // resolve a Spotify id, and does not (docs/06 §5 — that happens at submission).
    assertEquals(track.spotify_id, null);
  }
});

Deno.test("search is cached at the edge, per storefront", async () => {
  const user = await newNamedUser("Ana");
  const res = await call("tracks", "/search?q=Ribs", { token: user.token });
  assertEquals(res.status, 200);
  // docs/06 §4: 10 minutes on (storefront, normalised q). Private, because the storefront is
  // the *caller's* — a shared cache keyed on the URL alone would serve a German answer to an
  // American.
  assertEquals(res.headers.get("cache-control"), "private, max-age=600");
  assert(res.headers.get("vary")?.includes("x-storefront"));
});

Deno.test("search takes the storefront from the header and shrugs at a bad one", async () => {
  const user = await newNamedUser("Ana");
  for (const storefront of ["gb", "zz", "../../etc", ""]) {
    const res = await call("tracks", "/search?q=Ribs", {
      token: user.token,
      headers: { "x-storefront": storefront },
    });
    assertEquals(
      res.status,
      200,
      `storefront ${JSON.stringify(storefront)} should not fail a search`,
    );
  }
});

Deno.test("search rejects a one-character query and a silly limit", async () => {
  const user = await newNamedUser("Ana");
  for (
    const [query, field] of [["/search?q=a", "q"], ["/search", "q"], [
      "/search?q=Ribs&limit=500",
      "limit",
    ]]
  ) {
    const res = await call("tracks", query, { token: user.token });
    assertEquals(res.status, 400, query);
    assertEquals(res.body.error.code, "INVALID_INPUT");
    assertEquals(res.body.error.details, { field });
  }
});

Deno.test("an empty result is a 200, not a 404", async () => {
  const user = await newNamedUser("Ana");
  const res = await call("tracks", "/search?q=zzzznothingmatchesthis", { token: user.token });
  assertEquals(res.status, 200, "'No songs matched that' is a screen state, not a failed request");
  assertEquals(res.body.data.results, []);
});

Deno.test("the catalog is closed to anonymous and to unnamed callers", async () => {
  const anonymous = await call("tracks", "/search?q=Ribs");
  assertEquals(anonymous.status, 401);
  assertEquals(anonymous.body.error.code, "UNAUTHENTICATED");

  // Signed in but not through onboarding: search is billed against our Apple quota and there
  // is no reason for a half-registered account to spend it.
  const unnamed = await newUser();
  const res = await call("tracks", "/search?q=Ribs", { token: unnamed.token });
  assertEquals(res.status, 409);
  assertEquals(res.body.error.code, "NO_PROFILE");
});

Deno.test("POST /tracks/resolve takes all three input forms", async () => {
  const user = await newNamedUser("Ana");

  for (
    const body of [
      { apple_music_id: "1440818664" },
      { isrc: "USUM71311296" },
      { isrc: "us-um7-13-11296" },
      { spotify_url: "https://open.spotify.com/track/2QjOHCTQ1JF3zJyfWY7EMU?si=x" },
      { spotify_url: "spotify:track:2QjOHCTQ1JF3zJyfWY7EMU" },
      { spotify_url: "https://music.apple.com/us/album/pure-heroine/1/?i=1440818664" },
    ]
  ) {
    const res = await call("tracks", "/resolve", { method: "POST", token: user.token, body });
    assertEquals(res.status, 200, JSON.stringify(body));
    assertEquals(keysOf(res.body.data), TRACK_KEYS);
    // Every one of them is the same recording, and every one of them keys the same way. That
    // is what makes the duplicate-track rule work across members (docs/02 §4.3).
    assertEquals(res.body.data.track_key, "isrc:USUM71311296", JSON.stringify(body));
  }
});

Deno.test("resolve refuses a URL that is not a song link — the SSRF boundary", async () => {
  const user = await newNamedUser("Ana");
  for (
    const hostile of [
      "http://169.254.169.254/latest/meta-data/",
      "http://127.0.0.1:54421/functions/v1/me",
      "https://open.spotify.com.evil.test/track/2QjOHCTQ1JF3zJyfWY7EMU",
      "file:///etc/passwd",
      "https://music.apple.com/us/artist/lorde/602767352",
    ]
  ) {
    const res = await call("tracks", "/resolve", {
      method: "POST",
      token: user.token,
      body: { spotify_url: hostile },
    });
    assertEquals(res.status, 400, hostile);
    assertEquals(res.body.error.code, "INVALID_INPUT");
  }
});

Deno.test("resolve needs exactly one input field", async () => {
  const user = await newNamedUser("Ana");
  const none = await call("tracks", "/resolve", { method: "POST", token: user.token, body: {} });
  assertEquals(none.status, 400);
  assertEquals(none.body.error.details, { field: "track" });

  const both = await call("tracks", "/resolve", {
    method: "POST",
    token: user.token,
    body: { isrc: "USUM71311296", apple_music_id: "1440818664" },
  });
  assertEquals(both.status, 400);
  assertEquals(both.body.error.details, { field: "track" });

  // docs/14 §7: an unknown key is rejected, not ignored.
  const extra = await call("tracks", "/resolve", {
    method: "POST",
    token: user.token,
    body: { isrc: "USUM71311296", title: "Ribs" },
  });
  assertEquals(extra.status, 400);
  assertEquals(extra.body.error.details, { field: "title" });
});

Deno.test("a Spotify-only track is refused rather than stored", async () => {
  const user = await newNamedUser("Ana");
  const res = await call("tracks", "/resolve", {
    method: "POST",
    token: user.token,
    body: { spotify_url: "https://open.spotify.com/track/4orphanORPHANorphan01" },
  });
  // docs/06 §4: the game needs a preview and a stable artwork URL, and a track Apple does not
  // carry has neither. `resolve.error.notfound` is the copy the client shows on this code.
  assertEquals(res.status, 400);
  assertEquals(res.body.error.code, "INVALID_INPUT");
});

Deno.test("a track with no preview and a track with no ISRC both resolve", async () => {
  const user = await newNamedUser("Ana");

  const noPreview = await call("tracks", "/resolve", {
    method: "POST",
    token: user.token,
    body: { apple_music_id: "9000000005" },
  });
  assertEquals(noPreview.status, 200);
  assertEquals(noPreview.body.data.preview_url, null, "the card just has no play control");

  const noIsrc = await call("tracks", "/resolve", {
    method: "POST",
    token: user.token,
    body: { apple_music_id: "9000000001" },
  });
  assertEquals(noIsrc.status, 200);
  assertEquals(noIsrc.body.data.isrc, null);
  assertEquals(noIsrc.body.data.track_key, "am:9000000001");
});
