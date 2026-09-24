// reactions.test.ts — the seal, and the guards around it. tasks/E46-01, docs/19, docs/15 AC-12.
//
// `docs/19` §3 is one sentence — *a reaction behaves exactly like a guess* — and this file is
// that sentence in assertions. Two halves:
//
//   · **The seal.** While a round is `revealed`, a member's marks are theirs alone. No route
//     returns another member's mark and no route returns a count of anybody's. The `revealed`
//     payload's own key set is asserted in `reveal.test.ts`; what is here is the stronger
//     claim, which is that nothing in the shape carries somebody else's activity even when
//     three other people have been marking cards for an hour.
//   · **The guards.** Phase, joined-late, card range, the closed enum, idempotency — and the
//     two restrictions that deliberately are *not* there: a non-submitter may mark, and so may
//     the owner of the card.

import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  call,
  keysOf,
  mintToken,
  newGroupOwner,
  newMember,
  setJoinedAt,
  type TestUser,
  tickRoundsAt,
  zoneWhereLocalHourIs,
} from "./_harness.ts";

// `seed.sql`'s docs/02 §4.4 round — 2026-08-08, `scored`, and nobody's current round. The same
// fixture `results.test.ts` reads, used here for the one property that needs a genuinely past
// night rather than a freshly scored one.
const SEED_ANA = "a0000000-0000-4000-8000-000000000001";
const SEED_PAST_ROUND = "c0000000-0000-4000-8000-000000000001";

const TRACKS = ["1440818664", "1440765580", "1452874255", "1440830827", "1442571948"];

interface Revealed {
  owner: TestUser;
  submitters: TestUser[];
  /** A member of the circle who did not drop a song tonight. */
  bystander: TestUser;
  data: Record<string, unknown>;
}

/**
 * A revealed round with three submitters and one member who sat it out.
 *
 * 16:00 local with a reveal at 18:00, then the scheduler three hours on — a real transition,
 * because a round forced into `revealed` by hand would have no `card_order` and this file
 * addresses everything by card number.
 *
 * **16:00 rather than the 17:00 `reveal.test.ts` uses, and a three-hour tick rather than two.**
 * `zoneWhereLocalHourIs` shifts by whole hours, so the group's local minute is the real UTC
 * minute. Created at 17:59 with a reveal at 18:00, the round either has sixty seconds left or —
 * once `ensure_rounds` decides the reveal is already behind — is *tomorrow's*, two hours from
 * which is nowhere near it. Either way the tick landed on an `open` round and every test in this
 * file failed at once, for two minutes in every hour. An hour of margin on each side removes the
 * boundary: the tick is past `reveals_at` and short of `scores_at` at every minute.
 */
async function revealedRound(name: string): Promise<Revealed> {
  const { user: owner, group } = await newGroupOwner("Ana", {
    name,
    timezone: zoneWhereLocalHourIs(16),
    reveal_hour: 18,
    cue_cadence: 0,
  });
  const code = group.invite_code as string;
  const submitters = [owner, await newMember(code, "Ben"), await newMember(code, "Cal")];
  const bystander = await newMember(code, "Dee");

  for (const [i, member] of submitters.entries()) {
    const res = await call("rounds", "/current/submission", {
      method: "PUT",
      token: member.token,
      body: { apple_music_id: TRACKS[i] },
    });
    assertEquals(res.status, 200, `${i} could not submit`);
  }
  await tickRoundsAt(3);

  const res = await call("rounds", "/current", { token: owner.token });
  assertEquals(res.body.data.state, "revealed", `${name} did not reveal`);
  return { owner, submitters, bystander, data: res.body.data as Record<string, unknown> };
}

function react(token: string, cardNo: number, kind: string | null) {
  return call("rounds", "/current/reactions", {
    method: "PUT",
    token,
    body: { card_no: cardNo, kind },
  });
}

function myCardNo(data: Record<string, unknown>): number {
  return data.my_card_no as number;
}

/** A card the caller does not own. */
function otherCardNo(data: Record<string, unknown>): number {
  const cards = data.cards as { card_no: number }[];
  return cards.find((c) => c.card_no !== myCardNo(data))!.card_no;
}

// ─── the seal ────────────────────────────────────────────────────────────────

