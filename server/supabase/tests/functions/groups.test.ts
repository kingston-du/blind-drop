// groups.test.ts — tasks/E02-03. docs/04 §3, docs/02 §1, docs/14 §3, §4.

import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  call,
  keysOf,
  newGroupOwner,
  newMember,
  newNamedUser,
  newUser,
  tickRounds,
  zoneWhereLocalHourIs,
} from "./_harness.ts";

const groups = (path: string, opts: Parameters<typeof call>[2] = {}) => call("groups", path, opts);

const GROUP_KEYS = [
  "cue_cadence",
  "cue_effective_from",
  "id",
  "invite_code",
  "is_admin",
  "members",
  "name",
  "reveal_effective_from",
  "reveal_hour",
  "timezone",
];

// ─── create ──────────────────────────────────────────────────────────────────

Deno.test("POST /groups creates the group and makes the creator its admin", async () => {
  const owner = await newNamedUser("Ana");
  const res = await groups("/", {
    method: "POST",
    token: owner.token,
    body: { name: "The Cove", timezone: "America/New_York", reveal_hour: 19 },
  });

  assertEquals(res.status, 200);
  assertEquals(keysOf(res.body.data), GROUP_KEYS);
  assertEquals(res.body.data.name, "The Cove");
  assertEquals(res.body.data.timezone, "America/New_York");
  assertEquals(res.body.data.reveal_hour, 19);
  assertEquals(res.body.data.is_admin, true);
  assertEquals(res.body.data.members, [{ user_id: owner.id, display_name: "Ana", role: "admin" }]);
  assertEquals(res.body.data.invite_code.length, 6);
});

Deno.test("POST /groups defaults reveal_hour to 20 and holds it to 18–21", async () => {
  const { group } = await newGroupOwner("Ana");
  assertEquals(group.reveal_hour, 20);

  for (const hour of [17, 22, 20.5, "20"]) {
    const user = await newNamedUser("Ben");
    const res = await groups("/", {
      method: "POST",
      token: user.token,
      body: { name: "The Cove", timezone: "UTC", reveal_hour: hour },
    });
    assertEquals(res.status, 400, `reveal_hour ${hour}`);
    assertEquals(res.body.error.details, { field: "reveal_hour" });
  }
});

Deno.test("POST /groups validates the timezone against pg_timezone_names", async () => {
  for (const timezone of ["Mars/Olympus_Mons", "america/new_york", "EST5EDT4", ""]) {
    const user = await newNamedUser("Ana");
    const res = await groups("/", {
      method: "POST",
      token: user.token,
      body: { name: "The Cove", timezone },
    });
    assertEquals(res.status, 400, `timezone ${JSON.stringify(timezone)}`);
    assertEquals(res.body.error.code, "INVALID_INPUT");
  }

  // And a real one, on the other side of the world, still works.
  const ok = await newGroupOwner("Ivy", { timezone: "Pacific/Auckland" });
  assertEquals(ok.group.timezone, "Pacific/Auckland");
});

Deno.test("POST /groups needs a profile first", async () => {
  const nameless = await newUser();
  const res = await groups("/", {
    method: "POST",
    token: nameless.token,
    body: { name: "The Cove", timezone: "UTC" },
  });
  assertEquals(res.status, 409);
  assertEquals(res.body.error.code, "NO_PROFILE");
});

Deno.test("POST /groups allows a second circle for someone with an active membership", async () => {
  // ADR-005 refused this. ADR-011 (tasks/E18-01) lifts it — a user may hold several active
  // circles, up to a cap. The cap itself, and the error it refuses with, are covered in
  // circles.test.ts.
  const { user } = await newGroupOwner("Ana");
  const res = await groups("/", {
    method: "POST",
    token: user.token,
    body: { name: "Another Cove", timezone: "UTC" },
  });
  assertEquals(res.status, 200);
  assertEquals(res.body.data.name, "Another Cove");
});

