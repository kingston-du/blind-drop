// demo.test.ts — the App Review demo group, over HTTP. tasks/E16-01.
//
// The state machine itself is proved in `tests/db/demo_mode.sql`, which can move the clock and
// therefore watch every transition. What only an HTTP test can prove is the half that lives in
// `rounds/index.ts`: that dropping a song arms the reveal, that finishing a guess sheet arms
// the score, that a partial sheet gets the longer backstop — and, more important than any of
// those, that **none of it changes what comes back on the wire**.
//
// That last one is the point of the byte-for-byte comparisons below. A demo group is a
// scheduling arrangement, not a different API: the same routes, the same key sets, the same
// bodies. If a field ever appears here that a real group does not get, the golden files in
// `npm run audit:leak` will not catch it — they only ever see real groups — so this file is
// where that regression has to fail.

import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  call,
  keysOf,
  newGroupOwner,
  newMember,
  serviceRpc,
  setJoinedAt,
  type TestUser,
  zoneWhereLocalHourIs,
} from "./_harness.ts";

const TRACKS = ["1440818664", "1440765580", "1452874255"];

interface Room {
  owner: TestUser;
  members: TestUser[];
  roundId: string;
}

/**
 * Three people in a group, everyone but the owner already dropped.
 *
 * Set up at 17:00 local with a reveal at 18:00, the same arrangement `reveal.test.ts` uses:
 * `ensure_rounds()` will not create a round whose reveal has already gone by, so the group's
 * local hour has to be before its reveal hour for there to be a round at all.
 *
 * `demo` marks the group through the seed-only `make_demo_group()`. There is deliberately no
 * API route that can do this — `groups.is_demo` comes from a pilot cohort and nothing else
 * (20260815090000) — and that is the property the whole demo environment rests on, so the test
 * reaches for the same kind of local-only helper `tickRoundsAt` uses rather than an endpoint.
 */
async function room(name: string, opts: { demo: boolean }): Promise<Room> {
  const { user: owner, group } = await newGroupOwner("Ana", {
    name,
    timezone: zoneWhereLocalHourIs(17),
    reveal_hour: 18,
    cue_cadence: 0,
  });

  const members: TestUser[] = [];
  for (const displayName of ["Ben", "Cal"]) {
    members.push(await newMember(group.invite_code as string, displayName));
  }

  // The others drop first, so the owner's own submission is the one the room is waiting on —
  // which is what makes the reveal arming observable on a single request. They drop *before*
  // the group is marked, because `demo_arm` fires on whoever submits and the assertions below
  // want to see a round still carrying its real schedule.
  for (const [i, member] of members.entries()) {
    const sealed = await call("rounds", "/current/submission", {
      method: "PUT",
      token: member.token,
      body: { apple_music_id: TRACKS[i + 1] },
    });
    assertEquals(sealed.status, 200);
  }

  // An hour of membership behind everyone. In the real demo group `demo_provision()` backdates
  // the same column for the same reason: `cannotGuessReason()` refuses anyone whose
  // `joined_at` is not strictly before the reveal, and a group created four seconds ago is
  // within the rounding error of a reveal these tests then pull into the immediate past.
  const anHourAgo = new Date(Date.now() - 3_600_000);
  for (const user of [owner, ...members]) await setJoinedAt(user.id, anHourAgo);

  if (opts.demo) await serviceRpc("make_demo_group", { p_group_id: group.id });

  const current = await call("rounds", "/current", { token: owner.token });
  assertEquals(current.status, 200);
  return { owner, members, roundId: current.body.data.round_id as string };
}

/** Seconds from the response's own `server_now` to `at`. Measured against the server's clock
 *  rather than the test host's, so a slow round trip cannot make an assertion flap. */
function secondsAway(body: { server_now: string }, at: string): number {
  return (new Date(at).getTime() - new Date(body.server_now).getTime()) / 1000;
}

async function currentRound(user: TestUser): Promise<{ data: Record<string, string> } & {
  server_now: string;
}> {
  const res = await call("rounds", "/current", { token: user.token });
  assertEquals(res.status, 200);
  return res.body;
}

Deno.test("dropping a song in a demo group brings the reveal seconds away", async () => {
  const { owner } = await room("Demo Cove", { demo: true });

  // `zoneWhereLocalHourIs(17)` lands the group somewhere in the 17:00 hour, not on the hour,
  // so the honest bound here is "minutes away, not seconds" rather than a full hour.
  const before = await currentRound(owner);
  const untouched = secondsAway(before, before.data.reveals_at);
  assert(
    untouched > 120,
    `before the drop a demo round carries the real schedule; reveal was ${untouched}s away`,
  );

  const sealed = await call("rounds", "/current/submission", {
    method: "PUT",
    token: owner.token,
    body: { apple_music_id: TRACKS[0] },
  });
  assertEquals(sealed.status, 200);

  const after = await currentRound(owner);
  const seconds = secondsAway(after, after.data.reveals_at);
  assert(seconds > 0 && seconds <= 12, `reveal is ${seconds}s away, expected 0 < s <= 12`);
  assertEquals(after.data.state, "open", "and it is still open — the countdown has to run");
});

