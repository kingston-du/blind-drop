// results.test.ts — the answers. tasks/E05-04, docs/04 §4, docs/02 §4.4, docs/15 AC-8.
//
// Almost every other function test builds its own group through the API. This one does not,
// and the reason is worth stating: `seed.sql` already holds the docs/02 §4.4 matrix — nine
// people, eight submitters, forty-six guesses, and a readability table somebody worked out by
// hand — and `tests/db/scoring.sql` asserts the views reproduce it. What has never been checked
// is whether those numbers survive the trip through `GET /rounds/{id}/results` and out onto the
// wire in the shape docs/04 §4 promises.
//
// So this file speaks HTTP as Ana, as Eli and as Ivy, and asserts the payload against the
// numbers in the doc rather than against numbers it computed itself. A test that recomputed the
// arithmetic would agree with a handler that had the same bug.
//
// The §4.4 round is dated 2026-08-08 and is nobody's current round, which makes it the
// checklist's "works for any past round" case for free — this is exactly the call The Record
// makes when someone taps back into a night from last week.

import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  call,
  keysOf,
  mintToken,
  newGroupOwner,
  newMember,
  tickRoundsAt,
  zoneWhereLocalHourIs,
} from "./_harness.ts";

// ─── the fixture, by name ────────────────────────────────────────────────────
// seed.sql ids, written out so the assertions below read like docs/02 §4.4 rather than like a
// list of uuids.

const PERSON = {
  Ana: "a0000000-0000-4000-8000-000000000001",
  Ben: "a0000000-0000-4000-8000-000000000002",
  Cal: "a0000000-0000-4000-8000-000000000003",
  Dee: "a0000000-0000-4000-8000-000000000004",
  Eli: "a0000000-0000-4000-8000-000000000005",
  Fay: "a0000000-0000-4000-8000-000000000006",
  Gus: "a0000000-0000-4000-8000-000000000007",
  Hal: "a0000000-0000-4000-8000-000000000008",
  Ivy: "a0000000-0000-4000-8000-000000000009",
} as const;

// 2026-08-08, the §4.4 matrix. Already `scored` in the seed, and `scored` is terminal, so no
// amount of scheduler-running by the rest of the suite can move it out from under this file.
const SCORED_ROUND = "c0000000-0000-4000-8000-000000000001";

const RESULTS_KEYS = ["cards", "local_date", "me", "people", "round_id", "submitter_count"].sort();
const CARD_KEYS = [
  "card_no",
  "correct_guess_count",
  "eligible_guesser_count",
  "my_guess",
  "owner",
  "track",
].sort();
const ME_KEYS = [
  "ear",
  "ear_correct",
  "ear_possible",
  "readability",
  "readability_correct",
  "readability_possible",
].sort();

/**
 * §4.4's card order — `1=Dee 2=Ben 3=Hal 4=Ana 5=Gus 6=Cal 7=Eli 8=Fay` — with the
 * correct-guess count on each card from the readability table, as repaired by `seed.sql`
 * (Gus 0 → 1, Hal 5 → 4; the note in the seed explains why the doc's table is unsatisfiable
 * as printed).
 */
const CARDS: { owner: keyof typeof PERSON; correct: number }[] = [
  { owner: "Dee", correct: 4 },
  { owner: "Ben", correct: 5 },
  { owner: "Hal", correct: 4 },
  { owner: "Ana", correct: 6 },
  { owner: "Gus", correct: 1 },
  { owner: "Cal", correct: 3 },
  { owner: "Eli", correct: 1 },
  { owner: "Fay", correct: 2 },
];

// deno-lint-ignore no-explicit-any
type Json = any;

/** A signed-in fixture person. They exist in `auth.users`, so a minted token is a real one. */
function as(person: keyof typeof PERSON): Promise<string> {
  return mintToken(PERSON[person]);
}

async function resultsAs(person: keyof typeof PERSON, roundId = SCORED_ROUND): Promise<Json> {
  const res = await call("rounds", `/${roundId}/results`, { token: await as(person) });
  assertEquals(
    res.status,
    200,
    `${person} could not read the results: ${JSON.stringify(res.body)}`,
  );
  return res.body.data;
}

