// circles.test.ts — tasks/E18-01, ADR-011. docs/04 §3, §4, docs/14 §4.
//
// Two things this lifts from ADR-005 and has to prove itself: a user may hold more than one
// active circle up to the cap, and every route that now takes a `group_id` proves membership
// of it rather than getting authorization for free the way `requireMembership()` used to.

import { assert, assertEquals } from "jsr:@std/assert@1";
import { call, keysOf, newGroupOwner, newNamedUser, zoneWhereLocalHourIs } from "./_harness.ts";

const groups = (path: string, opts: Parameters<typeof call>[2] = {}) => call("groups", path, opts);
const rounds = (path: string, opts: Parameters<typeof call>[2] = {}) => call("rounds", path, opts);

const FABRICATED_UUID = "c0000000-0000-4000-8000-0000000000fe";

let ownerCount = 0;

/** A group with a fresh owner. `groupName` may be long and descriptive (max 40); the owner's
 *  own display name is generated separately, since `profiles.display_name` caps at 24. */
function freshGroup(groupName: string) {
  ownerCount += 1;
  return newGroupOwner(`Owner ${ownerCount}`, { name: groupName, timezone: zoneWhereLocalHourIs(12) });
}

// ─── the cap ─────────────────────────────────────────────────────────────────

Deno.test("a user may hold several circles, up to ADR-011's cap", async () => {
  const user = await newNamedUser("Ana");

  const first = await groups("/", {
    method: "POST",
    token: user.token,
    body: { name: "Circle one", timezone: "UTC" },
  });
  assertEquals(first.status, 200, "ADR-005 would have refused this; ADR-011 does not");

  const second = await groups("/", {
    method: "POST",
    token: user.token,
    body: { name: "Circle two", timezone: "UTC" },
  });
  assertEquals(second.status, 200, "a second active circle is allowed");

  const third = await groups("/", {
    method: "POST",
    token: user.token,
    body: { name: "Circle three", timezone: "UTC" },
  });
  assertEquals(third.status, 200, "a third active circle is allowed — the cap is three");

  const fourth = await groups("/", {
    method: "POST",
    token: user.token,
    body: { name: "Circle four", timezone: "UTC" },
  });
  assertEquals(fourth.status, 409);
  assertEquals(fourth.body.error.code, "CIRCLE_LIMIT_REACHED");
  assertEquals(keysOf(fourth.body.error), ["code", "message"], "the cap carries no other detail");
});

Deno.test("POST /groups/join refuses a fourth circle with the same named error", async () => {
  const joiner = await newNamedUser("Ben");
  for (let i = 0; i < 3; i += 1) {
    const owned = await groups("/", {
      method: "POST",
      token: joiner.token,
      body: { name: `Ben's circle ${i}`, timezone: "UTC" },
    });
    assertEquals(owned.status, 200);
  }

  const { group: fourthGroup } = await freshGroup("A fourth circle, somebody else's");
  const joined = await groups("/join", {
    method: "POST",
    token: joiner.token,
    body: { invite_code: fourthGroup.invite_code },
  });
  assertEquals(joined.status, 409);
  assertEquals(joined.body.error.code, "CIRCLE_LIMIT_REACHED");
});

// ─── the named-group routes ──────────────────────────────────────────────────

Deno.test("GET /groups/{group_id} answers the same as GET /groups/current, for a member", async () => {
  const { user, group } = await freshGroup("Named-route parity");

  const byCurrent = await groups("/current", { token: user.token });
  const byId = await groups(`/${group.id}`, { token: user.token });

  assertEquals(byId.status, 200);
  assertEquals(byId.body.data, byCurrent.body.data);
});

