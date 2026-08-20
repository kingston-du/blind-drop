// postgrest_locked.test.ts — the second lock, checked from outside. tasks/E04-04, AC-1.
//
// `0003_rls.sql` turns on deny-by-default RLS and revokes every privilege from `anon` and
// `authenticated`, and `tests/db/rls.sql` proves that in SQL. This file proves the same thing
// through the door an attacker would actually use: PostgREST, on the public API port, with a
// real access token belonging to a real member of a real group who genuinely has a submission
// in tonight's round.
//
// That distinction is the reason this exists as well as the pgTAP test. A `select` denied in
// psql is a fact about the database; a `select` denied over HTTPS with a valid JWT is a fact
// about the product. docs/01 §2 keeps `public` exposed in `config.toml` precisely so this
// surface is the same one production has.

import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  ANON_KEY,
  API_URL,
  call,
  newGroupOwner,
  newMember,
  zoneWhereLocalHourIs,
} from "./_harness.ts";

/** Every table in docs/03 §2. Kept explicit so adding a table requires a human to add it to
 *  this release-critical denial audit too. */
const TABLES = [
  "profiles",
  "groups",
  "memberships",
  "rounds",
  "submissions",
  "guesses",
  "devices",
  "notification_outbox",
  "track_links",
  "rate_limit_events",
  "invitations",
] as const;

async function restGet(table: string, token: string, query = "select=*"): Promise<Response> {
  return await fetch(`${API_URL}/rest/v1/${table}?${query}`, {
    headers: { apikey: ANON_KEY, authorization: `Bearer ${token}` },
  });
}

Deno.test("an authenticated PostgREST select on every table fails with 42501", async () => {
  // Not a bystander: a named member of a group, with a song sealed in tonight's round. If any
  // policy were to leak, this is the token it would leak to.
  const { user } = await newGroupOwner("Ana", {
    name: "Lockdown",
    timezone: zoneWhereLocalHourIs(12),
    reveal_hour: 20,
  });
  await call("rounds", "/current/submission", {
    method: "PUT",
    token: user.token,
    body: { apple_music_id: "1440818664" },
  });

  for (const table of TABLES) {
    const res = await restGet(table, user.token);
    const text = await res.text();

    assert(!res.ok, `PostgREST returned ${res.status} from ${table}: ${text}`);
    assertEquals(JSON.parse(text).code, "42501", `${table}: ${text}`);
  }
});

Deno.test("an anonymous PostgREST select on every table fails with 42501", async () => {
  for (const table of TABLES) {
    const res = await fetch(`${API_URL}/rest/v1/${table}?select=*`, {
      headers: { apikey: ANON_KEY },
    });
    const text = await res.text();
    assert(!res.ok, `PostgREST returned ${res.status} from ${table}: ${text}`);
    assertEquals(JSON.parse(text).code, "42501", `${table}: ${text}`);
  }
});

