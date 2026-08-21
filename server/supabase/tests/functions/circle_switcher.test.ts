// circle_switcher.test.ts — `E18-02`. docs/04 §3, docs/02 §2, CLAUDE.md §2.1.
//
// `GET /groups` is the whole payload the switcher gets: one row per circle the caller holds,
// each naming only the caller's own next move. These tests check the four live states plus
// `voided`, that the row never grows with anyone else's participation, and that a circle the
// caller cannot see does not appear.

import { assert, assertEquals } from "jsr:@std/assert@1";
import { circleSummaryFields } from "../../functions/_shared/dto.ts";
import {
  call,
  keysOf,
  newGroupOwner,
  newMember,
  newNamedUser,
  setJoinedAt,
  type TestUser,
  tickRoundsAt,
  zoneWhereLocalHourIs,
} from "./_harness.ts";

const groups = (path: string, opts: Parameters<typeof call>[2] = {}) => call("groups", path, opts);
const rounds = (path: string, opts: Parameters<typeof call>[2] = {}) => call("rounds", path, opts);

const TRACKS = ["1440818664", "1440765580", "1452874255", "1440830827"];

function circleOf(
  body: { data: { circles: Record<string, unknown>[] } },
  id: string,
): Record<string, unknown> {
  const circles = body.data.circles;
  const found = circles.find((c) => c.id === id);
  assert(found, `no circle ${id} in the response: ${JSON.stringify(circles)}`);
  return found;
}

Deno.test("a user in no circle gets an empty list, not an error", async () => {
  const user = await newNamedUser("Ana");
  const res = await groups("/", { token: user.token });
  assertEquals(res.status, 200);
  assertEquals(res.body.data, { circles: [] });
});

Deno.test("GET /groups requires authentication like every other route", async () => {
  const res = await groups("/");
  assertEquals(res.status, 401);
});

Deno.test("open: no submission is `drop`, a sealed one is `sealed` — independent per circle", async () => {
  const { user, group: dropped } = await newGroupOwner("Ana", {
    name: "Switcher Drop",
    timezone: "UTC",
  });
  const sealed = (
    await groups("/", { method: "POST", token: user.token, body: { name: "Switcher Sealed", timezone: "UTC" } })
  ).body.data;

  const sub = await rounds(`/${sealed.id}/current/submission`, {
    method: "PUT",
    token: user.token,
    body: { apple_music_id: TRACKS[0] },
  });
  assertEquals(sub.status, 200);

  const res = await groups("/", { token: user.token });
  assertEquals(res.status, 200);

  const a = circleOf(res.body, dropped.id as string);
  assertEquals(a.my_state, "drop");
  assertEquals(a.needs_action, true);

  const b = circleOf(res.body, sealed.id as string);
  assertEquals(b.my_state, "sealed");
  assertEquals(b.needs_action, false);
});

Deno.test("a circle the caller left no longer appears", async () => {
  const user = await newNamedUser("Ana");
  const kept = (
    await groups("/", { method: "POST", token: user.token, body: { name: "Kept", timezone: "UTC" } })
  ).body.data;
  const left = (
    await groups("/", { method: "POST", token: user.token, body: { name: "Left", timezone: "UTC" } })
  ).body.data;

  const leave = await groups(`/${left.id}/leave`, { method: "POST", token: user.token });
  assertEquals(leave.status, 204);

  const res = await groups("/", { token: user.token });
  const ids = (res.body.data.circles as { id: string }[]).map((c) => c.id);
  assert(ids.includes(kept.id), "the circle still held is missing");
  assert(!ids.includes(left.id), "the left circle is still listed");
});

Deno.test("circles come back oldest-active-first, stating no priority of its own", async () => {
  const user = await newNamedUser("Ana");
  const first = (
    await groups("/", { method: "POST", token: user.token, body: { name: "First", timezone: "UTC" } })
  ).body.data;
  const second = (
    await groups("/", { method: "POST", token: user.token, body: { name: "Second", timezone: "UTC" } })
  ).body.data;

  // The newer circle needs action (nothing submitted); the older one does too — both do, by
  // construction, which is the point: if the server ranked by urgency, ordering would tell us
  // nothing here. It has to just be creation order.
  const res = await groups("/", { token: user.token });
  const ids = (res.body.data.circles as { id: string }[]).map((c) => c.id);
  assertEquals(ids, [first.id, second.id]);
});

