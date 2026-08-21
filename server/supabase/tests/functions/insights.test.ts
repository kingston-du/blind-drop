import { assertAlmostEquals, assertEquals } from "jsr:@std/assert@1";
import {
  confusionMinimumRounds,
  confusionPairs,
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
