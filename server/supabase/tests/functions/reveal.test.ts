// reveal.test.ts — the payoff, and the rules that survive it. tasks/E05-01, E05-02.
//
// The blind window is over by the time any of this runs, so the things `rounds.test.ts` is
// strict about — no counts, no other people's songs — stop applying and different rules take
// over. docs/02 §3 accepts that the name pool reveals who participated, because the game is
// unsolvable otherwise. What does *not* change:
//
//   · `submission_id` never crosses the wire before `scored` (ADR-003). Cards are numbers.
//   · Only submitters may guess, enforced server-side and not merely disabled in the UI.
//   · Nobody else's guesses are obtainable at any URL in this phase.

import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  call,
  keysOf,
  newGroupOwner,
  newMember,
  setJoinedAt,
  type TestUser,
  tickRoundsAt,
  zoneWhereLocalHourIs,
} from "./_harness.ts";

const REVEALED_KEYS = [
  "can_guess",
  "cannot_guess_reason",
  "cards",
  "local_date",
  "my_card_no",
  "my_guesses",
  "my_submission",
  "name_pool",
  "opens_at",
  "reveals_at",
  "round_id",
  "scores_at",
  "state",
].sort();

/** Eight Apple ids from the fixture catalogue, all distinct recordings. */
const TRACKS = [
  "1440818664", "1440765580", "1452874255", "1440830827",
  "1442571948", "1656689279", "1468055107", "1440908896",
];

interface Revealed {
  owner: TestUser;
  members: TestUser[];
  /** Everyone who submitted, owner first. */
  submitters: TestUser[];
  data: Record<string, never>;
}

/**
 * A group of `submitterCount` submitters plus `extra` non-submitters, revealed.
 *
 * Set up at 17:00 local with a reveal at 18:00 — `ensure_rounds()` will not create a round
 * whose reveal has already gone by — then the scheduler is run two hours on. Real transitions,
 * real `card_order`, only the instant is chosen.
 */
async function revealedRound(
  name: string,
  submitterCount: number,
  extra = 0,
): Promise<Revealed> {
  const { user: owner, group } = await newGroupOwner("Ana", {
    name,
    timezone: zoneWhereLocalHourIs(17),
    reveal_hour: 18,
  });
  const code = group.invite_code as string;
  const names = ["Ben", "Cal", "Dee", "Eli", "Fay", "Gus", "Hal", "Ivy", "Jo", "Kit", "Lou"];
  const members: TestUser[] = [];
  for (let i = 0; i < submitterCount - 1 + extra; i += 1) {
    members.push(await newMember(code, names[i]));
  }

  const submitters = [owner, ...members.slice(0, submitterCount - 1)];
  for (const [i, member] of submitters.entries()) {
    const res = await call("rounds", "/current/submission", {
      method: "PUT",
      token: member.token,
      body: { apple_music_id: TRACKS[i % TRACKS.length] },
    });
    assertEquals(res.status, 200, `${i} could not submit`);
  }

  await tickRoundsAt(2);
  const res = await call("rounds", "/current", { token: owner.token });
  assertEquals(res.body.data.state, "revealed", `${name} did not reveal`);
  return { owner, members, submitters, data: res.body.data };
}

// ─── E05-01 · the revealed payload ───────────────────────────────────────────

Deno.test("the revealed payload has exactly the documented key set", async () => {
  const { data } = await revealedRound("Reveal Shape", 4);
  assertEquals(keysOf(data), REVEALED_KEYS);
  assertEquals((data as Record<string, unknown>).state, "revealed");
});

Deno.test("cards include every card, the caller's own included", async () => {
  // docs/08 §6: the client removes its own card from the *guessing* sheet using `my_card_no`,
  // but the card is still listed. The numbering is the game's spine and must not have a hole —
  // "card 3 of 5" with only four cards is a bug report waiting to happen.
  const { data } = await revealedRound("Every Card", 5);
  const cards = (data as Record<string, unknown>).cards as { card_no: number }[];

  assertEquals(cards.length, 5, "five submitters, five cards");
  assertEquals(cards.map((c) => c.card_no), [1, 2, 3, 4, 5], "consecutive from 1, in order");

  const myCardNo = (data as Record<string, unknown>).my_card_no as number;
  assert(myCardNo >= 1 && myCardNo <= 5);
  assert(cards.some((c) => c.card_no === myCardNo), "the caller's own card is present");
});

