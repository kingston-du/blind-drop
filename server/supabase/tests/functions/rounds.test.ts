// rounds.test.ts — the blind window, over HTTP. tasks/E04-01, E04-02.
//
// The golden-file key assertions live in `leak.test.ts` (E04-03) and the timing and lockdown
// probes in `audit:leak` (E04-04). This file is the behaviour underneath them: what a
// submission does, what `GET /current` returns in each phase it currently serves, and the two
// properties that make the `open` payload safe — that it is identical for everybody except
// their own song, and that its length does not move when other people submit.

import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  call,
  isRfc3339Z,
  keysOf,
  newGroupOwner,
  newMember,
  serviceRpc,
  type TestUser,
  tickRoundsAt,
  zoneWhereLocalHourIs,
} from "./_harness.ts";

/** docs/04 §4: the `open` payload, in full. There is no other key. */
const ROUND_KEYS = [
  "local_date",
  "my_submission",
  "opens_at",
  "reveals_at",
  "round_id",
  "scores_at",
  "state",
].sort();

const RIBS = { apple_music_id: "1440818664" };
const NIGHTS = { apple_music_id: "1440765580" };

/** A group whose round is mid-`open`: opened at 10:00 local, reveals at 20:00, and it is
 *  currently noon there. Real time, real timezone, no clock faked anywhere. The cue is off so
 *  the `open` payload keeps the exact minimal key set this file asserts — cued rounds get their
 *  own assertions in `leak.test.ts`. */
function openGroup(name = "The Cove") {
  return newGroupOwner("Ana", {
    name,
    timezone: zoneWhereLocalHourIs(12),
    reveal_hour: 20,
    cue_cadence: 0,
  });
}

/**
 * A group about to reveal: it is 17:00 in its timezone and `reveals_at` is 18:00 local.
 *
 * The round has to be created *before* its reveal, because `ensure_rounds()` refuses to
 * materialise a round whose reveal is already behind us (0004). So the group is set up an hour
 * early and `revealLate()` runs the scheduler two hours on — 19:00 local, past `reveals_at`
 * and short of `scores_at`, still the same local date. That is the window in which a round is
 * `revealed`, or `voided` if fewer than three people dropped (docs/02 §2).
 */
function aboutToRevealGroup(name = "The Late Cove") {
  return newGroupOwner("Ana", {
    name,
    timezone: zoneWhereLocalHourIs(17),
    reveal_hour: 18,
    cue_cadence: 0,
  });
}

/** Runs the real scheduler at 19:00 in an `aboutToRevealGroup`'s timezone. */
function revealLate() {
  return tickRoundsAt(2);
}

async function submit(user: TestUser, body: Record<string, string>) {
  return await call("rounds", "/current/submission", { method: "PUT", token: user.token, body });
}

async function current(user: TestUser) {
  return await call("rounds", "/current", { token: user.token });
}

async function submitTo(user: TestUser, groupId: string, body: Record<string, string>) {
  return await call("rounds", `/${groupId}/current/submission`, {
    method: "PUT",
    token: user.token,
    body,
  });
}

/** A second circle for an already-grouped owner, in the same timezone as `like` so the two
 *  share a group-local "tonight" (tasks/E18-03). */
async function secondCircle(owner: TestUser, name: string, like: { timezone: string }) {
  const res = await call("groups", "/", {
    method: "POST",
    token: owner.token,
    body: { name, timezone: like.timezone, reveal_hour: 20 },
  });
  assertEquals(res.status, 200, `could not create ${name}`);
  return res.body.data as Record<string, unknown>;
}

// ─── E04-02 · the shape ──────────────────────────────────────────────────────