/** Two rates are equal when they agree to within a rounding error no display could show.
 *  `readability` is a Postgres `numeric` and arrives with more digits than a double holds. */
function assertRate(actual: unknown, expected: number, what: string): void {
  assert(typeof actual === "number", `${what} should be a number, got ${JSON.stringify(actual)}`);
  assert(
    Math.abs((actual as number) - expected) < 1e-9,
    `${what}: expected ${expected}, got ${actual}`,
  );
}

// ─── shape ───────────────────────────────────────────────────────────────────

Deno.test("the results payload has exactly the documented key set", async () => {
  const data = await resultsAs("Ana");

  assertEquals(keysOf(data), RESULTS_KEYS);
  assertEquals(keysOf(data.me), ME_KEYS);
  assertEquals(keysOf(data.cards[0]), CARD_KEYS);
  assertEquals(keysOf(data.people[0]), ["display_name", "ear", "readability", "user_id"]);
  assertEquals(keysOf(data.cards[0].owner), ["display_name", "user_id"]);
  assertEquals(data.round_id, SCORED_ROUND);
  assertEquals(data.local_date, "2026-08-08");
});

Deno.test("a scored round from three days ago is readable — the Record links into it", async () => {
  // The route is keyed by id, not by "today". This is the call `RecordScreen` makes on "See
  // that night's results", and the §4.4 round has long since stopped being the fixture's
  // scheduled night. Addressing it directly must remain sufficient.
  const data = await resultsAs("Ana");
  assertEquals(data.submitter_count, 8);
});

// ─── the §4.4 matrix, over HTTP ──────────────────────────────────────────────

Deno.test("every card carries its owner, its correct count, and S − 1", async () => {
  const data = await resultsAs("Ana");

  assertEquals(data.cards.length, 8);
  assertEquals(data.cards.map((c: Json) => c.card_no), [1, 2, 3, 4, 5, 6, 7, 8]);

  for (const [index, expected] of CARDS.entries()) {
    const card = data.cards[index];
    assertEquals(card.owner.user_id, PERSON[expected.owner], `card ${index + 1} owner`);
    assertEquals(card.owner.display_name, expected.owner, `card ${index + 1} name`);
    assertEquals(card.correct_guess_count, expected.correct, `card ${index + 1} correct count`);
    // S − 1 on every card, including the ones nobody guessed. docs/02 §4.1: the denominator is
    // every other submitter whether or not they opened the sheet.
    assertEquals(card.eligible_guesser_count, 7, `card ${index + 1} denominator`);
  }

  // §4.4's totals balance at 26 — the same 26 that the ear numerators sum to, because every
  // correct guess counts once for the guesser and once for the card's owner.
  assertEquals(data.cards.reduce((sum: number, c: Json) => sum + c.correct_guess_count, 0), 26);
});

Deno.test("cards carry the whole Track DTO, so the archive renders without a second call", async () => {
  const data = await resultsAs("Ana");
  const track = data.cards[0].track;

  assertEquals(track.title, "Redbone");
  assertEquals(track.artist, "Childish Gambino");
  // The `{w}x{h}` template, never a resolved size — docs/06 §2.1.
  assert(String(track.artwork_url).includes("{w}x{h}"), "artwork stays a template");
  assert(String(track.spotify_url).startsWith("https://open.spotify.com/track/"));
});

Deno.test("my_guess is the caller's own, with the name and whether it landed", async () => {
  const data = await resultsAs("Ana");

  // Ana guessed seven of the eight cards and got five right (§4.4). Card 4 is her own.
  const guessed = data.cards.filter((c: Json) => c.my_guess !== null);
  assertEquals(guessed.length, 7);
  assertEquals(data.cards[3].my_guess, null, "you never guess your own card");
  assertEquals(guessed.filter((c: Json) => c.my_guess.is_correct).length, 5, "Ana got five right");

  // Card 5 is Gus's; Ana named Dee. Wrong, and the payload says whose name she put there so the
  // screen can strike it through (docs/08 §7.1) without a lookup.
  assertEquals(data.cards[4].my_guess.guessed_user_id, PERSON.Dee);
  assertEquals(data.cards[4].my_guess.display_name, "Dee");
  assertEquals(data.cards[4].my_guess.is_correct, false);
});