Deno.test("no submission_id appears anywhere in a revealed payload", async () => {
  // ADR-003. A submission id would be a durable handle to a row whose owner is the answer to
  // the game. Cards are addressed by number, everywhere, in both directions.
  const { data, owner } = await revealedRound("No Ids", 4);
  const serialised = JSON.stringify(data);

  assertEquals(
    serialised.match(/"submission_id"/g),
    null,
    "a field named submission_id is in the revealed payload",
  );

  // Stronger: no uuid in the payload may be a submission id. The only uuids that legitimately
  // appear are user ids — in `name_pool` and `my_guesses` — so anything else is a leak.
  const uuids = new Set(serialised.match(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi) ?? []);
  const pool = (data as Record<string, unknown>).name_pool as { user_id: string }[];
  const allowed = new Set([...pool.map((p) => p.user_id), (data as Record<string, unknown>).round_id as string]);
  for (const id of uuids) {
    assert(allowed.has(id), `an unexpected uuid ${id} is in the revealed payload`);
  }
  assert(owner.id.length > 0);
});

Deno.test("every member receives an identical card_no → track sequence", async () => {
  // AC-5. The shuffle happens once, at the transition, and the stored order is authoritative
  // and identical for everybody (docs/02 §2). A per-user order would make the guess sheet
  // unshareable and the game unarguable.
  const { submitters, members } = await revealedRound("Same Order", 8);

  const sequences: string[] = [];
  for (const member of [...submitters, ...members.slice(7)]) {
    const res = await call("rounds", "/current", { token: member.token });
    const cards = res.body.data.cards as { card_no: number; track: { track_key: string } }[];
    sequences.push(cards.map((c) => `${c.card_no}:${c.track.track_key}`).join("|"));
  }

  assertEquals(sequences.length, 8);
  assertEquals(new Set(sequences).size, 1, "the card order differed between members");
});

Deno.test("the name pool is exactly this round's submitters, caller included", async () => {
  // Two members joined and did not submit. docs/02 §3: the pool is the submitters and nobody
  // else — padding it with non-submitters makes the game harder in a way that is not fun, and
  // players work out the padding within two rounds.
  const { data, submitters, members } = await revealedRound("Name Pool", 4, 2);
  const pool = (data as Record<string, unknown>).name_pool as { user_id: string }[];
  const poolIds = new Set(pool.map((p) => p.user_id));

  assertEquals(poolIds.size, 4, "four submitters, four names");
  for (const submitter of submitters) {
    assert(poolIds.has(submitter.id), "a submitter is missing from the pool");
  }
  for (const absentee of members.slice(3)) {
    assert(!poolIds.has(absentee.id), "somebody who did not submit is in the pool");
  }
  assertEquals(keysOf(pool[0]), ["display_name", "user_id"], "and a pool entry is name and id only");
});

Deno.test("a non-submitter can see the reveal but is told why they cannot guess", async () => {
  // docs/02 §3: this is the participation-pressure mechanic, and it is reflected in the UI as
  // a disabled sheet with an explanation — never as a hidden feature.
  const { members } = await revealedRound("Non Submitter", 3, 1);
  const absentee = members[members.length - 1];

  const res = await call("rounds", "/current", { token: absentee.token });
  assertEquals(res.status, 200);
  assertEquals(keysOf(res.body.data), REVEALED_KEYS);
  assertEquals(res.body.data.can_guess, false);
  assertEquals(res.body.data.cannot_guess_reason, "not_a_submitter");
  assertEquals(res.body.data.my_card_no, null);
  assertEquals(res.body.data.my_submission, null);
  assertEquals((res.body.data.cards as unknown[]).length, 3, "they can still see the reveal");
});

Deno.test("somebody who joined after the reveal sits the round out", async () => {
  // docs/02 §3: they can view the reveal, cannot guess, and are excluded from the round's
  // scoring entirely. `joined_late` rather than `not_a_submitter`, because the two mean
  // different things to a player and the copy differs.
  const { owner, members, data } = await revealedRound("Joined Late", 3);
  const group = (await call("groups", "/current", { token: owner.token })).body.data;
  const latecomer = await newMember(group.invite_code as string, "Late");
  // A minute past the reveal. See `setJoinedAt` — a test cannot wait out the real hour
  // between a round's creation and its reveal.
  await setJoinedAt(latecomer.id, new Date(Date.parse(data.reveals_at as string) + 60_000));

  const res = await call("rounds", "/current", { token: latecomer.token });
  assertEquals(res.body.data.can_guess, false);
  assertEquals(res.body.data.cannot_guess_reason, "joined_late");
  assertEquals(res.body.data.my_submission, null);
  assertEquals((res.body.data.cards as unknown[]).length, 3, "they can still view the reveal");
  assert(members.length > 0);
});