Deno.test("GET /rounds/current during open has exactly the documented key set", async () => {
  const { user } = await openGroup();
  const res = await current(user);

  assertEquals(res.status, 200);
  assertEquals(keysOf(res.body), ["data", "server_now"]);
  assertEquals(keysOf(res.body.data), ROUND_KEYS);
  assertEquals(res.body.data.state, "open");
  assertEquals(res.body.data.my_submission, null, "nothing dropped yet");
  for (const field of ["opens_at", "reveals_at", "scores_at"]) {
    assert(isRfc3339Z(res.body.data[field]), `${field} is not RFC 3339 UTC`);
  }
  // docs/02 §1: the guess window is exactly two hours and open is exactly ten.
  const t = (f: string) => Date.parse(res.body.data[f] as string);
  assertEquals(t("scores_at") - t("reveals_at"), 2 * 3600_000);
  assertEquals(t("reveals_at") - t("opens_at"), 10 * 3600_000);
});

Deno.test("the key set does not grow once the caller has submitted", async () => {
  const { user } = await openGroup();
  await submit(user, RIBS);
  const res = await current(user);

  assertEquals(keysOf(res.body.data), ROUND_KEYS);
  assertEquals(keysOf(res.body.data.my_submission), ["sealed_at", "track"]);
  assertEquals(res.body.data.my_submission.track.title, "Ribs");
  assert(isRfc3339Z(res.body.data.my_submission.sealed_at));
});

Deno.test("a submitter and a non-submitter differ only in my_submission", async () => {
  const { user: ana, group } = await openGroup();
  const ben = await newMember(group.invite_code as string, "Ben");
  await submit(ana, RIBS);

  const forAna = (await current(ana)).body.data;
  const forBen = (await current(ben)).body.data;

  assertEquals(keysOf(forAna), keysOf(forBen));
  // Everything about the round itself is identical — it is the same round.
  for (const field of ["round_id", "local_date", "state", "opens_at", "reveals_at", "scores_at"]) {
    assertEquals(forAna[field], forBen[field], field);
  }
  assert(forAna.my_submission !== null, "Ana dropped a song and gets it back");
  assertEquals(forBen.my_submission, null, "Ben did not, and learns nothing about Ana");
});

Deno.test("the payload length does not move with the number of other submitters", async () => {
  // docs/14 §3: response size must not vary with participation, because a length is a count
  // with extra steps. Ana's own song is held fixed; everyone else's arrival must be invisible.
  const { user: ana, group } = await openGroup("Byte Length");
  const code = group.invite_code as string;
  await submit(ana, RIBS);

  const lengths: number[] = [];
  const measure = async () => {
    const res = await call("rounds", "/current", { token: ana.token });
    // `server_now` moves every second and is the one field that legitimately varies; blank it
    // so what is compared is the part of the payload that is supposed to be constant.
    const body = { ...res.body, server_now: "" };
    lengths.push(JSON.stringify(body).length);
  };

  await measure(); // 0 other submitters
  const others: TestUser[] = [];
  for (const count of [1, 5, 11]) {
    while (others.length < count) {
      const member = await newMember(code, `M${others.length}`);
      others.push(member);
      // Deliberately a *different* track from Ana's and from each other where possible, so a
      // leak would have something to leak.
      await submit(member, others.length % 2 === 0 ? RIBS : NIGHTS);
    }
    await measure();
  }

  assertEquals(
    new Set(lengths).size,
    1,
    `open payload length varied with participation: ${lengths.join(", ")}`,
  );
});

Deno.test("a voided round returns the caller's own song and no count of anyone else's", async () => {
  // Two submissions, which is one short of the three docs/02 §3 requires, and a reveal hour
  // that has already passed in the group's own timezone. The next tick voids it.
  const { user: ana, group } = await aboutToRevealGroup();
  const ben = await newMember(group.invite_code as string, "Ben");
  await submit(ana, RIBS);
  await submit(ben, NIGHTS);
  await revealLate();

  const forAna = (await current(ana)).body.data;
  assertEquals(forAna.state, "voided");
  assertEquals(keysOf(forAna), ROUND_KEYS, "voided is the same shape as open — no extra field");
  assertEquals(forAna.my_submission.track.title, "Ribs", "their song comes back, unseen");

  // Cal never dropped anything. What Cal must not be able to learn is that two people did.
  const cal = await newMember(group.invite_code as string, "Cal");
  const forCal = (await current(cal)).body.data;
  assertEquals(keysOf(forCal), ROUND_KEYS);
  assertEquals(forCal.my_submission, null);
  assert(
    !JSON.stringify(forCal).includes("Ribs") && !JSON.stringify(forCal).includes("Nights"),
    "a voided payload must not carry anybody else's song",
  );
});

