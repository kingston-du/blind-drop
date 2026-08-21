// _shared/insights.ts — pure scored-history aggregations used by the Insights route.

import type { InsightConfusionPairDTO, MemberDTO } from "./dto.ts";

export interface InsightGuessRow {
  guesser_id: string;
  card_owner_id: string;
  guessed_user_id: string;
  is_correct: boolean;
}

/** A confusion matrix needs materially more history than a one-to-one read. */
export function confusionMinimumRounds(memberCount: number): number {
  return memberCount ** 2;
}

/**
 * Returns the most repeated wrong attributions in deterministic order. Correct guesses naming
 * a duplicate-track submitter never enter this lens: the game scores them as reads, not misses.
 */
export function confusionPairs(
  rows: InsightGuessRow[],
  members: Map<string, MemberDTO>,
  limit: number,
): InsightConfusionPairDTO[] {
  const pairs = new Map<string, InsightConfusionPairDTO>();
  for (const row of rows) {
    if (row.is_correct) continue;
    const guesser = members.get(row.guesser_id);
    const actual = members.get(row.card_owner_id);
    const mistakenFor = members.get(row.guessed_user_id);
    if (!guesser || !actual || !mistakenFor) continue;

    const key = `${actual.user_id}:${mistakenFor.user_id}`;
    const existing = pairs.get(key);
    if (existing) {
      existing.count += 1;
    } else {
      pairs.set(key, { actual_member: actual, mistaken_for_member: mistakenFor, count: 1 });
    }
  }
  const compareMember = (a: MemberDTO, b: MemberDTO): number =>
    a.display_name.localeCompare(b.display_name) || a.user_id.localeCompare(b.user_id);
  return [...pairs.values()]
    .sort((a, b) => b.count - a.count || compareMember(a.actual_member, b.actual_member)
      || compareMember(a.mistaken_for_member, b.mistaken_for_member))
    .slice(0, limit);
}