Deno.test("PostgREST will not write either", async () => {
  const { user } = await newGroupOwner("Ana", {
    name: "Lockdown Writes",
    timezone: zoneWhereLocalHourIs(12),
    reveal_hour: 20,
  });

  // The one that would matter: forging a submission into a round, bypassing every phase check
  // in the handler.
  const res = await fetch(`${API_URL}/rest/v1/submissions`, {
    method: "POST",
    headers: {
      apikey: ANON_KEY,
      authorization: `Bearer ${user.token}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      round_id: crypto.randomUUID(),
      user_id: user.id,
      track_key: "x",
      track_meta: {},
    }),
  });
  await res.body?.cancel();
  assert(!res.ok, `PostgREST accepted a forged submission (${res.status})`);
});

Deno.test("no RPC in the public schema is callable by a client", async () => {
  const { user } = await newGroupOwner("Ana", {
    name: "Lockdown RPC",
    timezone: zoneWhereLocalHourIs(12),
    reveal_hour: 20,
  });

  // The functions a client would most like to reach: one that creates rounds, one that moves
  // them, and the two that write submissions. All are `service_role`-only by explicit grant.
  for (
    const fn of ["ensure_rounds", "tick_rounds", "upsert_submission", "patch_track_meta_spotify"]
  ) {
    for (const token of [ANON_KEY, user.token]) {
      const res = await fetch(`${API_URL}/rest/v1/rpc/${fn}`, {
        method: "POST",
        headers: {
          apikey: ANON_KEY,
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
        body: "{}",
      });
      await res.body?.cancel();
      assert(!res.ok, `${fn} was callable by a client (${res.status})`);
    }
  }
});

Deno.test("every Edge Function refuses an anonymous caller with our envelope", async () => {
  // docs/04 §1: `verify_jwt = false` moves the gate into our code so the body is one the
  // client can switch on. If the platform were answering instead, `error.code` would be
  // missing and every client error path would break at once.
  const routes: [string, string, string][] = [
    ["me", "/", "GET"],
    ["me", "/", "PUT"],
    ["groups", "/current", "GET"],
    ["groups", "/", "POST"],
    ["groups", "/join", "POST"],
    ["rounds", "/current", "GET"],
    ["rounds", "/current/submission", "PUT"],
    ["tracks", "/search?q=Ribs", "GET"],
    ["tracks", "/resolve", "POST"],
  ];

  for (const [fn, path, method] of routes) {
    const res = await call(fn, path, { method, body: {} });
    assertEquals(res.status, 401, `${method} ${fn}${path}`);
    assertEquals(res.body.error.code, "UNAUTHENTICATED", `${method} ${fn}${path}`);
    assert(typeof res.body.server_now === "string");
  }
});

Deno.test("there is no route that takes a resource id from the client", async () => {
  // ADR-005 and docs/04 §7: the group comes from the caller's membership, never from the
  // request, so there is no id to tamper with and nothing to fuzz. This asserts the absence
  // rather than trusting it — a route added later that *does* take an id will start
  // answering something other than 404 here and fail.
  const a = await newGroupOwner("Ana", {
    name: "Group A",
    timezone: zoneWhereLocalHourIs(12),
    reveal_hour: 20,
  });
  const b = await newGroupOwner("Ben", {
    name: "Group B",
    timezone: zoneWhereLocalHourIs(12),
    reveal_hour: 20,
  });
  await call("rounds", "/current/submission", {
    method: "PUT",
    token: b.user.token,
    body: { apple_music_id: "1440765580" },
  });
  const bRound = (await call("rounds", "/current", { token: b.user.token })).body.data;

  // Real ids belonging to a real other group, in every shape a route could plausibly take.
  const foreign = [b.group.id as string, bRound.round_id as string, b.user.id];
  const paths = foreign.flatMap((
    id,
  ) => [`/${id}`, `/current/${id}`, `/${id}/results`, `/${id}/submission`]);

  // Percent-encoded separators and a repeated function name, which are the two shapes that
  // survive the URL parser and actually reach `routePath`. A literal `/../` is *not* in this
  // list on purpose: `new URL` resolves it before a byte leaves the client, so testing it
  // would only be testing the URL spec.
  const fuzz = [
    "/current%2F..%2Fcurrent",
    "/current/..%2f..%2fgroups/current",
    "/current/rounds/current",
    "/current//current",
    "/CURRENT",
  ];

  for (const path of [...paths, ...fuzz]) {
    for (const fn of ["rounds", "groups"]) {
      const res = await call(fn, path, { token: a.user.token });
      assertEquals(res.status, 404, `${fn}${path} answered ${res.status}`);
      assert(
        !JSON.stringify(res.body).includes("Nights"),
        `${fn}${path} leaked another group's submission`,
      );
    }
  }
});

Deno.test("a path that resolves onto a real route still only ever sees the caller's own group", async () => {
  // `GET /functions/v1/rounds/current/../../groups/current` is normalised by the URL parser
  // into `GET /functions/v1/groups/current` before it is sent, so it does reach a handler and
  // does answer 200. That is not a traversal bug and there is nothing to fix: the route it
  // lands on resolves the group from the caller's own membership like every other one
  // (ADR-005). Asserted rather than argued.
  const a = await newGroupOwner("Ana", {
    name: "Group A Normalised",
    timezone: zoneWhereLocalHourIs(12),
    reveal_hour: 20,
  });
  const b = await newGroupOwner("Ben", {
    name: "Group B Normalised",
    timezone: zoneWhereLocalHourIs(12),
    reveal_hour: 20,
  });

  const res = await call("rounds", "/current/../../groups/current", { token: a.user.token });
  assertEquals(res.status, 200);
  assertEquals(res.body.data.id, a.group.id, "it answered with the caller's own group");
  assert(res.body.data.id !== b.group.id);
});

Deno.test("an ex-member's still-valid token gets NO_GROUP", async () => {
  const { user, group } = await newGroupOwner("Ana", {
    name: "Ex Member",
    timezone: zoneWhereLocalHourIs(12),
    reveal_hour: 20,
  });
  const ben = await newMember(group.invite_code as string, "Ben");
  await call("rounds", "/current/submission", {
    method: "PUT",
    token: ben.token,
    body: { apple_music_id: "1440765580" },
  });

  await call("groups", "/current/leave", { method: "POST", token: ben.token });

  // The token is untouched and still valid — docs/14 §5 is about what a *valid* token can
  // reach after the membership behind it ends.
  for (const [fn, path] of [["rounds", "/current"], ["groups", "/current"]] as const) {
    const res = await call(fn, path, { token: ben.token });
    assertEquals(res.status, 409, `${fn}${path}`);
    assertEquals(res.body.error.code, "NO_GROUP");
    assert(!JSON.stringify(res.body).includes("Nights"), "and it carries nothing from the group");
  }
});