Deno.test("submitting into a voided round is ROUND_VOIDED, and the body carries nothing else", async () => {
  const { user: ana } = await aboutToRevealGroup();
  await submit(ana, RIBS);
  await revealLate();

  const res = await submit(ana, NIGHTS);
  assertEquals(res.status, 409);
  assertEquals(res.body.error.code, "ROUND_VOIDED");
  // docs/14 §3: a phase error may not become "3 of 8 submitted, wait for reveal".
  assertEquals(keysOf(res.body.error), ["code", "message"]);
});

Deno.test("submitting into a revealed round is WRONG_PHASE carrying only the state", async () => {
  const { user: ana, group } = await aboutToRevealGroup("Revealed");
  const ben = await newMember(group.invite_code as string, "Ben");
  const cal = await newMember(group.invite_code as string, "Cal");
  await submit(ana, RIBS);
  await submit(ben, NIGHTS);
  await submit(cal, { apple_music_id: "1452874255" });
  await revealLate();

  assertEquals((await current(ana)).body.data.state, "revealed", "three drops is enough");

  const res = await submit(ana, NIGHTS);
  assertEquals(res.status, 409);
  assertEquals(res.body.error.code, "WRONG_PHASE");
  assertEquals(res.body.error.state, "revealed");
  assertEquals(keysOf(res.body.error), ["code", "message", "state"]);
});

// ─── E04-01 · the submission ─────────────────────────────────────────────────

Deno.test("PUT /rounds/current/submission returns the resolved track", async () => {
  const { user } = await openGroup();
  const res = await submit(user, RIBS);

  assertEquals(res.status, 200);
  assertEquals(keysOf(res.body.data), ["sealed_at", "track"]);
  assertEquals(res.body.data.track.track_key, "isrc:USUM71311296");
  // Spotify resolved inside the 700ms budget, so the sealed card can show the link at once.
  assertEquals(res.body.data.track.spotify_id, "2QjOHCTQ1JF3zJyfWY7EMU");
});

Deno.test("the same body twice produces one row and the same response", async () => {
  const { user } = await openGroup();
  const first = await submit(user, RIBS);
  const second = await submit(user, RIBS);

  assertEquals(second.status, 200);
  // docs/04 §4 wants idempotence, and `sealed_at` is when the currently-sealed thing was
  // sealed. Re-sending the same song has not sealed anything new, so it must not move.
  assertEquals(second.body.data, first.body.data);
  assertEquals((await current(user)).body.data.my_submission.sealed_at, first.body.data.sealed_at);
});

Deno.test("replacing a song moves sealed_at; there is no un-submitting", async () => {
  const { user } = await openGroup();
  const first = await submit(user, RIBS);
  await new Promise((r) => setTimeout(r, 1100)); // sealed_at has whole-second precision
  const second = await submit(user, NIGHTS);

  assertEquals(second.body.data.track.title, "Nights");
  assert(
    Date.parse(second.body.data.sealed_at) > Date.parse(first.body.data.sealed_at),
    "a replacement is a new seal",
  );

  // docs/02 §3: "Once sealed, you are in the round." There is no DELETE route, and asking for
  // one gets the same NOT_FOUND as any other path that does not exist.
  const deleted = await call("rounds", "/current/submission", {
    method: "DELETE",
    token: user.token,
  });
  assertEquals(deleted.status, 404);
});

