// standings.test.ts — all time. tasks/E05-05, docs/04 §4, docs/02 §4.2, §4.5.
//
// `tests/db/standings.sql` already proves the arithmetic: pooled ear, mean readability, and the
// asymmetry between them across rounds of three different sizes. What it cannot prove is that
// the two lists come out of the API shaped differently, and that is the whole of docs/02 §4.5:
//
//   **Best Ear is ranked. Readability is not, and must not carry a `rank` field.**
//
// Guessing well is a scoreboard. Being hard to read is a trait, and low readability is its own
// kind of win. The rule is enforced by not sending the field, because a client that receives a
// rank will render it — and the test at the bottom of this file is the one that notices the day
// somebody adds one "for consistency".
//
// The round is built here rather than borrowed from `seed.sql`, whose group is shared with the
// rest of the suite: any test that runs the scheduler scores another of its rounds, so its
// all-time numbers are a function of what else ran today. A group this file owns has standings
// it can state exactly.

import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  call,
  keysOf,
  newGroupOwner,
  newMember,
  newNamedUser,
  type TestUser,
  tickRoundsAt,
  zoneWhereLocalHourIs,
} from "./_harness.ts";

// deno-lint-ignore no-explicit-any
type Json = any;

/** Five distinct recordings from the fixture catalogue, so ownership is unambiguous — the
 *  duplicate rule in docs/02 §4.3 is `scoring.sql`'s to test, not this file's. */
const TRACKS = ["1440818664", "1440765580", "1452874255", "1440830827", "1442571948"];
const NAMES = ["Ana", "Ben", "Cal", "Dee", "Eli"] as const;

interface Scored {
  people: Record<string, TestUser>;
  standings: Json;
}

/**
 * One scored round, with hand-chosen guesses, so every number below is stated rather than
 * recomputed:
 *
 *   Ana  names all four correctly              ear 4/4
 *   Ben  correct on Ana and Cal, wrong twice   ear 2/4
 *   Cal  correct on Ana and Ben, wrong twice   ear 2/4   ← ties with Ben
 *   Dee  wrong on all four                     ear 0/4
 *   Eli  assigns nothing                       ear null  ← not a zero
 *
 * which puts the correct-guess counts on the cards at Ana 2, Ben 2, Cal 2, Dee 1, Eli 1, over a
 * denominator of S − 1 = 4.
 *
 * The guessers work out which card is whose the same way the test does — from the `track_key`
 * on each card, against the track each person was told to drop. A player cannot do that, which
 * is the game; a test can, which is how it gets to assert a specific answer.
 */
async function scoredRound(name: string): Promise<Scored> {
  const { user: ana, group } = await newGroupOwner("Ana", {
    name,
    timezone: zoneWhereLocalHourIs(17),
    reveal_hour: 18,
  });
  const code = group.invite_code as string;
  const people: Record<string, TestUser> = { Ana: ana };
  for (const person of NAMES.slice(1)) people[person] = await newMember(code, person);

  // track_key → who dropped it.
  const ownerOf = new Map<string, string>();
  for (const [i, person] of NAMES.entries()) {
    const res = await call("rounds", "/current/submission", {
      method: "PUT",
      token: people[person].token,
      body: { apple_music_id: TRACKS[i] },
    });
    assertEquals(res.status, 200, `${person} could not drop a song`);
    ownerOf.set(res.body.data.track.track_key as string, person);
  }

  await tickRoundsAt(2);

  /** `card_no → the name of whoever dropped it`, decoded from the caller's own view. */
  async function cardOwners(person: string): Promise<Map<number, string>> {
    const res = await call("rounds", "/current", { token: people[person].token });
    assertEquals(res.body.data.state, "revealed", `${name} did not reveal`);
    return new Map(
      (res.body.data.cards as Json[]).map((card) => [
        card.card_no as number,
        ownerOf.get(card.track.track_key as string)!,
      ]),
    );
  }

  /** `guesser` assigns a name to every card but their own, choosing the true owner for the
   *  people in `correctOn` and a deliberate miss everywhere else. */
  async function guess(guesser: string, correctOn: string[]): Promise<void> {
    const owners = await cardOwners(guesser);
    const assignments = [...owners.entries()]
      .filter(([, owner]) => owner !== guesser)
      .map(([cardNo, owner]) => {
        // A miss has to be somebody real: the name pool is this round's submitters and the
        // caller may not name themselves (docs/04 §4). "Ana" serves for every wrong answer
        // except on Ana's own card, where "Ben" does — duplicates across cards are allowed.
        const named = correctOn.includes(owner) ? owner : (owner === "Ana" ? "Ben" : "Ana");
        assert(named !== guesser, "a wrong answer must not be the guesser themselves");
        return { card_no: cardNo, guessed_user_id: people[named].id };
      });

    const res = await call("rounds", "/current/guesses", {
      method: "PUT",
      token: people[guesser].token,
      body: { assignments },
    });
    assertEquals(res.status, 200, `${guesser} could not save a sheet: ${JSON.stringify(res.body)}`);
  }

  await guess("Ana", ["Ben", "Cal", "Dee", "Eli"]);
  await guess("Ben", ["Ana", "Cal"]);
  await guess("Cal", ["Ana", "Ben"]);
  await guess("Dee", []);
  // Eli opens the app and assigns nothing. Not a call at all — that is the point.

  await tickRoundsAt(4);
  const res = await call("groups", "/current/standings", { token: ana.token });
  assertEquals(res.status, 200, `standings failed: ${JSON.stringify(res.body)}`);
  return { people, standings: res.body.data };
}