Deno.test("my_guesses is the caller's own sheet and nobody else's", async () => {
  const { submitters } = await revealedRound("Own Sheet", 4);
  const [ana, ben] = submitters;

  const anaView = (await call("rounds", "/current", { token: ana.token })).body.data;
  const anaCard = anaView.my_card_no as number;
  const target = (anaView.cards as { card_no: number }[]).find((c) => c.card_no !== anaCard)!;

  const saved = await call("rounds", "/current/guesses", {
    method: "PUT",
    token: ana.token,
    body: { assignments: [{ card_no: target.card_no, guessed_user_id: ben.id }] },
  });
  assertEquals(saved.status, 200);

  assertEquals(
    (await call("rounds", "/current", { token: ana.token })).body.data.my_guesses,
    [{ card_no: target.card_no, guessed_user_id: ben.id }],
  );
  // Ben has guessed nothing, and Ana's sheet is not his to see.
  assertEquals((await call("rounds", "/current", { token: ben.token })).body.data.my_guesses, []);
});

Deno.test("no route returns another user's guesses in this phase", async () => {
  // E05-01 asks for this by enumerating routes rather than by inspection. Every route in
  // `functions/` is called as Ben, and the assertion is that Ana's saved guess — a uuid he has
  // no other way to obtain in relation to a card — appears in none of them.
  const { submitters } = await revealedRound("Guess Privacy", 4);
  const [ana, ben, cal] = submitters;

  const anaView = (await call("rounds", "/current", { token: ana.token })).body.data;
  const anaCard = anaView.my_card_no as number;
  const target = (anaView.cards as { card_no: number }[]).find((c) => c.card_no !== anaCard)!;
  await call("rounds", "/current/guesses", {
    method: "PUT",
    token: ana.token,
    body: { assignments: [{ card_no: target.card_no, guessed_user_id: cal.id }] },
  });

  const functionsDir = new URL("../../functions/", import.meta.url);
  const routes: { fn: string; method: string; path: string }[] = [];
  for await (const entry of Deno.readDir(functionsDir)) {
    if (!entry.isDirectory || entry.name.startsWith("_")) continue;
    let source: string;
    try {
      source = await Deno.readTextFile(new URL(`${entry.name}/index.ts`, functionsDir));
    } catch {
      continue;
    }
    for (const match of source.matchAll(/^\s*"(GET|PUT|POST|PATCH|DELETE) ([^"]*)":/gm)) {
      // DELETE /me would end Ben's own account mid-test, and it returns 204 with no body to
      // leak. Everything else is called for real.
      if (entry.name === "me" && match[1] === "DELETE") continue;
      routes.push({ fn: entry.name, method: match[1], path: match[2] });
    }
  }
  assert(routes.length >= 10, `only found ${routes.length} routes to probe`);

  for (const route of routes) {
    const res = await call(route.fn, route.path, { method: route.method, token: ben.token, body: {} });
    const serialised = JSON.stringify(res.body ?? {});
    // Ana's guess is "Cal, on card N". Ben may legitimately see Cal's *name and id* — the name
    // pool is public in this phase — so what must not be obtainable is the pairing. The only
    // route that returns a card→user pairing at all is `my_guesses`, and Ben's is empty.
    if (serialised.includes("my_guesses")) {
      assertEquals(res.body.data.my_guesses, [], `${route.method} ${route.fn}${route.path}`);
    }
    assert(
      !serialised.includes("guesser_id") && !serialised.includes("guessed_by"),
      `${route.method} ${route.fn}${route.path} exposes a guesser`,
    );
  }
});

// ─── E05-02 · the guess sheet ────────────────────────────────────────────────

/** Ana's view, plus a card that is not hers and somebody who is not her. */
async function sheetContext(name: string, submitters = 4) {
  const round = await revealedRound(name, submitters);
  const [ana, ben, cal] = round.submitters;
  const view = (await call("rounds", "/current", { token: ana.token })).body.data;
  const myCardNo = view.my_card_no as number;
  const others = (view.cards as { card_no: number }[])
    .map((c) => c.card_no)
    .filter((n) => n !== myCardNo);
  return { ...round, ana, ben, cal, view, myCardNo, others };
}