Deno.test("a mark comes back to its owner and to nobody else", async () => {
  const { submitters, data } = await revealedRound("React Seal");
  const [ana, ben, cal] = submitters;
  const card = otherCardNo(data);

  // Everybody marks the same card. If any aggregate existed anywhere, this is the round it
  // would show up in.
  assertEquals((await react(ana.token, card, "loved")).status, 200);
  assertEquals((await react(ben.token, card, "loved")).status, 200);
  assertEquals((await react(cal.token, card, "not_for_me")).status, 200);

  const view = await call("rounds", "/current", { token: ana.token });
  const mine = (view.body.data as Record<string, unknown>).my_reactions as unknown[];
  assertEquals(mine, [{ card_no: card, kind: "loved" }], "Ana sees her own mark, once");

  // The strong form: no number anywhere in the payload is a count of reactions, and no key
  // resembling one exists. Three people marked that card; the word "loved" may appear exactly
  // once, as the caller's own kind.
  const serialised = JSON.stringify(view.body.data);
  assertEquals(serialised.match(/loved/g)?.length, 1, "somebody else's mark is in the payload");
  assertEquals(serialised.match(/not_for_me/g) ?? null, null, "Cal's mark is in the payload");
  // `"reactions":` as a key of its own — the counts object that must not exist until `scored`.
  // Anchored on the opening quote so it does not match `my_reactions`, which is the caller's
  // own and is meant to be there.
  for (const banned of ['"reactions":', "reaction_count", "loved_count", "reactor"]) {
    assert(!serialised.includes(banned), `the revealed payload carries ${banned}`);
  }
});

Deno.test("the write route answers with the caller's own marks and nothing else", async () => {
  const { submitters, data } = await revealedRound("React Write Shape");
  const [ana, ben] = submitters;
  const card = otherCardNo(data);

  await react(ben.token, card, "loved");
  const res = await react(ana.token, card, "interesting");

  assertEquals(res.status, 200);
  assertEquals(keysOf(res.body.data), ["my_reactions"], "the write answers with one key");
  assertEquals(res.body.data.my_reactions, [{ card_no: card, kind: "interesting" }]);
  // Ben marked the same card a moment ago. Nothing about that is in this response — not a
  // count, not a total, not a hint (docs/19 §3, consequence 1).
  assert(!JSON.stringify(res.body).includes("loved"));
});

Deno.test("the group-addressed route is the same handler, and proves membership", async () => {
  // ADR-011: every `current`-shaped route also exists named by group id, one shared handler
  // apiece. Marking through either door must do the same thing — and a member of some other
  // circle must not get through the named one.
  const { owner, data } = await revealedRound("React By Group Id");
  const stranger = await revealedRound("React Outsider");
  const groupId = (await call("groups", "/current", { token: owner.token })).body.data.id as string;
  const card = otherCardNo(data);

  const res = await call("rounds", `/${groupId}/current/reactions`, {
    method: "PUT",
    token: owner.token,
    body: { card_no: card, kind: "loved" },
  });
  assertEquals(res.status, 200);
  assertEquals(res.body.data.my_reactions, [{ card_no: card, kind: "loved" }]);

  const outsider = await call("rounds", `/${groupId}/current/reactions`, {
    method: "PUT",
    token: stranger.owner.token,
    body: { card_no: card, kind: "loved" },
  });
  assert(outsider.status === 403 || outsider.status === 404, `outsider got ${outsider.status}`);
});

// ─── the guards ──────────────────────────────────────────────────────────────

Deno.test("marking is refused before the reveal, with the state and nothing else", async () => {
  const { user } = await newGroupOwner("Ana", {
    name: "React Too Early",
    timezone: zoneWhereLocalHourIs(12),
    reveal_hour: 20,
    cue_cadence: 0,
  });
  const res = await react(user.token, 1, "loved");

  assertEquals(res.status, 409);
  assertEquals(res.body.error.code, "WRONG_PHASE");
  assertEquals(res.body.error.state, "open");
  // The refusal is the one place an `open`-phase response could carry a count, so it carries
  // exactly three keys, the same as every other WRONG_PHASE in this API.
  assertEquals(keysOf(res.body.error), ["code", "message", "state"]);
});

Deno.test("a member who joined after the reveal cannot mark", async () => {
  const { submitters, bystander, data } = await revealedRound("React Joined Late");
  const card = otherCardNo(data);

  // Same clause `cannotGuessReason` checks first: the cards were dealt before they arrived.
  //
  // **Three hours, and it is tied to `revealedRound`'s clock.** The room sits at 16:00 local
  // with an 18:00 reveal, so `reveals_at` is between one and two hours out depending on the
  // real minute; a join stamped an hour from now is only reliably *after* it when the room sits
  // in the 17:00 hour, which is what this used to assume. Anything past the room's two-hour
  // ceiling is after the reveal at every minute.
  await setJoinedAt(bystander.id, new Date(Date.now() + 3 * 60 * 60 * 1000));
  const res = await react(bystander.token, card, "loved");
  assertEquals(res.status, 403);
  assertEquals(res.body.error.code, "JOINED_LATE");

  // And the submitter beside them is unaffected — the guard is about the one caller.
  assertEquals((await react(submitters[1].token, card, "loved")).status, 200);
});