/**
 * Owner plus one member per name in `memberNames`, revealed. Mirrors `reveal.test.ts`'s
 * helper, scoped down to what this file needs.
 *
 * Everyone submits **before** the tick except whoever is named in `nonSubmitters` — the round
 * needs three real submissions to reveal rather than void (docs/02 §2), so a non-submitter has
 * to be a deliberate exclusion from that set, never just "didn't get to it yet" after the fact.
 */
async function revealedCircle(
  name: string,
  memberNames: string[],
  nonSubmitters: string[] = [],
): Promise<{ owner: TestUser; group: Record<string, unknown>; members: TestUser[] }> {
  const { user: owner, group } = await newGroupOwner("Ana", {
    name,
    timezone: zoneWhereLocalHourIs(17),
    reveal_hour: 18,
  });
  const members: TestUser[] = [];
  for (const memberName of memberNames) {
    members.push(await newMember(group.invite_code as string, memberName));
  }

  const roster: [string, TestUser][] = [["Ana", owner], ...memberNames.map((n, i) => [n, members[i]] as [string, TestUser])];
  let trackIndex = 0;
  for (const [memberName, user] of roster) {
    if (nonSubmitters.includes(memberName)) continue;
    const sub = await call("rounds", "/current/submission", {
      method: "PUT",
      token: user.token,
      body: { apple_music_id: TRACKS[trackIndex % TRACKS.length] },
    });
    assertEquals(sub.status, 200, `${memberName} could not submit`);
    trackIndex += 1;
  }

  await tickRoundsAt(2);
  const check = await call("rounds", "/current", { token: owner.token });
  assertEquals(check.body.data.state, "revealed", `${name} did not reveal`);
  return { owner, group, members };
}

Deno.test("revealed and eligible: `guess`, needing action until the sheet is locked in", async () => {
  const { owner, group, members } = await revealedCircle("Switcher Guess", ["Ben", "Cal"]);

  const before = circleOf(
    (await groups("/", { token: owner.token })).body,
    group.id as string,
  );
  assertEquals(before.my_state, "guess");
  assertEquals(before.needs_action, true);

  const current = await rounds("/current", { token: owner.token });
  const cards = current.body.data.cards as { card_no: number }[];
  const myCardNo = current.body.data.my_card_no as number;
  const others = cards.filter((c) => c.card_no !== myCardNo);
  const lockIn = await rounds("/current/guesses", {
    method: "PUT",
    token: owner.token,
    body: {
      assignments: others.map((c, i) => ({
        card_no: c.card_no,
        guessed_user_id: members[i % members.length].id,
      })),
    },
  });
  assertEquals(lockIn.status, 200);

  const after = circleOf(
    (await groups("/", { token: owner.token })).body,
    group.id as string,
  );
  assertEquals(after.my_state, "guess");
  assertEquals(after.needs_action, false);
});

Deno.test("revealed, not a submitter: `guess` with nothing to do", async () => {
  const { group, members } = await revealedCircle(
    "Switcher Nonsub",
    ["Ben", "Cal", "Dee"],
    ["Dee"],
  );
  // Dee never submitted — the other three did, so the round still reveals.
  const dee = members[members.length - 1];

  const row = circleOf((await groups("/", { token: dee.token })).body, group.id as string);
  assertEquals(row.my_state, "guess");
  assertEquals(row.needs_action, false);
});