const putGuesses = (token: string, assignments: unknown[]) =>
  call("rounds", "/current/guesses", { method: "PUT", token, body: { assignments } });

Deno.test("a whole-sheet upsert returns the sheet with its two counts", async () => {
  const { ana, ben, cal, others } = await sheetContext("Sheet Counts", 5);

  const res = await putGuesses(ana.token, [
    { card_no: others[0], guessed_user_id: ben.id },
    { card_no: others[1], guessed_user_id: cal.id },
  ]);

  assertEquals(res.status, 200);
  assertEquals(keysOf(res.body.data), ["assignable_count", "assigned_count", "assignments"]);
  assertEquals(res.body.data.assigned_count, 2);
  // S − 1: every card the caller could be asked about (docs/02 §4.1).
  assertEquals(res.body.data.assignable_count, 4);
  assertEquals(res.body.data.assignments.length, 2);
});

Deno.test("an omitted card is untouched; an explicit null clears it", async () => {
  // docs/04 §4 rule 7. This is what makes the endpoint safe to call on every debounce with
  // whatever the sheet currently shows.
  const { ana, ben, cal, others } = await sheetContext("Partial Sheet", 5);

  await putGuesses(ana.token, [
    { card_no: others[0], guessed_user_id: ben.id },
    { card_no: others[1], guessed_user_id: cal.id },
  ]);

  // A second call mentioning only one card leaves the other alone.
  const partial = await putGuesses(ana.token, [{ card_no: others[2], guessed_user_id: ben.id }]);
  assertEquals(partial.body.data.assigned_count, 3, "the earlier two were not cleared");

  const cleared = await putGuesses(ana.token, [{ card_no: others[0], guessed_user_id: null }]);
  assertEquals(cleared.body.data.assigned_count, 2);
  assert(
    !(cleared.body.data.assignments as { card_no: number }[]).some((a) => a.card_no === others[0]),
    "the explicitly-nulled card is gone",
  );
});

Deno.test("the same person may be named on two cards", async () => {
  // docs/04 §4 rule 6, deliberately permitted: players double-assign while thinking. The UI
  // discourages it; the API allows it and scoring handles it naturally.
  const { ana, ben, others } = await sheetContext("Double Assign", 5);
  const res = await putGuesses(ana.token, [
    { card_no: others[0], guessed_user_id: ben.id },
    { card_no: others[1], guessed_user_id: ben.id },
  ]);
  assertEquals(res.status, 200);
  assertEquals(res.body.data.assigned_count, 2);
});

Deno.test("a guess is refused outside the revealed phase", async () => {
  const { user } = await newGroupOwner("Ana", {
    name: "Guess Wrong Phase",
    timezone: zoneWhereLocalHourIs(12),
    reveal_hour: 20,
  });
  await call("rounds", "/current/submission", {
    method: "PUT",
    token: user.token,
    body: { apple_music_id: "1440818664" },
  });

  const res = await putGuesses(user.token, []);
  assertEquals(res.status, 409);
  assertEquals(res.body.error.code, "WRONG_PHASE");
  assertEquals(res.body.error.state, "open");
  assertEquals(keysOf(res.body.error), ["code", "message", "state"]);
});

Deno.test("only submitters may guess, and it is the server that says so", async () => {
  // CLAUDE.md §2.3. The UI disables the sheet; this is the enforcement.
  const { members } = await revealedRound("Only Submitters", 3, 1);
  const absentee = members[members.length - 1];

  const res = await putGuesses(absentee.token, []);
  assertEquals(res.status, 403);
  assertEquals(res.body.error.code, "NOT_A_SUBMITTER");
});

Deno.test("somebody who joined after the reveal cannot guess", async () => {
  const { owner, data } = await revealedRound("Late Guesser", 3);
  const group = (await call("groups", "/current", { token: owner.token })).body.data;
  const latecomer = await newMember(group.invite_code as string, "Late");
  await setJoinedAt(latecomer.id, new Date(Date.parse(data.reveals_at as string) + 60_000));

  const res = await putGuesses(latecomer.token, []);
  assertEquals(res.status, 403);
  // They are also not a submitter — they could not have been — so which code answers is a real
  // choice. JOINED_LATE, because it is the specific one and the general one would make it
  // unreachable. See the open question in tasks/E05 and `cannotGuessReason`.
  assertEquals(res.body.error.code, "JOINED_LATE");
});

