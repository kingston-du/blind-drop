// groups.test.ts — tasks/E02-03. docs/04 §3, docs/02 §1, docs/14 §3, §4.

import { assert, assertEquals } from "jsr:@std/assert@1";
import { call, keysOf, newGroupOwner, newMember, newNamedUser, newUser } from "./_harness.ts";

const groups = (path: string, opts: Parameters<typeof call>[2] = {}) => call("groups", path, opts);

const GROUP_KEYS = ["id", "invite_code", "is_admin", "members", "name", "reveal_hour", "timezone"];

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

Deno.test("PATCH /groups/current changes name and reveal_hour, and echoes effective_from", async () => {
  const { user, group } = await newGroupOwner("Ana");

  const renamed = await groups("/current", {
    method: "PATCH",
    token: user.token,
    body: { name: "  The Cove II " },
  });
  assertEquals(renamed.status, 200);
  assertEquals(renamed.body.data.name, "The Cove II");
  // Renaming takes effect at once, so there is no date to wait for.
  assertEquals(renamed.body.data.effective_from, null);

  const rehoured = await groups("/current", {
    method: "PATCH",
    token: user.token,
    body: { reveal_hour: 18 },
  });
  assertEquals(rehoured.status, 200);
  assertEquals(keysOf(rehoured.body.data), [...GROUP_KEYS, "effective_from"].sort());
  assertEquals(rehoured.body.data.reveal_hour, 18);
  // No rounds exist for a group this new, so the change lands on the next round created —
  // today's, in the group's own timezone (docs/02 §1).
  const today = new Intl.DateTimeFormat("en-CA", {
    timeZone: String(group.timezone),
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
  assertEquals(rehoured.body.data.effective_from, today);
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