Deno.test("a member who did not drop a song may still mark — deliberately", async () => {
  // docs/19 §4. `docs/02` §3.3 restricts *guessing* because guessing is scored; a mark is
  // scored by nothing, and the reveal screen otherwise tells a non-submitter they have nothing
  // to do. This is the assertion that keeps somebody from "fixing" that asymmetry later.
  const { bystander, data } = await revealedRound("React Bystander");
  const card = otherCardNo(data);

  const res = await react(bystander.token, card, "interesting");
  assertEquals(res.status, 200);
  assertEquals(res.body.data.my_reactions, [{ card_no: card, kind: "interesting" }]);

  // The same member is still refused a guess, on the same round, in the same breath.
  const guess = await call("rounds", "/current/guesses", {
    method: "PUT",
    token: bystander.token,
    body: { assignments: [{ card_no: card, guessed_user_id: bystander.id }] },
  });
  assertEquals(guess.status, 403);
  assertEquals(guess.body.error.code, "NOT_A_SUBMITTER");
});

Deno.test("a member may mark their own card", async () => {
  // docs/19 §4, and there is no `reactions_not_self` constraint behind it either. The reveal
  // gives this no control — the quick pass skips your own card — so in the app this lands from
  // the results screen; the route permits it in both phases all the same.
  const { owner, data } = await revealedRound("React Own Card");
  const res = await react(owner.token, myCardNo(data), "loved");

  assertEquals(res.status, 200);
  assertEquals(res.body.data.my_reactions, [{ card_no: myCardNo(data), kind: "loved" }]);
});

Deno.test("a card number outside the round is refused", async () => {
  const { owner, data } = await revealedRound("React Card Range");
  const cards = (data.cards as unknown[]).length;

  for (const cardNo of [0, -1, cards + 1, 999]) {
    const res = await react(owner.token, cardNo, "loved");
    assertEquals(res.status, 400, `card_no ${cardNo} was accepted`);
    assertEquals(res.body.error.code, "INVALID_INPUT");
  }
});

Deno.test("the three kinds are the whole set", async () => {
  const { owner, data } = await revealedRound("React Kind Set");
  const card = otherCardNo(data);

  for (const kind of ["loved", "interesting", "not_for_me"]) {
    assertEquals((await react(owner.token, card, kind)).status, 200, `${kind} was refused`);
  }
  for (const kind of ["hated", "LOVED", "fire", "", "1"]) {
    const res = await react(owner.token, card, kind);
    assertEquals(res.status, 400, `"${kind}" was accepted as a reaction kind`);
    assertEquals(res.body.error.code, "INVALID_INPUT");
  }
});

Deno.test("a mark is replaced, not stacked, and null clears it", async () => {
  const { owner, data } = await revealedRound("React Replace");
  const card = otherCardNo(data);

  await react(owner.token, card, "loved");
  const changed = await react(owner.token, card, "not_for_me");
  assertEquals(changed.body.data.my_reactions, [{ card_no: card, kind: "not_for_me" }]);

  // Idempotent: the same body twice is one row and the same response.
  const again = await react(owner.token, card, "not_for_me");
  assertEquals(again.body.data.my_reactions, [{ card_no: card, kind: "not_for_me" }]);

  const cleared = await react(owner.token, card, null);
  assertEquals(cleared.status, 200);
  assertEquals(cleared.body.data.my_reactions, [], "null clears the mark");

  // Clearing a card that was never marked is not an error — the client fires this on a second
  // tap of an unset mark whenever a write raced a refresh.
  assertEquals((await react(owner.token, card, null)).status, 200);
});