Deno.test("revealed, joined after the reveal: `guess` with nothing to do", async () => {
  // Mirrors `reveal.test.ts`'s "somebody who joined after the reveal sits the round out" —
  // `joinedLate` is checked before `!submission` in `circleCallerState`, same order as
  // `cannotGuessReason`, and this is the one branch nothing else in this file exercises.
  const { owner, group } = await revealedCircle("Switcher Joined Late", ["Ben", "Cal"]);
  const current = await rounds("/current", { token: owner.token });
  const revealsAt = current.body.data.reveals_at as string;

  const groupDTO = (await groups("/current", { token: owner.token })).body.data;
  const latecomer = await newMember(groupDTO.invite_code as string, "Late");
  // A minute past the reveal — a test cannot wait out the real gap between creation and reveal.
  await setJoinedAt(latecomer.id, new Date(Date.parse(revealsAt) + 60_000));

  const row = circleOf((await groups("/", { token: latecomer.token })).body, group.id as string);
  assertEquals(row.my_state, "guess");
  assertEquals(row.needs_action, false);
});

Deno.test("scored: `answers`, never needing action", async () => {
  const { owner, group } = await revealedCircle("Switcher Scored", ["Ben", "Cal"]);
  await tickRoundsAt(6); // past `scores_at`

  const row = circleOf((await groups("/", { token: owner.token })).body, group.id as string);
  assertEquals(row.my_state, "answers");
  assertEquals(row.needs_action, false);
});

Deno.test("fewer than three submitters: `voided`, never needing action", async () => {
  const { user: owner, group } = await newGroupOwner("Ana", {
    name: "Switcher Voided",
    timezone: zoneWhereLocalHourIs(17),
    reveal_hour: 18,
  });
  await call("rounds", "/current/submission", {
    method: "PUT",
    token: owner.token,
    body: { apple_music_id: TRACKS[3] },
  });
  await tickRoundsAt(2);

  const row = circleOf((await groups("/", { token: owner.token })).body, group.id as string);
  assertEquals(row.my_state, "voided");
  assertEquals(row.needs_action, false);
});

Deno.test(
  "a circle created after its own reveal hour has already passed today still shows drop, not a gap",
  async () => {
    // `ensure_rounds()` never creates a round whose reveal has already passed
    // (`0004_round_lifecycle.sql`) — a circle founded at, say, 22:00 local with a 21:00 reveal
    // hour has a round for tomorrow and none dated today. That is not "nothing to report yet":
    // tomorrow's round is real, already `open`, and is the circle's only round, so it is the
    // one the switcher must show. `circleCallerState`'s lookup takes the earliest round dated
    // today or later for exactly this reason — pinning to `local_date = today` would miss this
    // row and silently drop the circle out of `GET /groups` for the rest of the day.
    const user = await newNamedUser("Ana");
    const kept = (
      await groups("/", { method: "POST", token: user.token, body: { name: "Kept", timezone: "UTC" } })
    ).body.data;
    const tooLate = (
      await groups("/", {
        method: "POST",
        token: user.token,
        body: { name: "Too Late Tonight", timezone: zoneWhereLocalHourIs(22), reveal_hour: 21 },
      })
    ).body.data;

    const res = await groups("/", { token: user.token });
    assertEquals(res.status, 200, "a circle with only a future round must not fail the whole request");
    const ids = (res.body.data.circles as { id: string }[]).map((c) => c.id);
    assert(ids.includes(kept.id), "the unaffected circle is still listed");
    assert(ids.includes(tooLate.id), "a circle whose only round is tomorrow's must still be listed");

    const row = circleOf(res.body, tooLate.id as string);
    assertEquals(row.my_state, "drop");
    assertEquals(row.needs_action, true);
  },
);

Deno.test("a circle's row carries exactly {id, name, my_state, needs_action} — no more, no fewer", async () => {
  const { owner, group, members } = await revealedCircle(
    "Switcher Shape",
    ["Ben", "Cal", "Dee", "Eli"],
  );

  const row = circleOf((await groups("/", { token: owner.token })).body, group.id as string);
  assertEquals(keysOf(row), [...circleSummaryFields()].sort());

  // Nothing that names another member — the whole point of `E18-02`'s leak discipline.
  const serialised = JSON.stringify(row);
  for (const member of members) {
    assert(!serialised.includes(member.id), `row leaks ${member.id}`);
  }
});
