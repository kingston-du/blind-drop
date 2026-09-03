// _shared/insights.ts — pure scored-history aggregations used by the Insights route.

import type { InsightConfusionPairDTO, MemberDTO } from "./dto.ts";

export interface InsightGuessRow {
  guesser_id: string;
  card_owner_id: string;
  guessed_user_id: string;
  is_correct: boolean;
}

/** What a *read* is counted from, which is less than the confusion lens needs: a read does not
 *  care whose card the name was written on (see `correctReadRounds`), and it is counted per
 *  round rather than per row. */
export interface ReadGuessRow {
  round_id: string;
  guesser_id: string;
  guessed_user_id: string;
  is_correct: boolean;
}

/** Both, for the one query that feeds both lenses. */
export interface InsightRoundGuessRow extends InsightGuessRow, ReadGuessRow {}

/** `reader:subject`, the direction a read runs in. */
export function readKey(reader: string, subject: string): string {
  return `${reader}:${subject}`;
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

// ─── what a read is, and is not — `E40-01` ──────────────────────────────────
//
// A read is counted **per round**, in one direction, between two people:
//
//   possible  rounds where both submitted **and the reader made at least one guess**
//   correct   of those, the rounds where the reader correctly named the subject
//
// Two corrections live in that sentence, and both look like details until you see what they do.
//
// **The reader has to have guessed.** `docs/02` §4.1 already drops a zero-guess round from `ear`
// — *"NULL means you sat this one out"* — and the pairwise number used to contradict it, counting
// every round both people merely submitted in. Sitting out ten sheets left your `ear` untouched
// while dividing every one of your reads by ten extra rounds. Note the line this draws: a round
// you played but *skipped this card in* is still a miss, exactly as `ear`'s `S − 1` denominator
// makes it one. Only the sheet you never touched at all leaves.
//
// **Credit follows the name, not the card.** `is_correct` (0005_scoring.sql) is an existence test
// on `(round_id, guessed_user_id, track_key)`, and this used to attribute it to `card_owner_id`.
// If Ana and Ben both dropped *Ribs* and you named Ana on Ben's card, you were credited with
// reading Ben — somebody you never named — while Ana, whom you did name and did get right, got
// nothing. Keying on `guessed_user_id` puts the credit where the naming happened. Ben keeps the
// round in his denominator, so it reads as the miss it was.
//
// `round_scores` still attributes the same guess to the card's owner, because `docs/02` §4.3 says
// core scoring does and that is an owner call, not a consequence of this file. So a circle with a
// duplicate night can show a readability that does not decompose into these pairwise reads. That
// is deliberate and it is stated in `docs/04` §4.

/** Rounds each person made at least one guess in. A round they never opened produces no rows at
 *  all, which is exactly how their absence is detected — there is nothing else to ask. */
export function roundsGuessedIn(rows: ReadGuessRow[]): Map<string, Set<string>> {
  const byGuesser = new Map<string, Set<string>>();
  for (const row of rows) {
    const rounds = byGuesser.get(row.guesser_id) ?? new Set<string>();
    rounds.add(row.round_id);
    byGuesser.set(row.guesser_id, rounds);
  }
  return byGuesser;
}

/**
 * Rounds in which each reader correctly named each subject, keyed `reader:subject`.
 *
 * A `Set` of rounds rather than a count, and that is load-bearing: with a duplicate track the same
 * reader can name the same person correctly on two cards in one night, and two rows for one
 * evening would be two reads of a person who could only be read once — a rate above 100%.
 */
export function correctReadRounds(rows: ReadGuessRow[]): Map<string, Set<string>> {
  const byDirection = new Map<string, Set<string>>();
  for (const row of rows) {
    if (!row.is_correct) continue;
    const key = readKey(row.guesser_id, row.guessed_user_id);
    const rounds = byDirection.get(key) ?? new Set<string>();
    rounds.add(row.round_id);
    byDirection.set(key, rounds);
  }
  return byDirection;
}

export interface ReadTally {
  correct: number;
  possible: number;
}

/**
 * One direction of one relationship. `submitted` maps a user to the scored rounds they submitted
 * in; `guessed` and `correct` come from the two functions above.
 *
 * Iterating the reader's *guessed* rounds rather than either submission set is what makes the
 * zero-guess round disappear without a special case: a round they never guessed in is not in the
 * set being walked.
 */
export function readTally(
  reader: string,
  subject: string,
  submitted: Map<string, Set<string>>,
  guessed: Map<string, Set<string>>,
  correct: Map<string, Set<string>>,
): ReadTally {
  const readerRounds = submitted.get(reader);
  const subjectRounds = submitted.get(subject);
  const guessedRounds = guessed.get(reader);
  if (!readerRounds || !subjectRounds || !guessedRounds) return { correct: 0, possible: 0 };

  const correctRounds = correct.get(readKey(reader, subject));
  const tally: ReadTally = { correct: 0, possible: 0 };
  for (const roundID of guessedRounds) {
    // Only submitters may guess, so `readerRounds` holds every round in `guessedRounds` already;
    // the check costs nothing and means this function cannot be handed inconsistent maps and
    // quietly count a round nobody played.
    if (!readerRounds.has(roundID) || !subjectRounds.has(roundID)) continue;
    tally.possible += 1;
    if (correctRounds?.has(roundID)) tally.correct += 1;
  }
  return tally;
}