Deno.test("marks survive to the answers, counted and anonymous", async () => {
  const { submitters, bystander, data } = await revealedRound("React To Answers");
  const [ana, ben, cal] = submitters;
  const card = otherCardNo(data);
  const anaCard = myCardNo(data);

  await react(ana.token, card, "loved");
  await react(ben.token, card, "loved");
  await react(cal.token, card, "interesting");
  await react(bystander.token, card, "not_for_me");
  await react(ana.token, anaCard, "loved"); // her own

  await tickRoundsAt(5); // past scores_at
  const roundId = data.round_id as string;
  const res = await call("rounds", `/${roundId}/results`, { token: ana.token });
  assertEquals(res.status, 200);

  const cards = res.body.data.cards as Record<string, unknown>[];
  const marked = cards.find((c) => c.card_no === card)!;
  assertEquals(marked.reactions, { loved: 2, interesting: 1, not_for_me: 1 });
  assertEquals(marked.my_reaction, "loved");

  // All three keys on every card, zeros included — a card nobody marked is three zeros, not a
  // missing object (docs/19 §7).
  for (const c of cards) {
    assertEquals(keysOf(c.reactions).sort(), ["interesting", "loved", "not_for_me"]);
  }
  const untouched = cards.find((c) => c.card_no !== card && c.card_no !== anaCard)!;
  assertEquals(untouched.reactions, { loved: 0, interesting: 0, not_for_me: 0 });
  assertEquals(untouched.my_reaction, null);

  // **Nobody is named.** Not on any card, and not on the caller's own — which is the one card
  // that *does* name guessers. A reactor id appearing anywhere here is the failure this
  // assertion exists for (docs/19 §7).
  const own = cards.find((c) => c.card_no === anaCard)!;
  assertEquals(own.my_reaction, "loved");
  assertEquals(own.reactions, { loved: 1, interesting: 0, not_for_me: 0 });
  const serialised = JSON.stringify(cards.map((c) => c.reactions));
  for (const id of [ana.id, ben.id, cal.id, bystander.id]) {
    assert(!serialised.includes(id), "a reactor is named in the counts");
  }
  assert(!JSON.stringify(res.body.data).includes("reactor"), "a reactor key is on the payload");
});

Deno.test("a scored round is still markable while it is tonight's round", async () => {
  const { owner, data } = await revealedRound("React After Scoring");
  const card = otherCardNo(data);

  await tickRoundsAt(4);
  const view = await call("rounds", "/current", { token: owner.token });
  assertEquals((view.body.data as Record<string, unknown>).state, "scored");

  const res = await react(owner.token, card, "loved");
  assertEquals(res.status, 200, "the answers are where your own card gets marked (docs/19 §4)");
  assertEquals(res.body.data.my_reactions, [{ card_no: card, kind: "loved" }]);
});

Deno.test("a past round cannot be marked, and still serves the counts it ended with", async () => {
  // `docs/19` §3: reactions close with the round. The route's first line of defence is that it
  // takes no round id at all — `PUT /rounds/current/reactions` addresses whatever
  // `currentRound()` resolves, which is keyed by the circle's *local date* and can never be a
  // night that has passed. There is deliberately no `PUT /rounds/{round_id}/reactions` to test,
  // and this asserts the two halves of that: the write lands on tonight, and last week still
  // reads.
  const token = await mintToken(SEED_ANA);

  // Tonight, in the seed circle, has nobody's drop in it — so the write is refused *against
  // tonight's round*, which is the proof that it resolved tonight rather than reaching back for
  // 2026-08-08. A route that could address the past round would have answered 200 or a
  // different phase. Tonight is `open` (WRONG_PHASE) or, once another test's `tickRoundsAt`
  // has carried the whole database past 20:00 in New York, `voided` (ROUND_VOIDED): every
  // group ticks, the seed circle included, so which one depends on the hour the suite runs.
  // Both are tonight; only the scored night would be wrong.
  const write = await call("rounds", "/current/reactions", {
    method: "PUT",
    token,
    body: { card_no: 1, kind: "loved" },
  });
  assertEquals(write.status, 409);
  assert(
    ["WRONG_PHASE", "ROUND_VOIDED"].includes(write.body.error.code),
    `expected tonight's refusal, got ${JSON.stringify(write.body.error)}`,
  );
  assert(
    write.body.error.state !== "scored",
    `the write resolved a scored round: ${JSON.stringify(write.body.error)}`,
  );

  // And the past night still reads. Its cards carry the three keys like any other; nobody
  // marked that round, so they are zeros — which is exactly what every night from before this
  // shipped looks like, and the client draws no row for it (docs/19 §8.3).
  const results = await call("rounds", `/${SEED_PAST_ROUND}/results`, { token });
  assertEquals(results.status, 200);
  for (const card of results.body.data.cards as Record<string, unknown>[]) {
    assertEquals(keysOf(card.reactions).sort(), ["interesting", "loved", "not_for_me"]);
    assertEquals(card.reactions, { loved: 0, interesting: 0, not_for_me: 0 });
    assertEquals(card.my_reaction, null);
  }
});