Deno.test("a duplicate track is never rejected, and the response gives no hint of one", async () => {
  const { user: ana, group } = await openGroup("Duplicates");
  const ben = await newMember(group.invite_code as string, "Ben");

  const first = await submit(ana, RIBS);
  const duplicate = await submit(ben, RIBS);

  assertEquals(duplicate.status, 200, "the rejection itself would be the leak (docs/02 §3)");
  assertEquals(keysOf(duplicate.body.data), keysOf(first.body.data));
  assertEquals(duplicate.body.data.track, first.body.data.track, "byte-identical track payload");

  // The strong form: Ben's response to a song already in play is identical to Ana's response
  // to the same song when it was not, down to every field but the seal time. There is no
  // "already dropped" flag, no altered ordering, and nothing whose absence could be read as
  // one — which is the only way "never rejected" is actually true (docs/02 §3).
  assertEquals(
    { ...duplicate.body.data, sealed_at: null },
    { ...first.body.data, sealed_at: null },
  );

  // And a unique song produces the same shape, so shape carries no signal either way.
  const cal = await newMember(group.invite_code as string, "Cal");
  const unique = await submit(cal, NIGHTS);
  assertEquals(keysOf(unique.body.data), keysOf(duplicate.body.data));
  assertEquals(keysOf(unique.body.data.track), keysOf(duplicate.body.data.track));
});

// ─── E18-03 · the same track, twice, across circles ─────────────────────────

Deno.test(
  "the same track twice tonight is refused only when the two circles share another member",
  async () => {
    const { user: ana, group: west } = await openGroup("Overlap West");
    const ben = await newMember(west.invite_code as string, "Ben");

    const north = await secondCircle(ana, "Overlap North", west as { timezone: string });
    const joinedNorth = await call("groups", "/join", {
      method: "POST",
      token: ben.token,
      body: { invite_code: north.invite_code },
    });
    assertEquals(joinedNorth.status, 200, "Ben is in both West and North — the overlap");

    const east = await secondCircle(ana, "Overlap East", west as { timezone: string });
    // Nobody joins East besides Ana: it shares nothing with West but the submitter herself.

    const inWest = await submitTo(ana, west.id as string, RIBS);
    assertEquals(inWest.status, 200);

    const inEast = await submitTo(ana, east.id as string, RIBS);
    assertEquals(
      inEast.status,
      200,
      "East shares nobody with West but Ana — no overlap, no refusal",
    );

    const inNorth = await submitTo(ana, north.id as string, RIBS);
    assertEquals(inNorth.status, 409);
    assertEquals(inNorth.body.error.code, "TRACK_ALREADY_USED");
    assertEquals(
      keysOf(inNorth.body.error),
      ["code", "message"],
      "the refusal names no circle and no person — nothing beyond the fixed copy",
    );

    // A different track in North is unaffected — the refusal is about the track, not the
    // circle pair.
    const differentTrack = await submitTo(ana, north.id as string, NIGHTS);
    assertEquals(differentTrack.status, 200);
  },
);

Deno.test("a Spotify timeout does not fail the submission", async () => {
  // The fixture makes this ISRC's lookup outlast any budget the app allows. docs/06 §5:
  // sealing a song must never fail because Spotify was slow.
  const { user } = await openGroup("Slow Spotify");
  const started = performance.now();
  const res = await submit(user, { apple_music_id: "9000000003" });
  const elapsed = performance.now() - started;

  assertEquals(res.status, 200);
  assertEquals(res.body.data.track.spotify_id, null, "no link yet — the backfill will try again");
  assertEquals(res.body.data.track.spotify_url, null);
  assertEquals(res.body.data.track.title, "Slow Lookup");
  assert(elapsed < 5_000, `the submission took ${Math.round(elapsed)}ms waiting on Spotify`);
});

Deno.test("a track with no ISRC seals, and is never chased on Spotify", async () => {
  const { user } = await openGroup("No ISRC");
  const res = await submit(user, { apple_music_id: "9000000001" });

  assertEquals(res.status, 200);
  assertEquals(res.body.data.track.track_key, "am:9000000001");
  assertEquals(res.body.data.track.spotify_id, null);
});