Deno.test("GET /groups/people-you-played-with returns shared people and no social graph", async () => {
  const { user: ana, group } = await newGroupOwner("Ana");
  const ben = await newMember(String(group.invite_code), "Ben");

  const res = await groups("/people-you-played-with", { token: ana.token });

  assertEquals(res.status, 200);
  assertEquals(res.body.data.people, [{ user_id: ben.id, display_name: "Ben" }]);
  assertEquals(keysOf(res.body.data.people[0]), ["display_name", "user_id"]);
});

// ─── join ────────────────────────────────────────────────────────────────────

Deno.test("POST /groups/join is case-insensitive and whitespace-tolerant", async () => {
  const { group } = await newGroupOwner("Ana");
  const code = String(group.invite_code);

  for (
    const typed of [code, code.toLowerCase(), ` ${code} `, `${code.slice(0, 3)} ${code.slice(3)}`]
  ) {
    const joiner = await newNamedUser("Ben");
    const res = await groups("/join", {
      method: "POST",
      token: joiner.token,
      body: { invite_code: typed },
    });
    assertEquals(res.status, 200, `typed ${JSON.stringify(typed)}`);
    assertEquals(res.body.data.id, group.id);
    assertEquals(res.body.data.is_admin, false);
  }
});

Deno.test("a bad code and a valid-but-unusable code are the same NOT_FOUND", async () => {
  const { group } = await newGroupOwner("Ana");

  const joiner = await newNamedUser("Ben");
  const unknown = await groups("/join", {
    method: "POST",
    token: joiner.token,
    body: { invite_code: "K7MQ2Z" },
  });
  const malformed = await groups("/join", {
    method: "POST",
    token: joiner.token,
    body: { invite_code: "I1LO0!" },
  });
  const tooShort = await groups("/join", {
    method: "POST",
    token: joiner.token,
    body: { invite_code: "ABC" },
  });

  for (const res of [unknown, malformed, tooShort]) {
    assertEquals(res.status, 404);
    assertEquals(res.body.error, unknown.body.error);
  }

  // Someone already in a group asking about a real code learns nothing about that group.
  await groups("/join", {
    method: "POST",
    token: joiner.token,
    body: { invite_code: group.invite_code },
  });
  const second = await groups("/join", {
    method: "POST",
    token: joiner.token,
    body: { invite_code: group.invite_code },
  });
  assertEquals(second.status, 409);
  assertEquals(second.body.error.code, "ALREADY_IN_GROUP");
});

// ─── current ─────────────────────────────────────────────────────────────────

Deno.test("GET /groups/current carries user_id, display_name and role only — docs/14 §3", async () => {
  const { user: owner, group } = await newGroupOwner("Ana");
  const ben = await newNamedUser("Ben");
  await groups("/join", {
    method: "POST",
    token: ben.token,
    body: { invite_code: group.invite_code },
  });

  const res = await groups("/current", { token: owner.token });
  assertEquals(res.status, 200);
  assertEquals(keysOf(res.body.data), GROUP_KEYS);
  assertEquals(res.body.data.members.length, 2);
  for (const member of res.body.data.members) {
    // No joined_at. A joined_at that changed today, plus a missing name in tonight's pool,
    // is an inference channel — and nothing else about participation belongs here either.
    // `role` (E21-01) is static circle governance, not participation, so it is the one
    // exception to that rule.
    assertEquals(keysOf(member), ["display_name", "role", "user_id"]);
  }
  assertEquals(res.body.data.members.map((m: { display_name: string }) => m.display_name), [
    "Ana",
    "Ben",
  ]);
  // The creator is the admin; the joiner is a member — E21-01.
  assertEquals(
    res.body.data.members.map((m: { role: string }) => m.role),
    ["admin", "member"],
  );

  // The joiner sees the same group, and is not its admin.
  const fromBen = await groups("/current", { token: ben.token });
  assertEquals(fromBen.body.data.id, group.id);
  assertEquals(fromBen.body.data.is_admin, false);
});