Deno.test("me carries both rates as decimals with the fraction behind them", async () => {
  const data = await resultsAs("Ana");

  assertRate(data.me.readability, 6 / 7, "Ana readability");
  assertEquals(data.me.readability_correct, 6);
  assertEquals(data.me.readability_possible, 7);
  assertRate(data.me.ear, 5 / 7, "Ana ear");
  assertEquals(data.me.ear_correct, 5);
  assertEquals(data.me.ear_possible, 7);
});

Deno.test("people is every submitter and nobody else", async () => {
  const data = await resultsAs("Ana");

  assertEquals(data.people.length, 8);
  assertEquals(
    data.people.map((p: Json) => p.display_name),
    ["Ana", "Ben", "Cal", "Dee", "Eli", "Fay", "Gus", "Hal"],
    "in name order, matching the roster elsewhere in the API",
  );
  // Ivy did not submit. She has no card and could not guess, so she has neither number — and a
  // row of two dashes beside her name would read as a scoreline rather than an absence.
  assert(
    !data.people.some((p: Json) => p.user_id === PERSON.Ivy),
    "a non-submitter must not appear in people",
  );

  const gus = data.people.find((p: Json) => p.user_id === PERSON.Gus);
  assertRate(gus.readability, 1 / 7, "Gus readability");
  assertRate(gus.ear, 1 / 7, "Gus ear");
});

// ─── null means not applicable, never zero ───────────────────────────────────
// docs/04 §4 and docs/08 §7.2. This is the clause that turns "you sat out" into "you scored
// nothing" when it is got wrong, and it is the one judgement the product refuses to make.

Deno.test("Eli guessed nothing, so Eli's ear is null — and so is its fraction", async () => {
  const data = await resultsAs("Eli");

  assertEquals(data.me.ear, null, "null, never 0 — docs/02 §4.1 drops the round from the average");
  assertEquals(
    data.me.ear_correct,
    null,
    "and no fraction, because there is no honest one to show",
  );
  assertEquals(data.me.ear_possible, null);

  // Eli still has a readability: how much of the room read you does not depend on whether you
  // looked (§4.4, "Eli, who guessed nothing, still has a readability").
  assertRate(data.me.readability, 1 / 7, "Eli readability");
  assertEquals(data.me.readability_correct, 1);
  assertEquals(data.me.readability_possible, 7);

  // Eli appears in `people` with a null ear, for the same reason.
  const eli = data.people.find((p: Json) => p.user_id === PERSON.Eli);
  assertEquals(eli.ear, null);
  assertRate(eli.readability, 1 / 7, "Eli readability in people");
});

Deno.test("Ivy did not submit, so every one of Ivy's numbers is null", async () => {
  const data = await resultsAs("Ivy");

  assertEquals(data.me, {
    readability: null,
    readability_correct: null,
    readability_possible: null,
    ear: null,
    ear_correct: null,
    ear_possible: null,
  });
  // She still sees the round. Sitting one out does not lock you out of the answers — it is the
  // group's evening, not a paywall (docs/08 §7).
  assertEquals(data.cards.length, 8);
  assert(data.cards.every((c: Json) => c.my_guess === null), "she could not guess, so no guesses");
});

// ─── the guards ──────────────────────────────────────────────────────────────