Deno.test("submission validates its input the same way resolve does", async () => {
  const { user } = await openGroup("Validation");

  const none = await submit(user, {});
  assertEquals(none.status, 400);
  assertEquals(none.body.error.details, { field: "track" });

  const hostile = await submit(user, { spotify_url: "http://169.254.169.254/latest/meta-data/" });
  assertEquals(hostile.status, 400);
  assertEquals(hostile.body.error.code, "INVALID_INPUT");

  const unknownKey = await call("rounds", "/current/submission", {
    method: "PUT",
    token: user.token,
    body: { apple_music_id: "1440818664", sealed_at: "2020-01-01T00:00:00Z" },
  });
  assertEquals(unknownKey.status, 400, "an unknown key is rejected, not ignored (docs/14 §7)");
  assertEquals(unknownKey.body.error.details, { field: "sealed_at" });
});

Deno.test("submission is rate limited at 20 a minute, with a Retry-After", async () => {
  // docs/04 §8. Twenty is far above changing your mind and far below anything that costs us
  // an Apple lookup a second. The counter is per user per route and never per group — a
  // group-shared counter would let one member detect another's activity by watching for
  // throttling, which is a real side channel (docs/14 §8).
  const { user } = await openGroup("Rate Limited");
  for (let i = 0; i < 20; i += 1) {
    const res = await submit(user, i % 2 === 0 ? RIBS : NIGHTS);
    assertEquals(res.status, 200, `request ${i + 1} of 20 should still be allowed`);
  }

  const blocked = await submit(user, RIBS);
  assertEquals(blocked.status, 429);
  assertEquals(blocked.body.error.code, "RATE_LIMITED");
  const retryAfter = Number(blocked.headers.get("retry-after"));
  assert(
    retryAfter > 0 && retryAfter <= 60,
    `Retry-After was ${blocked.headers.get("retry-after")}`,
  );
});

Deno.test("the round is closed to anonymous callers and to people with no group", async () => {
  const anonymous = await call("rounds", "/current");
  assertEquals(anonymous.status, 401);
  assertEquals(anonymous.body.error.code, "UNAUTHENTICATED");

  const { user, group } = await openGroup("Leavers");
  await call("groups", "/current/leave", { method: "POST", token: user.token });

  // docs/14 §5: an ex-member's still-valid token gets NO_GROUP, not their old round.
  const after = await current(user);
  assertEquals(after.status, 409);
  assertEquals(after.body.error.code, "NO_GROUP");
  assert(!JSON.stringify(after.body).includes(group.id as string));

  const submitAfter = await submit(user, RIBS);
  assertEquals(submitAfter.status, 409);
  assertEquals(submitAfter.body.error.code, "NO_GROUP");
});

// ─── the dark hours ──────────────────────────────────────────────────────────
// docs/18-CUES.md §7. Between local midnight and `opens_at`, `GET /current` already returns the
// *coming* night's round and the app draws "Tonight's round is done." over it. The cue on the
// base keys there is the brief for a round nobody has dropped against yet, so the screen shows
// `previous_cue` — the night it is actually talking about — instead.

/** A group in its dark hours: 03:00 local, reveal at 20:00, so `opens_at` (10:00) is still
 *  ahead. Real time, real timezone, nothing faked. Cues on every night so the round the seed
 *  helper adds behind it can carry one. */
function darkHoursGroup(name = "The Small Hours") {
  return newGroupOwner("Ana", {
    name,
    timezone: zoneWhereLocalHourIs(3),
    reveal_hour: 20,
    cue_cadence: 1,
  });
}

Deno.test("the dark hours carry the previous night's cue, and never the coming one", async () => {
  const { user, group } = await darkHoursGroup();
  // One read first: `POST /groups` does not materialise a round, `GET /current` does (it calls
  // `ensure_rounds()` on a miss). The seed helper dates its row one day before the group's
  // earliest round, so it needs that round to exist.
  await current(user);
  await serviceRpc("seed_previous_round", {
    p_group_id: group.id,
    p_prompt_key: "song_you_hate",
    p_prompt: "A song you hate",
  });

  const res = await current(user);
  assertEquals(res.status, 200);
  assertEquals(res.body.data.state, "open");
  // The round on the wire is the coming night's, and it has not opened yet.
  assert(new Date(res.body.data.opens_at as string) > new Date());
  assertEquals(res.body.data.previous_cue, { key: "song_you_hate", text: "A song you hate" });
  // And the two are genuinely different rounds' cues — the point of the whole key.
  assert(
    (res.body.data.cue as { text: string } | undefined)?.text !== "A song you hate",
    "the coming round drew the same cue as the seeded one; the fixture is not proving anything",
  );
  // The seeded night is `voided`, so it has a cue and no results — and therefore no link to
  // them. The two keys are gated separately and this is the half that proves it.
  assert(!("previous_round_id" in (res.body.data as Record<string, unknown>)));
});