Deno.test("GET /groups/current is NO_GROUP before joining anything", async () => {
  const user = await newNamedUser("Ana");
  const res = await groups("/current", { token: user.token });
  assertEquals(res.status, 409);
  assertEquals(res.body.error.code, "NO_GROUP");
});

Deno.test("a member of one group sees nothing of another — there is no id to tamper with", async () => {
  const a = await newGroupOwner("Ana");
  const b = await newGroupOwner("Ben");

  // Every group route resolves the group from the caller's membership (ADR-005), so the
  // only thing a member of A can ask for is A. There is no path, query or body parameter
  // anywhere in this function that names a group.
  const seen = await groups("/current", { token: a.user.token });
  assertEquals(seen.body.data.id, a.group.id);
  assert(seen.body.data.id !== b.group.id);
  assertEquals(seen.body.data.members.length, 1);

  // Trying to name one is an unknown key, not a silent override.
  const smuggled = await groups("/current", {
    method: "PATCH",
    token: a.user.token,
    body: { name: "Renamed", group_id: b.group.id },
  });
  assertEquals(smuggled.status, 400);
  assertEquals(smuggled.body.error.details, { field: "group_id" });
  assertEquals((await groups("/current", { token: b.user.token })).body.data.name, "The Cove");
});

// ─── patch ───────────────────────────────────────────────────────────────────

Deno.test("PATCH /groups/current is admin only", async () => {
  const { group } = await newGroupOwner("Ana");
  const ben = await newNamedUser("Ben");
  await groups("/join", {
    method: "POST",
    token: ben.token,
    body: { invite_code: group.invite_code },
  });

  const res = await groups("/current", {
    method: "PATCH",
    token: ben.token,
    body: { name: "Ben's Cove" },
  });
  assertEquals(res.status, 403);
  assertEquals(res.body.error.code, "NOT_ADMIN");
});

Deno.test("PATCH /groups/current changes name and reveal_hour", async () => {
  const { user } = await newGroupOwner("Ana");

  const renamed = await groups("/current", {
    method: "PATCH",
    token: user.token,
    body: { name: "  The Cove II " },
  });
  assertEquals(renamed.status, 200);
  assertEquals(keysOf(renamed.body.data), GROUP_KEYS);
  assertEquals(renamed.body.data.name, "The Cove II");

  const rehoured = await groups("/current", {
    method: "PATCH",
    token: user.token,
    body: { reveal_hour: 18 },
  });
  assertEquals(rehoured.status, 200);
  assertEquals(keysOf(rehoured.body.data), GROUP_KEYS);
  assertEquals(rehoured.body.data.reveal_hour, 18);
  // No round has been materialised for a group this new, so the next one created will use the
  // new hour and there is nothing to wait for. The round-table cases are the two tests below.
  assertEquals(rehoured.body.data.reveal_effective_from, null);
});

// The owner's 2026-09-09 amendment (docs/02 §1): a reveal_hour change re-times every round
// that has not yet opened, and stops at one that has. These two tests are the two sides of
// that line — the round nobody has been able to drop into yet moves, and the round that is
// live does not. `reveal_effective_from` is what the settings screen prints "Starts %@." from,
// and it has exactly one thing left to report: the live round still running on the old hour.

const localDateIn = (timezone: string, at: Date) =>
  new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(at);

const revealsAt = async (token: string) => {
  const res = await call("rounds", "/current", { token });
  assertEquals(res.status, 200);
  return res.body.data.reveals_at as string;
};