Deno.test("an unscored round returns WRONG_PHASE, and the error body carries no card data", async () => {
  // Built here rather than borrowed from the seed, because the seed's `revealed` round is only
  // revealed until some other test in the suite runs the scheduler — the fixture is shared and
  // `tick_rounds()` is global. A round this test owns is a round whose phase it can rely on.
  //
  // Refusing is easy; refusing *without* leaking is the part worth asserting. An `open` round
  // is refused because the blind window is still up, and a `revealed` one because its sheets
  // are still being edited — the answers do not exist yet, and half-scored numbers shown once
  // cannot be un-shown. In both cases a helpful error body is how this endpoint would become
  // the leak that `GET /rounds/current` is careful not to be.
  const { user: ana, group } = await newGroupOwner("Ana", {
    name: "Too Early",
    timezone: zoneWhereLocalHourIs(17),
    reveal_hour: 18,
  });
  const code = group.invite_code as string;
  const submitters = [ana, await newMember(code, "Ben"), await newMember(code, "Cal")];
  // Three drops, so the round genuinely reveals rather than voiding — a voided round would
  // refuse for an entirely different reason and prove nothing about the phase guard.
  for (const [i, member] of submitters.entries()) {
    await call("rounds", "/current/submission", {
      method: "PUT",
      token: member.token,
      body: { apple_music_id: ["1440818664", "1440765580", "1452874255"][i] },
    });
  }

  const current = await call("rounds", "/current", { token: ana.token });
  const roundId = current.body.data.round_id as string;

  const refusals: Record<string, Json> = {};
  for (const [phase, tick] of [["open", 0], ["revealed", 2]] as const) {
    if (tick) await tickRoundsAt(tick);
    const res = await call("rounds", `/${roundId}/results`, { token: ana.token });

    assertEquals(res.status, 409, `${phase} should be refused`);
    assertEquals(res.body.error.code, "WRONG_PHASE");
    assertEquals(res.body.error.state, phase);
    assertEquals(
      keysOf(res.body.error),
      ["code", "message", "state"],
      "the state, and nothing else",
    );
    assertEquals(keysOf(res.body), ["error", "server_now"], "no data key at all");
    refusals[phase] = res.body;
  }

  // The `revealed` refusal is where a leak would actually be worth something: three songs are
  // sitting behind that round id and the caller has not earned the names attached to them.
  const serialised = JSON.stringify(refusals.revealed);
  for (const forbidden of ["track", "card", "Ben", "Cal", "count", "submitter"]) {
    assert(!serialised.includes(forbidden), `the refusal must not mention ${forbidden}`);
  }
});

Deno.test("a voided round has no results and says so in its own words", async () => {
  // Fewer than three drops, so there is nothing to score and nothing that was ever seen
  // (docs/02 §2). `ROUND_VOIDED` rather than `WRONG_PHASE` because the client has different
  // copy for it — and, as everywhere else, no count of how many did submit.
  const { user: ana } = await newGroupOwner("Ana", {
    name: "Not Enough",
    timezone: zoneWhereLocalHourIs(17),
    reveal_hour: 18,
  });
  await call("rounds", "/current/submission", {
    method: "PUT",
    token: ana.token,
    body: { apple_music_id: "1440818664" },
  });

  const current = await call("rounds", "/current", { token: ana.token });
  await tickRoundsAt(2);

  const res = await call("rounds", `/${current.body.data.round_id}/results`, { token: ana.token });
  assertEquals(res.status, 409);
  assertEquals(res.body.error.code, "ROUND_VOIDED");
  assertEquals(keysOf(res.body.error), ["code", "message"], "not even a state — just the copy");
});

Deno.test("a round belonging to another group is indistinguishable from one that does not exist", async () => {
  // The only route in the API that takes an id, so the only one with an IDOR surface at all
  // (docs/14 §4). The group id is part of the query key rather than a check afterwards, which
  // is why both of these are the same 404 with the same body.
  const { user: outsider } = await newGroupOwner("Outsider", {
    name: "Elsewhere",
    timezone: zoneWhereLocalHourIs(12),
  });

  const theirs = await call("rounds", `/${SCORED_ROUND}/results`, { token: outsider.token });
  const nothing = await call("rounds", "/c0000000-0000-4000-8000-0000000000ff/results", {
    token: outsider.token,
  });

  assertEquals(theirs.status, 404);
  assertEquals(nothing.status, 404);
  assertEquals(theirs.body.error, nothing.body.error, "byte-identical, so neither is an oracle");
});

Deno.test("a malformed round id is a 404, not a 500", async () => {
  // A uuid Postgres cannot parse is a `22P02`, which would surface as INTERNAL — and a route
  // answering 500 for garbage and 404 for a real id elsewhere has just told the caller which
  // is which.
  const res = await call("rounds", "/not-a-uuid/results", { token: await as("Ana") });

  assertEquals(res.status, 404);
  assertEquals(res.body.error.code, "NOT_FOUND");
});

Deno.test("results require a token", async () => {
  const res = await call("rounds", `/${SCORED_ROUND}/results`, { token: null });

  assertEquals(res.status, 401);
  assertEquals(res.body.error.code, "UNAUTHENTICATED");
});
