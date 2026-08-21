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

// ─── Wilson score interval — `E28-07` ──────────────────────────────────────
//
// A rate alone ranks a thin 3-of-4 above a well-supported 8-of-12, which is not what "reads them
// best" means. The Wilson score interval is a 95% confidence bound on the true rate behind a
// `correct/possible` sample — not an invented weighting — and using its **lower** bound to rank
// answers the owner's worked cases directly: 8-of-12 (≈0.391) outranks 3-of-4 (≈0.301), and so
// does the smaller-but-still-better-supported 7-of-12 (≈0.320), while 6-of-12 (≈0.254) does not.
// "Hardest to read" ranks by the **upper** bound instead, ascending, by the same argument run the
// other way: a single unlucky round with one person should not credibly claim the room cannot
// read the caller at all, and the upper bound is the most generous the sample can support.
const WILSON_Z_95 = 1.959963984540054;

interface WilsonBounds {
  lower: number;
  upper: number;
}

function wilsonBounds(correct: number, possible: number): WilsonBounds {
  if (possible <= 0) return { lower: 0, upper: 0 };
  const n = possible;
  const p = correct / n;
  const z2 = WILSON_Z_95 * WILSON_Z_95;
  const denominator = 1 + z2 / n;
  const center = p + z2 / (2 * n);
  const margin = WILSON_Z_95 * Math.sqrt((p * (1 - p)) / n + z2 / (4 * n * n));
  return {
    lower: (center - margin) / denominator,
    upper: (center + margin) / denominator,
  };
}

export function wilsonLowerBound(correct: number, possible: number): number {
  return wilsonBounds(correct, possible).lower;
}

export function wilsonUpperBound(correct: number, possible: number): number {
  return wilsonBounds(correct, possible).upper;
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