Deno.test("a reveal_hour change re-times a round that has not opened yet", async () => {
  // 08:00 local. A 21:00 reveal opens at 11:00, so nothing is open and everything is fair game.
  const timezone = zoneWhereLocalHourIs(8);
  const { user } = await newGroupOwner("Ana", { timezone, reveal_hour: 21 });
  await tickRounds();

  const before = await revealsAt(user.token);

  const moved = await groups("/current", {
    method: "PATCH",
    token: user.token,
    body: { reveal_hour: 18 },
  });
  assertEquals(moved.status, 200);
  assertEquals(
    moved.body.data.reveal_effective_from,
    null,
    "nothing was open, so the new hour is in force tonight and there is no date to wait for",
  );

  const after = await revealsAt(user.token);
  assert(after !== before, "tonight's round did not move, and it should have");
  assertEquals(
    new Date(after).getTime(),
    new Date(before).getTime() - 3 * 3_600_000,
    "21:00 to 18:00 is three hours earlier, tonight",
  );
});

Deno.test("a reveal_hour change never re-times a round that is already open", async () => {
  // 14:00 local. A 21:00 reveal opened at 11:00 — three hours ago — and reveals in seven.
  const timezone = zoneWhereLocalHourIs(14);
  const { user } = await newGroupOwner("Ana", { timezone, reveal_hour: 21 });
  await tickRounds();

  const tonight = await revealsAt(user.token);

  const settled = await groups("/current", { token: user.token });
  assertEquals(settled.status, 200);
  assertEquals(
    settled.body.data.reveal_effective_from,
    null,
    "an unchanged hour is already in force",
  );

  const moved = await groups("/current", {
    method: "PATCH",
    token: user.token,
    body: { reveal_hour: 18 },
  });
  assertEquals(moved.status, 200);

  assertEquals(
    await revealsAt(user.token),
    tonight,
    "tonight's round is open and somebody may have sealed against its clock",
  );

  // So the change lands tomorrow — the next round, not the one after it, which is what an
  // admin waiting two nights used to be told.
  const tomorrow = localDateIn(timezone, new Date(Date.now() + 24 * 3_600_000));
  assertEquals(moved.body.data.reveal_effective_from, tomorrow);

  // And it keeps saying so on an ordinary read, which is the whole point of the field: the
  // date used to exist only in the reply to the change, and the screen forgot it on reopen.
  const reread = await groups("/current", { token: user.token });
  assertEquals(reread.body.data.reveal_effective_from, tomorrow);

  // Put it back and the answer goes away: the open round is on 21:00 and so is everything else.
  const restored = await groups("/current", {
    method: "PATCH",
    token: user.token,
    body: { reveal_hour: 21 },
  });
  assertEquals(restored.status, 200);
  assertEquals(restored.body.data.reveal_effective_from, null);
  assertEquals(await revealsAt(user.token), tonight, "and tonight never moved through any of it");
});

Deno.test("PATCH /groups/current changes the cue cadence and names the effective date", async () => {
  const { user, group } = await newGroupOwner("Ana");

  const res = await groups("/current", {
    method: "PATCH",
    token: user.token,
    body: { cue_cadence: 1 },
  });
  assertEquals(res.status, 200);
  assertEquals(res.body.data.cue_cadence, 1);
  assertEquals(typeof res.body.data.cue_effective_from, "string");

  // Admin-only, the same guard reveal_hour gets (docs/18-CUES.md §4).
  const ben = await newMember(group.invite_code as string, "Ben");
  const refused = await groups("/current", {
    method: "PATCH",
    token: ben.token,
    body: { cue_cadence: 3 },
  });
  assertEquals(refused.status, 403);
  assertEquals(refused.body.error.code, "NOT_ADMIN");
});

// ─── the next round's cue — E43-02, docs/18-CUES.md §11.6 ────────────────────
//
// A circle whose local hour is 02:00 with the default 20:00 reveal has today's round opening at
// 10:00 local — eight hours out — so there is always exactly one editable round in these tests,
// and it is today's, not tomorrow's. That is the dark-hours case, and it is why nothing in this
// feature is labelled "tomorrow".
async function circleWithAnEditableRound(cadence = 1) {
  const owner = await newGroupOwner("Ana", {
    timezone: zoneWhereLocalHourIs(2),
    reveal_hour: 20,
    cue_cadence: cadence,
  });
  await tickRounds();
  return owner;
}

