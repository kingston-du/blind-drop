import { assertAlmostEquals, assertEquals } from "jsr:@std/assert@1";
import {
  confusionMinimumRounds,
  confusionPairs,
  correctReadRounds,
  type ReadGuessRow,
  readTally,
  roundsGuessedIn,
  wilsonLowerBound,
  wilsonUpperBound,
} from "../../functions/_shared/insights.ts";

const members = new Map([
  ["ana", { user_id: "ana", display_name: "Ana" }],
  ["ben", { user_id: "ben", display_name: "Ben" }],
  ["cal", { user_id: "cal", display_name: "Cal" }],
]);

Deno.test("confusion needs a member-square history gate", () => {
  assertEquals(confusionMinimumRounds(3), 9);
  assertEquals(confusionMinimumRounds(12), 144);
});

Deno.test("confusion counts wrong owner-to-name pairs, excludes correct duplicates, and sorts stably", () => {
  const pairs = confusionPairs([
    { guesser_id: "ben", card_owner_id: "ana", guessed_user_id: "ben", is_correct: false },
    { guesser_id: "cal", card_owner_id: "ana", guessed_user_id: "ben", is_correct: false },
    { guesser_id: "ben", card_owner_id: "ana", guessed_user_id: "cal", is_correct: false },
    // Ben dropped the same track as Ana: naming Ben is correct and not a mix-up.
    { guesser_id: "cal", card_owner_id: "ana", guessed_user_id: "ben", is_correct: true },
    { guesser_id: "ben", card_owner_id: "unknown", guessed_user_id: "ben", is_correct: false },
    { guesser_id: "former", card_owner_id: "ana", guessed_user_id: "ben", is_correct: false },
  ], members, 3);

  assertEquals(pairs, [
    { actual_member: members.get("ana"), mistaken_for_member: members.get("ben"), count: 2 },
    { actual_member: members.get("ana"), mistaken_for_member: members.get("cal"), count: 1 },
  ]);
});

// ─── `E28-07`: the volume-aware ranking ────────────────────────────────────
//
// The four cases the owner asked for by name: a well-supported 8-of-12 must always outrank a
// thin 3-of-4, a 7-of-12 — genuinely better supported, not just bigger — must still outrank it,
// and a 6-of-12 must not.
Deno.test("the Wilson lower bound ranks volume-supported rates above thin ones, in the owner's own order", () => {
  const eightOfTwelve = wilsonLowerBound(8, 12);
  const sevenOfTwelve = wilsonLowerBound(7, 12);
  const sixOfTwelve = wilsonLowerBound(6, 12);
  const threeOfFour = wilsonLowerBound(3, 4);

  assertAlmostEquals(eightOfTwelve, 0.3906, 0.001);
  assertAlmostEquals(sevenOfTwelve, 0.3195, 0.001);
  assertAlmostEquals(threeOfFour, 0.3006, 0.001);

  if (!(eightOfTwelve > threeOfFour)) throw new Error("8 of 12 must outrank 3 of 4");
  if (!(sevenOfTwelve > threeOfFour)) throw new Error("7 of 12 must still outrank 3 of 4");
  if (!(sixOfTwelve < threeOfFour)) throw new Error("6 of 12 must not outrank 3 of 4");
});

Deno.test("the Wilson upper bound is the more generous bound, and both are zero with nothing to rank", () => {
  const lower = wilsonLowerBound(1, 4);
  const upper = wilsonUpperBound(1, 4);
  if (!(upper > lower)) throw new Error("the upper bound must sit above the lower bound");

  assertEquals(wilsonLowerBound(0, 0), 0);
  assertEquals(wilsonUpperBound(0, 0), 0);
});

// ─── `E40-01`: what a read counts, and who it credits ──────────────────────
//
// This aggregation used to live inline in `groups/index.ts` and had no unit coverage at all —
// only `standings.test.ts`'s single scored night, over HTTP, which cannot reach the cases below
// without building four more fixture evenings. The four tests here are the four claims the epic
// makes; the HTTP test still proves they are wired to the route.

/** Three nights, and who submitted on each. Ana and Ben played all three; Cal missed `r3`. */
const submitted = new Map([
  ["ana", new Set(["r1", "r2", "r3"])],
  ["ben", new Set(["r1", "r2", "r3"])],
  ["cal", new Set(["r1", "r2"])],
]);