Deno.test("card_no is validated in 1..N and cannot be the caller's own", async () => {
  const { ana, ben, myCardNo, others } = await sheetContext("Card Validation", 4);

  for (const cardNo of [0, -1, 99, 4.5]) {
    const res = await putGuesses(ana.token, [{ card_no: cardNo, guessed_user_id: ben.id }]);
    assertEquals(res.status, 400, `card_no ${cardNo}`);
    assertEquals(res.body.error.details, { field: "card_no" });
  }

  // Guessing at your own song is meaningless, and the `guesses_not_self` trigger would refuse
  // it anyway — this turns a database exception into the documented 400.
  const own = await putGuesses(ana.token, [{ card_no: myCardNo, guessed_user_id: ben.id }]);
  assertEquals(own.status, 400);
  assertEquals(own.body.error.details, { field: "card_no" });
  assert(others.length > 0);
});

Deno.test("guessed_user_id must be in the name pool and cannot be the caller", async () => {
  const { ana, others } = await sheetContext("Pool Validation", 4);

  // A real user, in no group of ours.
  const stranger = await newGroupOwner("Stranger", {
    name: "Elsewhere",
    timezone: zoneWhereLocalHourIs(12),
    reveal_hour: 20,
  });

  for (const id of [stranger.user.id, ana.id, crypto.randomUUID()]) {
    const res = await putGuesses(ana.token, [{ card_no: others[0], guessed_user_id: id }]);
    assertEquals(res.status, 400, id);
    assertEquals(res.body.error.details, { field: "guessed_user_id" });
  }

  const malformed = await putGuesses(ana.token, [{ card_no: others[0], guessed_user_id: "not-a-uuid" }]);
  assertEquals(malformed.status, 400);
  assertEquals(malformed.body.error.details, { field: "guessed_user_id" });
});

Deno.test("a non-submitter in the group is not in the pool and cannot be named", async () => {
  // The pool is the round's submitters. Naming somebody who sat the round out is not a wrong
  // guess — it is a malformed one, and scoring would have no card to compare it against.
  const { submitters, members } = await revealedRound("Absent Names", 4, 1);
  const ana = submitters[0];
  const absentee = members[members.length - 1];

  const view = (await call("rounds", "/current", { token: ana.token })).body.data;
  const target = (view.cards as { card_no: number }[])
    .find((c) => c.card_no !== view.my_card_no)!;

  const res = await putGuesses(ana.token, [
    { card_no: target.card_no, guessed_user_id: absentee.id },
  ]);
  assertEquals(res.status, 400);
  assertEquals(res.body.error.details, { field: "guessed_user_id" });
});

Deno.test("the request body is validated like every other body", async () => {
  const { ana, ben, others } = await sheetContext("Body Validation", 4);

  const notAList = await call("rounds", "/current/guesses", {
    method: "PUT",
    token: ana.token,
    body: { assignments: "everything" },
  });
  assertEquals(notAList.status, 400);
  assertEquals(notAList.body.error.details, { field: "assignments" });

  // docs/14 §7: an unknown key is rejected, not ignored — including inside a nested entry.
  const extraKey = await putGuesses(ana.token, [
    { card_no: others[0], guessed_user_id: ben.id, is_correct: true },
  ]);
  assertEquals(extraKey.status, 400);
  assertEquals(extraKey.body.error.details, { field: "is_correct" });

  const unbounded = await putGuesses(
    ana.token,
    Array.from({ length: 65 }, () => ({ card_no: others[0], guessed_user_id: ben.id })),
  );
  assertEquals(unbounded.status, 400);
});

Deno.test("guesses stay editable, and a rejected request changes nothing", async () => {
  const { ana, ben, cal, others } = await sheetContext("Editable", 5);

  await putGuesses(ana.token, [{ card_no: others[0], guessed_user_id: ben.id }]);
  const changed = await putGuesses(ana.token, [{ card_no: others[0], guessed_user_id: cal.id }]);
  assertEquals(changed.body.data.assignments, [{ card_no: others[0], guessed_user_id: cal.id }]);

  // A request that fails validation part-way through must not half-apply: the valid first
  // entry is not written because the second one is refused.
  const rejected = await putGuesses(ana.token, [
    { card_no: others[1], guessed_user_id: ben.id },
    { card_no: 99, guessed_user_id: ben.id },
  ]);
  assertEquals(rejected.status, 400);
  const after = (await call("rounds", "/current", { token: ana.token })).body.data.my_guesses;
  assertEquals(after, [{ card_no: others[0], guessed_user_id: cal.id }], "nothing was half-written");
});