Deno.test("GET /groups/current carries next_cue for an admin and not for a member", async () => {
  const { user, group } = await circleWithAnEditableRound();

  const mine = await groups("/current", { token: user.token });
  assertEquals(mine.status, 200);
  const next = mine.body.data.next_cue as Record<string, unknown>;
  assert(next, "an admin is told what the next round's cue is");
  assertEquals(keysOf(next), ["editable_until", "is_custom", "local_date", "text"]);
  assertEquals(next.is_custom, false, "and that nobody has written it by hand");
  assertEquals(typeof next.text, "string", "cadence 1 cues every night");

  // Absent, not null. docs/18-CUES.md §7 argues that handing out the *coming* night's cue early
  // is wrong — it is why the dark hours render `previous_cue` instead — so a member never sees
  // this key at all.
  const ben = await newMember(group.invite_code as string, "Ben");
  const theirs = await groups("/current", { token: ben.token });
  assertEquals(theirs.status, 200);
  assert(!("next_cue" in theirs.body.data), "a member is not told tomorrow's brief today");
});

Deno.test("PUT /groups/current/cue writes the admin's own line onto the next round", async () => {
  const { user, group } = await circleWithAnEditableRound();

  const res = await groups("/current/cue", {
    method: "PUT",
    token: user.token,
    body: { text: "  Your lock tf in song  " },
  });
  assertEquals(res.status, 200);
  const next = res.body.data.next_cue as Record<string, unknown>;
  assertEquals(next.text, "Your lock tf in song", "trimmed, and exactly what was typed");
  assertEquals(next.is_custom, true);

  // It is on the round, not just in the reply to the write: the next read agrees.
  const reread = await groups("/current", { token: user.token });
  assertEquals((reread.body.data.next_cue as Record<string, unknown>).text, "Your lock tf in song");

  const ben = await newMember(group.invite_code as string, "Ben");
  const refused = await groups("/current/cue", {
    method: "PUT",
    token: ben.token,
    body: { text: "Not yours to write" },
  });
  assertEquals(refused.status, 403);
  assertEquals(refused.body.error.code, "NOT_ADMIN");
});

Deno.test("PUT /groups/current/cue holds the line to the catalog's own length bar", async () => {
  const { user } = await circleWithAnEditableRound();

  for (const text of ["", "   ", "x".repeat(57)]) {
    const res = await groups("/current/cue", { method: "PUT", token: user.token, body: { text } });
    assertEquals(res.status, 400, `refused: ${JSON.stringify(text)}`);
    assertEquals(res.body.error.code, "INVALID_INPUT");
  }

  // 56 is `cue_catalog.text`'s own check constraint — what keeps a line from overflowing on an
  // SE at accessibility5 (docs/18-CUES.md §6). A hand-written cue is held to the same bar.
  const ok56 = await groups("/current/cue", {
    method: "PUT",
    token: user.token,
    body: { text: "x".repeat(56) },
  });
  assertEquals(ok56.status, 200);

  // And the bar is measured *after* the trim, the same order `set_round_cue()` uses and the
  // same string the client's "N left" counter counts. A 56-character line that arrives with a
  // trailing space is 57 raw characters and still valid.
  const padded = await groups("/current/cue", {
    method: "PUT",
    token: user.token,
    body: { text: `  ${"y".repeat(56)}  ` },
  });
  assertEquals(padded.status, 200);
  assertEquals((padded.body.data.next_cue as Record<string, unknown>).text, "y".repeat(56));
});

