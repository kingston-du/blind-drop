import { assertEquals } from "jsr:@std/assert@1";
import { confusionMinimumRounds, confusionPairs } from "../../functions/_shared/insights.ts";

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