Deno.test(
  "a member of one circle asking for another's data gets the same NOT_FOUND a stranger would",
  async () => {
    const { user: outsider } = await freshGroup("Outsider's own circle");
    const { group: theirs } = await freshGroup("Somebody else's circle");

    const routes = [
      () => groups(`/${theirs.id}`, { token: outsider.token }),
      () =>
        groups(`/${theirs.id}`, {
          method: "PATCH",
          token: outsider.token,
          body: { name: "Renamed" },
        }),
      () => groups(`/${theirs.id}/standings`, { token: outsider.token }),
      () => groups(`/${theirs.id}/record`, { token: outsider.token }),
      () => groups(`/${theirs.id}/record/export?service=apple`, { token: outsider.token }),
      () => groups(`/${theirs.id}/leave`, { method: "POST", token: outsider.token }),
      () => rounds(`/${theirs.id}/current`, { token: outsider.token }),
      () =>
        rounds(`/${theirs.id}/current/submission`, {
          method: "PUT",
          token: outsider.token,
          body: { apple_music_id: "1440818664" },
        }),
      () =>
        rounds(`/${theirs.id}/current/guesses`, {
          method: "PUT",
          token: outsider.token,
          body: { assignments: [] },
        }),
    ];

    for (const request of routes) {
      const asOutsider = await request();
      assertEquals(asOutsider.status, 404, JSON.stringify(asOutsider.body));
      assertEquals(asOutsider.body.error.code, "NOT_FOUND");
    }
  },
);

Deno.test(
  "a real circle the caller does not belong to and a fabricated id are byte-identical",
  async () => {
    const { user: outsider } = await freshGroup("Outsider's own circle, again");
    const { group: theirs } = await freshGroup("The real one nobody outside can see");
    const theirsId = theirs.id as string;

    for (
      const path of [
        `/${theirsId}`,
        `/${theirsId}/standings`,
        `/${theirsId}/record`,
      ]
    ) {
      const real = await groups(path, { token: outsider.token });
      const fake = await groups(path.replace(theirsId, FABRICATED_UUID), {
        token: outsider.token,
      });
      assertEquals(real.status, fake.status, path);
      assertEquals(real.body.error, fake.body.error, `${path}: no existence oracle`);
    }

    const realRound = await rounds(`/${theirsId}/current`, { token: outsider.token });
    const fakeRound = await rounds(`/${FABRICATED_UUID}/current`, { token: outsider.token });
    assertEquals(realRound.body.error, fakeRound.body.error);
  },
);

Deno.test("a malformed group id is the same NOT_FOUND as a real one the caller cannot see", async () => {
  const { user: outsider } = await freshGroup("Malformed-id prober");

  const malformed = await groups("/not-a-uuid", { token: outsider.token });
  assertEquals(malformed.status, 404);
  assertEquals(malformed.body.error.code, "NOT_FOUND");
});

// ─── leave stays scoped to the one circle ────────────────────────────────────

Deno.test("leaving one circle does not end membership in another", async () => {
  const user = await newNamedUser("Ana");
  const a = (await groups("/", { method: "POST", token: user.token, body: { name: "A", timezone: "UTC" } }))
    .body.data;
  const b = (await groups("/", { method: "POST", token: user.token, body: { name: "B", timezone: "UTC" } }))
    .body.data;

  const left = await groups(`/${a.id}/leave`, { method: "POST", token: user.token });
  assertEquals(left.status, 204);

  const stillA = await groups(`/${a.id}`, { token: user.token });
  assertEquals(stillA.status, 404, "left circle A — no longer a member");

  const stillB = await groups(`/${b.id}`, { token: user.token });
  assertEquals(stillB.status, 200, "circle B is untouched by leaving A");
  assert(stillB.body.data.name === "B");
});

// ─── the `current` compatibility alias ───────────────────────────────────────

Deno.test("GET /groups/current resolves to the caller's oldest active circle", async () => {
  const user = await newNamedUser("Ana");
  const first = (
    await groups("/", { method: "POST", token: user.token, body: { name: "First", timezone: "UTC" } })
  ).body.data;
  await groups("/", { method: "POST", token: user.token, body: { name: "Second", timezone: "UTC" } });

  const current = await groups("/current", { token: user.token });
  assertEquals(current.body.data.id, first.id, "the oldest membership wins, not the most recent");
});