Deno.test("a hand-set cue survives a cadence change, and DELETE puts the derivation back", async () => {
  const { user } = await circleWithAnEditableRound();

  const before = await groups("/current", { token: user.token });
  const derived = (before.body.data.next_cue as Record<string, unknown>).text;

  await groups("/current/cue", {
    method: "PUT",
    token: user.token,
    body: { text: "A song you hate" },
  });

  // The load-bearing one. A cadence change rewrites the cue on exactly the rounds this feature
  // edits, and without `not prompt_custom` in `rewrite_open_round_cues()` the admin's line would
  // vanish the moment they touched the cadence picker.
  const patched = await groups("/current", {
    method: "PATCH",
    token: user.token,
    body: { cue_cadence: 1 },
  });
  assertEquals(patched.status, 200);
  assertEquals((patched.body.data.next_cue as Record<string, unknown>).text, "A song you hate");

  const cleared = await groups("/current/cue", { method: "DELETE", token: user.token });
  assertEquals(cleared.status, 200);
  const after = cleared.body.data.next_cue as Record<string, unknown>;
  assertEquals(after.is_custom, false);
  assertEquals(after.text, derived, "back to exactly the line the sequence would have given");
});

Deno.test("the cue can be set on a night the cadence gives no cue", async () => {
  const { user } = await circleWithAnEditableRound(0);

  const off = await groups("/current", { token: user.token });
  assertEquals((off.body.data.next_cue as Record<string, unknown>).text, null, "cadence 0, no cue");

  const res = await groups("/current/cue", {
    method: "PUT",
    token: user.token,
    body: { text: "A song for your current mood" },
  });
  assertEquals(res.status, 200);
  assertEquals((res.body.data.next_cue as Record<string, unknown>).text, "A song for your current mood");

  // And clearing it on an uncued night is correctly *no cue*, not a failure.
  const cleared = await groups("/current/cue", { method: "DELETE", token: user.token });
  assertEquals((cleared.body.data.next_cue as Record<string, unknown>).text, null);
});

Deno.test("PATCH /groups/current refuses to change the timezone", async () => {
  const { user } = await newGroupOwner("Ana");
  const res = await groups("/current", {
    method: "PATCH",
    token: user.token,
    body: { timezone: "Europe/Paris" },
  });
  assertEquals(res.status, 400);
  assertEquals(res.body.error.details, { field: "timezone" });
  assertEquals(
    (await groups("/current", { token: user.token })).body.data.timezone,
    "America/New_York",
  );
});

Deno.test("PATCH /groups/current with nothing to change is INVALID_INPUT", async () => {
  const { user } = await newGroupOwner("Ana");
  const res = await groups("/current", { method: "PATCH", token: user.token, body: {} });
  assertEquals(res.status, 400);
  assertEquals(res.body.error.code, "INVALID_INPUT");
});

// ─── leave ───────────────────────────────────────────────────────────────────

Deno.test("POST /groups/current/leave is a 204, and the live token then gets NO_GROUP", async () => {
  const { user, group } = await newGroupOwner("Ana");
  const ben = await newNamedUser("Ben");
  await groups("/join", {
    method: "POST",
    token: ben.token,
    body: { invite_code: group.invite_code },
  });

  const left = await groups("/current/leave", { method: "POST", token: ben.token });
  assertEquals(left.status, 204);
  assertEquals(left.body, null);

  // docs/14 §5: membership is resolved per request, so the ex-member's still-valid token
  // stops working immediately rather than at token expiry.
  const after = await groups("/current", { token: ben.token });
  assertEquals(after.status, 409);
  assertEquals(after.body.error.code, "NO_GROUP");

  // And the group carries on without them.
  const remaining = await groups("/current", { token: user.token });
  assertEquals(remaining.body.data.members, [{ user_id: user.id, display_name: "Ana", role: "admin" }]);
});