function tally(rows: ReadGuessRow[], reader: string, subject: string) {
  return readTally(reader, subject, submitted, roundsGuessedIn(rows), correctReadRounds(rows));
}

Deno.test("a round the reader never guessed in leaves the denominator entirely", () => {
  // Ana guesses on r1 and r2 and never opens r3's sheet. docs/02 §4.1 drops that night from her
  // `ear`; it now drops from her reads too, rather than being divided into them as a miss.
  const rows: ReadGuessRow[] = [
    { round_id: "r1", guesser_id: "ana", guessed_user_id: "ben", is_correct: true },
    { round_id: "r2", guesser_id: "ana", guessed_user_id: "ben", is_correct: false },
  ];

  assertEquals(tally(rows, "ana", "ben"), { correct: 1, possible: 2 });
});

Deno.test("a card left blank in a round the reader did guess in is still a miss", () => {
  // The line this draws. Ana opened r2's sheet and named somebody — just not on Ben's card. That
  // is a miss, exactly as `ear`'s S−1 denominator makes it one; only the untouched sheet leaves.
  const rows: ReadGuessRow[] = [
    { round_id: "r1", guesser_id: "ana", guessed_user_id: "ben", is_correct: true },
    { round_id: "r2", guesser_id: "ana", guessed_user_id: "cal", is_correct: true },
  ];

  assertEquals(tally(rows, "ana", "ben"), { correct: 1, possible: 2 }, "r2 counts against Ben");
  assertEquals(tally(rows, "ana", "cal"), { correct: 1, possible: 2 }, "and r1 against Cal");
});

Deno.test("a duplicate-track read credits the person named, not the card's owner", () => {
  // Ana and Ben both drop Ribs. The reader writes "Ana" on Ben's card: correct under docs/02
  // §4.3, and a read of **Ana**, whom they named. Ben was not read by anybody that night, and
  // still owns the round in his own denominator.
  const rows: ReadGuessRow[] = [
    { round_id: "r1", guesser_id: "cal", guessed_user_id: "ana", is_correct: true },
    { round_id: "r2", guesser_id: "cal", guessed_user_id: "ben", is_correct: false },
  ];

  assertEquals(tally(rows, "cal", "ana"), { correct: 1, possible: 2 });
  assertEquals(tally(rows, "cal", "ben"), { correct: 0, possible: 2 }, "Ben is a miss, not a read");
});

Deno.test("naming the same person correctly on two cards in one night is one read", () => {
  // The duplicate rule scores both rows correct. A read is a round, not a row — counting rows
  // would put `correct` above `possible` and render a rate above 100%.
  const rows: ReadGuessRow[] = [
    { round_id: "r1", guesser_id: "cal", guessed_user_id: "ana", is_correct: true },
    { round_id: "r1", guesser_id: "cal", guessed_user_id: "ana", is_correct: true },
  ];

  assertEquals(tally(rows, "cal", "ana"), { correct: 1, possible: 1 });
});

Deno.test("a read needs both people in the round, and a reader with no sheets has nothing", () => {
  // Cal missed r3 entirely, so Ana's r3 guesses cannot become reads of Cal. And a reader who
  // never guessed has no rounds at all — the empty state, not a wall of zero percents.
  const rows: ReadGuessRow[] = [
    { round_id: "r3", guesser_id: "ana", guessed_user_id: "ben", is_correct: true },
  ];

  assertEquals(tally(rows, "ana", "cal"), { correct: 0, possible: 0 });
  assertEquals(tally(rows, "ben", "ana"), { correct: 0, possible: 0 }, "Ben opened no sheet");
});

Deno.test("the miss ranking prefers the best-evidenced silence, not the smallest sample", () => {
  // `compareMisses` in `groups/index.ts` sorts on this, ascending: a pair that has failed to read
  // each other across twenty rounds is a more credible miss than one that has had two chances.
  const overTwenty = wilsonUpperBound(0, 20);
  const overTwo = wilsonUpperBound(0, 2);
  const oneOfTwenty = wilsonUpperBound(1, 20);

  if (!(overTwenty < overTwo)) throw new Error("0 of 20 must rank as a stronger miss than 0 of 2");
  if (!(overTwenty < oneOfTwenty)) throw new Error("a landed read must rank below a total miss");
});