Deno.test("an admin-written cue still carries a key — the shape old builds decode", async () => {
  // The regression from 2026-09-10. `set_round_cue` writes `prompt_key = null` by design, and
  // for one deploy `cueDTO` answered that by omitting `key` from the wire. Shipped builds
  // decode `key` as a non-optional String, and because the cue is nested inside the round
  // payload the decode failure took the whole `GET /rounds/current` response down — users saw
  // `error.generic`, not a missing cue. Nothing covered a keyless cue's shape, which is why it
  // shipped; this is that cover.
  const { user, group } = await darkHoursGroup("Hand Written");
  await current(user);
  await serviceRpc("seed_previous_round", {
    p_group_id: group.id,
    p_prompt_key: null,
    p_prompt: "A song you would put on at 3am",
  });

  const res = await current(user);
  assertEquals(res.status, 200);
  const cue = res.body.data.previous_cue as Record<string, unknown>;
  // Present, a string, and never null — an explicit null fails a non-optional String just as
  // hard as a missing field does.
  assert("key" in cue, "a custom cue must still carry `key`; omitting it breaks shipped builds");
  assertEquals(typeof cue.key, "string");
  assertEquals(cue, { key: "custom", text: "A song you would put on at 3am" });
});

Deno.test("a scored night behind the dark hours is linkable; a voided one is not", async () => {
  const { user, group } = await darkHoursGroup("Linkable");
  await current(user);
  // Uncued *and* scored: the two keys are independent in both directions, and this is the
  // direction the cue test cannot reach — results to link to, no cue to show.
  const previousID = await serviceRpc("seed_previous_round", {
    p_group_id: group.id,
    p_prompt_key: null,
    p_prompt: null,
    p_state: "scored",
  });
  assert(typeof previousID === "string");

  const res = await current(user);
  assertEquals(res.status, 200);
  assertEquals(res.body.data.previous_round_id, previousID);
  // It names the night that just ended, not the one on the wire.
  assert(res.body.data.round_id !== previousID);
  assert(!("previous_cue" in (res.body.data as Record<string, unknown>)));
});

Deno.test("a round with nothing behind it says nothing, and an open round never says it", async () => {
  // A circle's first night: the dark hours with no previous round at all. Absence is silent —
  // no `previous_cue` key, the same way an uncued round ships no `cue` key.
  const first = await darkHoursGroup("First Night");
  const firstRes = await current(first.user);
  assertEquals(firstRes.status, 200);
  assert(!("previous_cue" in (firstRes.body.data as Record<string, unknown>)));
  assert(!("previous_round_id" in (firstRes.body.data as Record<string, unknown>)));

  // And once the round has opened, both keys are gone even with a finished round behind it: the
  // blind window's payload is byte-for-byte what `ROUND_KEYS` has always pinned (docs/14 §3).
  // Seeded `scored` so the round behind it is the linkable kind — the strongest version of the
  // assertion, since it is the case that would have had something to say.
  const { user, group } = await openGroup("Opened Cove");
  await current(user);
  await serviceRpc("seed_previous_round", {
    p_group_id: group.id,
    p_prompt_key: "song_you_hate",
    p_prompt: "A song you hate",
    p_state: "scored",
  });
  const opened = await current(user);
  assertEquals(opened.status, 200);
  assertEquals(keysOf(opened.body.data), ROUND_KEYS);
});