Deno.test("the sole admin cannot leave while other active members remain — E21-01", async () => {
  const { user: owner, group } = await newGroupOwner("Ana");
  const ben = await newNamedUser("Ben");
  await groups("/join", {
    method: "POST",
    token: ben.token,
    body: { invite_code: group.invite_code },
  });

  const res = await groups("/current/leave", { method: "POST", token: owner.token });
  assertEquals(res.status, 409);
  assertEquals(res.body.error.code, "LAST_ADMIN_MUST_TRANSFER");

  // Refused, not partially applied: the admin's membership is still active.
  const still = await groups("/current", { token: owner.token });
  assertEquals(still.body.data.id, group.id);
  assertEquals(still.body.data.is_admin, true);
});

Deno.test("a sole admin with no other active members may still leave — E21-01", async () => {
  const { user } = await newGroupOwner("Ana");

  const res = await groups("/current/leave", { method: "POST", token: user.token });
  assertEquals(res.status, 204);

  const after = await groups("/current", { token: user.token });
  assertEquals(after.status, 409);
  assertEquals(after.body.error.code, "NO_GROUP");
});

// ─── roles — E21-02 ─────────────────────────────────────────────────────────

Deno.test("an admin can promote and demote an active member — E21-02", async () => {
  const { user: ana, group } = await newGroupOwner("Ana");
  const ben = await newMember(String(group.invite_code), "Ben");

  const promoted = await groups(`/${group.id}/members/${ben.id}`, {
    method: "PATCH",
    token: ana.token,
    body: { role: "admin" },
  });
  assertEquals(promoted.status, 200);
  assertEquals(promoted.body.data.members.map((m: { role: string }) => m.role), ["admin", "admin"]);

  const demoted = await groups(`/${group.id}/members/${ana.id}`, {
    method: "PATCH",
    token: ana.token,
    body: { role: "member" },
  });
  assertEquals(demoted.status, 200);
  assertEquals(demoted.body.data.is_admin, false);
  assertEquals(demoted.body.data.members.map((m: { role: string }) => m.role), ["member", "admin"]);
});

Deno.test("role changes and removals are admin-only and scoped to an active member — E21-02", async () => {
  const { user: ana, group } = await newGroupOwner("Ana");
  const ben = await newMember(String(group.invite_code), "Ben");
  const cara = await newNamedUser("Cara");

  const denied = await groups(`/${group.id}/members/${ana.id}`, {
    method: "PATCH",
    token: ben.token,
    body: { role: "member" },
  });
  assertEquals(denied.status, 403);
  assertEquals(denied.body.error.code, "NOT_ADMIN");

  const outside = await groups(`/${group.id}/members/${cara.id}`, {
    method: "DELETE",
    token: ana.token,
  });
  assertEquals(outside.status, 404);
  assertEquals(outside.body.error.code, "NOT_FOUND");

  const invalid = await groups(`/${group.id}/members/${ben.id}`, {
    method: "PATCH",
    token: ana.token,
    body: { role: "owner" },
  });
  assertEquals(invalid.status, 400);
  assertEquals(invalid.body.error.details, { field: "role" });
});

Deno.test("the last admin cannot demote or remove themselves while members remain — E21-02", async () => {
  const { user: ana, group } = await newGroupOwner("Ana");
  await newMember(String(group.invite_code), "Ben");

  const demoted = await groups(`/${group.id}/members/${ana.id}`, {
    method: "PATCH",
    token: ana.token,
    body: { role: "member" },
  });
  assertEquals(demoted.status, 409);
  assertEquals(demoted.body.error.code, "LAST_ADMIN_MUST_TRANSFER");

  const removed = await groups(`/${group.id}/members/${ana.id}`, {
    method: "DELETE",
    token: ana.token,
  });
  assertEquals(removed.status, 409);
  assertEquals(removed.body.error.code, "LAST_ADMIN_MUST_TRANSFER");
});