// ─── shape ───────────────────────────────────────────────────────────────────

Deno.test("standings has exactly the documented key set", async () => {
  const { standings } = await scoredRound("Standings Shape");

  assertEquals(keysOf(standings), ["best_ear", "readability", "rounds_played"]);
  assertEquals(standings.rounds_played, 1, "one scored round, so one night played");
  assertEquals(keysOf(standings.best_ear[0]), [
    "display_name",
    "ear_all_time",
    "ear_correct_total",
    "rank",
    "user_id",
  ]);
  assertEquals(keysOf(standings.readability[0]), [
    "band",
    "display_name",
    "readability_all_time",
    "user_id",
  ]);
});

// ─── Best Ear is ranked ──────────────────────────────────────────────────────

Deno.test("best_ear is ranked, ties share a rank, and the next rank skips", async () => {
  // 1, 2, 2, 4 — competition ranking. Ben and Cal both guessed two of four, so they share
  // second and nobody is third. A dense ranking (1, 2, 2, 3) would quietly tell Dee she came
  // third in a group where two people finished ahead of her.
  const { standings } = await scoredRound("Standings Rank");
  const ear = standings.best_ear as Json[];

  assertEquals(ear.map((e) => e.display_name), ["Ana", "Ben", "Cal", "Dee"]);
  assertEquals(ear.map((e) => e.rank), [1, 2, 2, 4]);
  assertEquals(ear.map((e) => e.ear_correct_total), [4, 2, 2, 0]);

  assertEquals(ear[0].ear_all_time, 1, "Ana named all four");
  assertEquals(ear[1].ear_all_time, 0.5);
  assertEquals(ear[2].ear_all_time, 0.5, "the tie is a real tie, not a display rounding");
  assertEquals(ear[3].ear_all_time, 0, "Dee guessed and got none right — a genuine zero");
});

Deno.test("someone who never guessed is absent from best_ear, not last in it", async () => {
  // docs/02 §4.1 draws this line for a single round and it holds all the way up: never guessing
  // is not guessing badly. Eli has no ear at all, and the leaderboard is the one surface where
  // a dash in last place would read as a score.
  const { people, standings } = await scoredRound("Standings Absent");

  assert(
    !(standings.best_ear as Json[]).some((e) => e.user_id === people.Eli.id),
    "Eli made no guesses and must not be ranked",
  );
  // She is on the readability list all the same: how much of the room read you does not depend
  // on whether you looked.
  assert(
    (standings.readability as Json[]).some((r) => r.user_id === people.Eli.id),
    "Eli still has a readability",
  );
});

// ─── readability is not ranked ───────────────────────────────────────────────

Deno.test("the readability array contains no key named rank", async () => {
  // The checklist item, asserted over every row rather than the first: a client that receives a
  // rank will render it, and docs/02 §4.5 says readability has no rank position and no arrow.
  const { standings } = await scoredRound("Standings No Rank");

  for (const row of standings.readability as Json[]) {
    assert(!("rank" in row), `readability carried a rank for ${row.display_name}`);
    assert(!("position" in row) && !("place" in row), "nor anything wearing a different hat");
  }
});

Deno.test("readability is sorted descending, with the docs/02 §4.5 band", async () => {
  const { standings } = await scoredRound("Standings Bands");
  const rows = standings.readability as Json[];

  assertEquals(rows.length, 5, "every submitter has a readability, including Eli");
  const rates = rows.map((r) => r.readability_all_time as number);
  assertEquals([...rates].sort((a, b) => b - a), rates, "sorted descending, for a stable list");

  // Ana, Ben and Cal were each read by two of four; Dee and Eli by one of four.
  assertEquals(rows.map((r) => r.display_name), ["Ana", "Ben", "Cal", "Dee", "Eli"]);
  assertEquals(rates, [0.5, 0.5, 0.5, 0.25, 0.25]);
  assertEquals(
    rows.map((r) => r.band),
    ["mixed_signals", "mixed_signals", "mixed_signals", "hard_to_place", "hard_to_place"],
    "40–59% is mixed signals, 20–39% is hard to place",
  );
});

// ─── the guards ──────────────────────────────────────────────────────────────

Deno.test("a group with no scored rounds has empty lists, not an error", async () => {
  // The first week. docs/08 §7.3 wants two empty lists and a rounds_played of zero, not a 404 —
  // there is nothing wrong, there is just nothing yet.
  const { user } = await newGroupOwner("Ana", {
    name: "Standings Empty",
    timezone: zoneWhereLocalHourIs(12),
  });
  const res = await call("groups", "/current/standings", { token: user.token });

  assertEquals(res.status, 200);
  assertEquals(res.body.data, { rounds_played: 0, best_ear: [], readability: [] });
});

Deno.test("standings need a group", async () => {
  const stranger = await newNamedUser("Nobody");
  const res = await call("groups", "/current/standings", { token: stranger.token });

  assertEquals(res.status, 409);
  assertEquals(res.body.error.code, "NO_GROUP");
});