Deno.test("the same drop in a real group leaves the schedule exactly where it was", async () => {
  const { owner } = await room("Real Cove", { demo: false });

  const before = await currentRound(owner);
  const sealed = await call("rounds", "/current/submission", {
    method: "PUT",
    token: owner.token,
    body: { apple_music_id: TRACKS[0] },
  });
  assertEquals(sealed.status, 200);

  const after = await currentRound(owner);
  assertEquals(after.data.reveals_at, before.data.reveals_at);
  assertEquals(after.data.opens_at, before.data.opens_at);
  assertEquals(after.data.scores_at, before.data.scores_at);
});

Deno.test("a demo group's payloads are the same shape a real group gets", async () => {
  const demo = await room("Demo Shape", { demo: true });
  const real = await room("Real Shape", { demo: false });

  const body = { apple_music_id: TRACKS[0] };
  const demoSealed = await call("rounds", "/current/submission", {
    method: "PUT",
    token: demo.owner.token,
    body,
  });
  const realSealed = await call("rounds", "/current/submission", {
    method: "PUT",
    token: real.owner.token,
    body,
  });

  assertEquals(demoSealed.status, realSealed.status);
  // The whole submission body, not just its keys: same track, same shape, same everything.
  // `sealed_at` is the only value that legitimately differs, and it is a timestamp of the
  // caller's own action either way.
  assertEquals(
    { ...demoSealed.body.data, sealed_at: null },
    { ...realSealed.body.data, sealed_at: null },
  );

  const demoRound = await currentRound(demo.owner);
  const realRound = await currentRound(real.owner);
  assertEquals(keysOf(demoRound.data), keysOf(realRound.data));
  assertEquals(keysOf(demoRound), keysOf(realRound));
});

Deno.test("the guess sheet arms the score: twenty seconds complete, three minutes partial", async () => {
  const { owner, members } = await room("Demo Guesses", { demo: true });
  assertEquals(
    (await call("rounds", "/current/submission", {
      method: "PUT",
      token: owner.token,
      body: { apple_music_id: TRACKS[0] },
    })).status,
    200,
  );

  // Run the seal countdown out rather than waiting twelve seconds for it: `demo_arm` with a
  // negative offset is the same call the handler makes, and the reveal itself still happens
  // where it always does — inside `demo_tick()`, on the next `GET /current`. The client's real
  // countdown triggers that same refetch; this just does not spend twelve seconds of suite
  // time proving that a clock ticks.
  const { roundId } = { roundId: (await currentRound(owner)).data.round_id };
  await serviceRpc("demo_arm", { p_round_id: roundId, p_seconds: -1 });

  const revealed = await currentRound(owner);
  assertEquals(revealed.data.state, "revealed", "the demo round reveals on the next fetch");

  const cards = (revealed.data as unknown as { cards: { card_no: number }[] }).cards;
  const myCardNo = (revealed.data as unknown as { my_card_no: number }).my_card_no;
  const others = cards.map((c) => c.card_no).filter((n) => n !== myCardNo);
  assertEquals(others.length, 2, "three submitters, so two cards to name");

  // One of two named: a partial sheet, and the longer backstop.
  const partial = await call("rounds", "/current/guesses", {
    method: "PUT",
    token: owner.token,
    body: { assignments: [{ card_no: others[0], guessed_user_id: members[0].id }] },
  });
  assertEquals(partial.status, 200);

  const afterPartial = await currentRound(owner);
  const partialSeconds = secondsAway(afterPartial, afterPartial.data.scores_at);
  assert(
    partialSeconds > 20 && partialSeconds <= 180,
    `partial sheet scores in ${partialSeconds}s, expected 20 < s <= 180`,
  );

  // Both named: the sheet is complete, which is the request `RevealStore.lockIn()` sends.
  const complete = await call("rounds", "/current/guesses", {
    method: "PUT",
    token: owner.token,
    body: {
      assignments: [
        { card_no: others[0], guessed_user_id: members[0].id },
        { card_no: others[1], guessed_user_id: members[1].id },
      ],
    },
  });
  assertEquals(complete.status, 200);

  const afterComplete = await currentRound(owner);
  const completeSeconds = secondsAway(afterComplete, afterComplete.data.scores_at);
  assert(
    completeSeconds > 0 && completeSeconds <= 20,
    `complete sheet scores in ${completeSeconds}s, expected 0 < s <= 20`,
  );

  // And the loop closes: the answers land, from the same route everybody else uses.
  await serviceRpc("demo_arm", { p_round_id: roundId, p_seconds: -1 });
  const scored = await currentRound(owner);
  assertEquals(scored.data.state, "scored");

  const results = await call("rounds", `/${roundId}/results`, { token: owner.token });
  assertEquals(results.status, 200);
});