Deno.test("an admin can remove another member without rewriting the active roster — E21-02", async () => {
  const { user: ana, group } = await newGroupOwner("Ana");
  const ben = await newMember(String(group.invite_code), "Ben");

  const removed = await groups(`/${group.id}/members/${ben.id}`, { method: "DELETE", token: ana.token });
  assertEquals(removed.status, 204);

  const roster = await groups(`/${group.id}`, { token: ana.token });
  assertEquals(roster.status, 200);
  assertEquals(roster.body.data.members, [{ user_id: ana.id, display_name: "Ana", role: "admin" }]);
  const fromBen = await groups(`/${group.id}`, { token: ben.token });
  assertEquals(fromBen.status, 404);
  assertEquals(fromBen.body.error.code, "NOT_FOUND");
});

Deno.test("leaving frees the one-group rule, and rejoining is allowed", async () => {
  const { group } = await newGroupOwner("Ana");
  const ben = await newNamedUser("Ben");

  await groups("/join", {
    method: "POST",
    token: ben.token,
    body: { invite_code: group.invite_code },
  });
  await groups("/current/leave", { method: "POST", token: ben.token });

  const rejoined = await groups("/join", {
    method: "POST",
    token: ben.token,
    body: { invite_code: group.invite_code },
  });
  assertEquals(rejoined.status, 200);
  assertEquals(rejoined.body.data.id, group.id);
});

Deno.test("every group route is 401 for an anonymous caller", async () => {
  const calls: [string, string][] = [
    ["POST", "/"],
    ["POST", "/join"],
    ["GET", "/current"],
    ["PATCH", "/current"],
    ["POST", "/current/leave"],
  ];
  for (const [method, path] of calls) {
    const res = await groups(path, { method, body: {} });
    assertEquals(res.status, 401, `${method} ${path}`);
    assertEquals(res.body.error.code, "UNAUTHENTICATED");
  }
});

// ─── reports — E45-01 ───────────────────────────────────────────────────────

Deno.test("any member can report any other member, and repeats are idempotent — E45-01", async () => {
  const { user: ana, group } = await newGroupOwner("Ana");
  const ben = await newMember(String(group.invite_code), "Ben");

  // The point of the slice: Ben is not an admin, and does not need to be.
  const reported = await groups(`/${group.id}/members/${ana.id}/report`, {
    method: "POST",
    token: ben.token,
    body: { reason: "display_name" },
  });
  assertEquals(reported.status, 204);

  // A second tap within the day is the same report, and is success rather than a failure the
  // reporter cannot act on.
  const again = await groups(`/${group.id}/members/${ana.id}/report`, {
    method: "POST",
    token: ben.token,
    body: { reason: "harassment" },
  });
  assertEquals(again.status, 204);
});

Deno.test("a report refuses itself, a stranger, an outsider and a reason off the list — E45-01", async () => {
  const { user: ana, group } = await newGroupOwner("Ana");
  const ben = await newMember(String(group.invite_code), "Ben");
  const cara = await newNamedUser("Cara");

  const itself = await groups(`/${group.id}/members/${ana.id}/report`, {
    method: "POST",
    token: ana.token,
    body: { reason: "other" },
  });
  assertEquals(itself.status, 400);
  assertEquals(itself.body.error.details, { field: "user_id" });

  const outsider = await groups(`/${group.id}/members/${cara.id}/report`, {
    method: "POST",
    token: ana.token,
    body: { reason: "other" },
  });
  assertEquals(outsider.status, 404);
  assertEquals(outsider.body.error.code, "NOT_FOUND");

  // Cara is not in this circle, so she cannot raise anybody in it — and the refusal is 404
  // rather than 403, which is the right one: a circle she does not hold should not be confirmed
  // to exist by the shape of its own rejection.
  const byOutsider = await groups(`/${group.id}/members/${ben.id}/report`, {
    method: "POST",
    token: cara.token,
    body: { reason: "other" },
  });
  assertEquals(byOutsider.status, 404);

  const badReason = await groups(`/${group.id}/members/${ben.id}/report`, {
    method: "POST",
    token: ana.token,
    body: { reason: "vibes" },
  });
  assertEquals(badReason.status, 400);
  assertEquals(badReason.body.error.details, { field: "reason" });
});
