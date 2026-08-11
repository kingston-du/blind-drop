// shared.test.ts — tasks/E02-01. The envelope, the guards, and the parse step.
//
// These tests reach into `_shared` directly rather than through a handler, because what is
// being asserted is the spine itself: if `fail()` can be talked into carrying an extra key,
// no amount of handler testing will find it.

import { assert, assertEquals, assertRejects, assertThrows } from "jsr:@std/assert@1";

import {
  ApiError,
  type ErrorCode,
  errorSpec,
  fail,
  int,
  noContent,
  ok,
  optional,
  parseBody,
  routePath,
  str,
} from "../../functions/_shared/http.ts";
import {
  enforceRateLimit,
  type MemberCtx,
  requireAdmin,
  requireJoinedBefore,
  requireMembership,
  requirePhase,
  requireProfile,
  requireUser,
} from "../../functions/_shared/auth.ts";
import { serviceClient } from "../../functions/_shared/db.ts";
import { hasPassed, localDate, nextDate, rfc3339 } from "../../functions/_shared/time.ts";
import { isRfc3339Z, keysOf, mintToken, newUser } from "./_harness.ts";

const ALL_CODES: ErrorCode[] = [
  "UNAUTHENTICATED",
  "NO_PROFILE",
  "NO_GROUP",
  "NOT_FOUND",
  "WRONG_PHASE",
  "NOT_A_SUBMITTER",
  "JOINED_LATE",
  "ROUND_VOIDED",
  "INVALID_INPUT",
  "ALREADY_IN_GROUP",
  "NOT_ADMIN",
  "RATE_LIMITED",
  "UPSTREAM_UNAVAILABLE",
  "INTERNAL",
];

const ANA = "a0000000-0000-4000-8000-000000000001"; // seed.sql, in The Cove
const bodyOf = (res: Response) => res.json();

// ─── the envelope — docs/04 §1 ───────────────────────────────────────────────

Deno.test("ok() is { server_now, data } and nothing else", async () => {
  const body = await bodyOf(ok({ hello: "there" }));
  assertEquals(keysOf(body), ["data", "server_now"]);
  assert(isRfc3339Z(body.server_now), `server_now was ${body.server_now}`);
  assertEquals(body.data, { hello: "there" });
});

Deno.test("fail() is { server_now, error: { code, message } }", async () => {
  const res = fail("NO_GROUP");
  assertEquals(res.status, 409);
  const body = await bodyOf(res);
  assertEquals(keysOf(body), ["error", "server_now"]);
  assertEquals(keysOf(body.error), ["code", "message"]);
  assertEquals(body.error.code, "NO_GROUP");
});

Deno.test("every error code carries the status docs/04 §1 gives it", async () => {
  const contract = await Deno.readTextFile(
    new URL("../../../../docs/04-API-CONTRACT.md", import.meta.url),
  );
  let checked = 0;
  for (const code of ALL_CODES) {
    const row = contract.match(new RegExp(`^\\| \`${code}\` \\| (\\d{3}) \\|`, "m"));
    assert(row, `docs/04 §1 has no row for ${code}`);
    assertEquals(errorSpec(code).status, Number(row[1]), `${code} status`);
    checked += 1;
  }
  assertEquals(checked, ALL_CODES.length);
});

Deno.test("every error message is the string docs/11 gives it", async () => {
  const deck = await Deno.readTextFile(
    new URL("../../../../docs/11-COPY-DECK.md", import.meta.url),
  );
  for (const code of ALL_CODES) {
    const spec = errorSpec(code);
    const row = deck.match(
      new RegExp(`^\\| \`${spec.copyKey}\` \\| \`?${code}\`? \\| (.+?) \\|`, "m"),
    );
    assert(row, `docs/11 has no row keyed ${spec.copyKey} for ${code}`);
    assertEquals(spec.message, row[1].trim(), `${code} copy`);
  }
});

Deno.test("WRONG_PHASE carries state and nothing else — docs/14 §3", async () => {
  const withState = await bodyOf(fail("WRONG_PHASE", { state: "open" }));
  assertEquals(keysOf(withState.error), ["code", "message", "state"]);
  assertEquals(withState.error.state, "open");

  // No state to give: the key is absent, not null.
  const bare = await bodyOf(fail("WRONG_PHASE"));
  assertEquals(keysOf(bare.error), ["code", "message"]);
});

Deno.test("a detail meant for one code cannot be smuggled onto another", async () => {
  // The body is assembled per code, so `state` on a NOT_FOUND simply does not appear —
  // which is what stops a future handler leaking a round's phase through a 404.
  const notFound = await bodyOf(fail("NOT_FOUND", { state: "revealed", field: "round_id" }));
  assertEquals(keysOf(notFound.error), ["code", "message"]);

  const invalid = await bodyOf(fail("INVALID_INPUT", { field: "name", state: "open" }));
  assertEquals(keysOf(invalid.error), ["code", "details", "message"]);
  assertEquals(invalid.details, undefined);
  assertEquals(invalid.error.details, { field: "name" });
});

Deno.test("RATE_LIMITED sets Retry-After", () => {
  const res = fail("RATE_LIMITED", { retryAfterSeconds: 42 });
  assertEquals(res.status, 429);
  assertEquals(res.headers.get("retry-after"), "42");
});

Deno.test("noContent() is a bodiless 204", async () => {
  const res = noContent();
  assertEquals(res.status, 204);
  assertEquals(await res.text(), "");
});

// ─── routing ─────────────────────────────────────────────────────────────────

Deno.test("routePath strips the function prefix", () => {
  const url = (p: string) => `http://localhost:54421/functions/v1${p}`;
  assertEquals(routePath(url("/groups"), "groups"), "/");
  assertEquals(routePath(url("/groups/"), "groups"), "/");
  assertEquals(routePath(url("/groups/join"), "groups"), "/join");
  assertEquals(routePath(url("/groups/current/leave"), "groups"), "/current/leave");
  assertEquals(routePath(url("/groups/current?x=1"), "groups"), "/current");
  assertEquals(routePath(url("/me"), "me"), "/");
});

// ─── the parse step — docs/14 §7 ─────────────────────────────────────────────

const post = (body: unknown) =>
  new Request("http://localhost/x", { method: "POST", body: JSON.stringify(body) });

Deno.test("an unknown body key is rejected, not ignored", async () => {
  const error = await assertRejects(
    () => parseBody(post({ display_name: "Ana", is_admin: true }), { display_name: str() }),
    ApiError,
  );
  assertEquals(error.code, "INVALID_INPUT");
  assertEquals(error.detail.field, "is_admin");
});

Deno.test("parseBody returns exactly the schema's fields", async () => {
  const parsed = await parseBody(post({ name: "The Cove", reveal_hour: 19 }), {
    name: str({ min: 1, max: 40 }),
    reveal_hour: optional(int({ min: 18, max: 21 })),
    timezone: optional(str()),
  });
  assertEquals(parsed, { name: "The Cove", reveal_hour: 19, timezone: undefined });
});

Deno.test("parseBody enforces required, type, range and pattern", async () => {
  const cases: [unknown, Record<string, ReturnType<typeof str>>, string][] = [
    [{}, { name: str() }, "name"],
    [{ name: 7 }, { name: str() }, "name"],
    [{ name: "" }, { name: str({ min: 1 }) }, "name"],
    [{ name: "x".repeat(41) }, { name: str({ max: 40 }) }, "name"],
    [{ code: "abc" }, { code: str({ pattern: /^[A-Z]{3}$/ }) }, "code"],
    [[], { name: str() }, "body"],
    ["not json at all", { name: str() }, "body"],
  ];
  for (const [body, schema, field] of cases) {
    const req = typeof body === "string"
      ? new Request("http://localhost/x", { method: "POST", body })
      : post(body);
    const error = await assertRejects(() => parseBody(req, schema), ApiError);
    assertEquals(error.code, "INVALID_INPUT");
    assertEquals(error.detail.field, field, `field for ${JSON.stringify(body)}`);
  }
});

Deno.test("int() rejects a non-integer and enforces its range", async () => {
  for (const value of [19.5, "19", 17, 22, null]) {
    const error = await assertRejects(
      () => parseBody(post({ reveal_hour: value }), { reveal_hour: int({ min: 18, max: 21 }) }),
      ApiError,
    );
    assertEquals(error.detail.field, "reveal_hour");
  }
});

Deno.test("string length counts code points, like Postgres char_length", async () => {
  // Twenty-four emoji is twenty-four characters to a user and to the database. It must not
  // be forty-eight here (docs/11: names may hold emoji).
  const name = "🎧".repeat(24);
  const parsed = await parseBody(post({ display_name: name }), { display_name: str({ max: 24 }) });
  assertEquals(parsed.display_name, name);

  await assertRejects(
    () => parseBody(post({ display_name: "🎧".repeat(25) }), { display_name: str({ max: 24 }) }),
    ApiError,
  );
});

// ─── time ────────────────────────────────────────────────────────────────────

Deno.test("rfc3339 is UTC, Z-suffixed, whole seconds", () => {
  assertEquals(rfc3339("2026-08-10T16:11:02.184362+00:00"), "2026-08-10T16:11:02Z");
  assertEquals(rfc3339("2026-08-10T12:11:02.000-04:00"), "2026-08-10T16:11:02Z");
  assertEquals(rfc3339(new Date(Date.UTC(2026, 7, 10, 16, 11, 2))), "2026-08-10T16:11:02Z");
  assertThrows(() => rfc3339("not a time"));
});

Deno.test("localDate resolves the group-local calendar date, across a DST boundary", () => {
  const tz = "America/New_York";
  // 2026-03-08 01:30 EST and 2026-03-08 03:30 EDT are the same local date either side of the
  // spring-forward, and 03:00 UTC on the 8th is still the 7th in New York.
  assertEquals(localDate(tz, new Date("2026-03-08T06:30:00Z")), "2026-03-08");
  assertEquals(localDate(tz, new Date("2026-03-08T03:00:00Z")), "2026-03-07");
  assertEquals(localDate("UTC", new Date("2026-03-08T03:00:00Z")), "2026-03-08");
  assertEquals(localDate("Pacific/Auckland", new Date("2026-08-10T23:00:00Z")), "2026-08-11");
});

Deno.test("nextDate crosses months and years", () => {
  assertEquals(nextDate("2026-08-10"), "2026-08-11");
  assertEquals(nextDate("2026-08-31"), "2026-09-01");
  assertEquals(nextDate("2026-12-31"), "2027-01-01");
  assertEquals(nextDate("2028-02-28"), "2028-02-29");
});

Deno.test("hasPassed compares against the passed-in now, not the process clock", () => {
  const now = new Date("2026-08-10T20:00:00Z");
  assert(hasPassed("2026-08-10T20:00:00Z", now));
  assert(hasPassed("2026-08-10T19:59:59Z", now));
  assert(!hasPassed("2026-08-10T20:00:01Z", now));
});

// ─── the guards — docs/14 §4 ─────────────────────────────────────────────────

Deno.test("requireUser: anonymous, malformed and forged tokens all get 401", async () => {
  const requests = [
    new Request("http://localhost/me"),
    new Request("http://localhost/me", { headers: { authorization: "Basic abc" } }),
    new Request("http://localhost/me", { headers: { authorization: "Bearer " } }),
    new Request("http://localhost/me", { headers: { authorization: "Bearer not.a.token" } }),
    new Request("http://localhost/me", {
      headers: { authorization: `Bearer ${await mintToken(ANA, { expiresIn: -60 })}` },
    }),
  ];
  for (const req of requests) {
    const error = await assertRejects(() => requireUser(req, "GET /"), ApiError);
    assertEquals(error.code, "UNAUTHENTICATED");
  }
});

Deno.test("requireProfile: 409 NO_PROFILE before onboarding, then the name", async () => {
  const fresh = await newUser();
  const freshCtx = await requireUser(authed(fresh.token), "GET /");
  const error = await assertRejects(() => requireProfile(freshCtx), ApiError);
  assertEquals(error.code, "NO_PROFILE");

  const anaCtx = await requireProfile(await requireUser(authed(await mintToken(ANA)), "GET /"));
  assertEquals(anaCtx.displayName, "Ana");
  assertEquals(anaCtx.userId, ANA);
});

Deno.test("requireMembership: 409 NO_GROUP, and it takes no group parameter", async () => {
  // The signature is the point: there is no group id to pass, so there is no IDOR surface
  // for group data anywhere in the client-facing API (ADR-005, docs/14 §4).
  assertEquals(requireMembership.length, 1);

  const nameless = await newUser();
  const profileCtx = {
    ...(await requireUser(authed(nameless.token), "GET /")),
    displayName: "Nobody",
  };
  const error = await assertRejects(() => requireMembership(profileCtx), ApiError);
  assertEquals(error.code, "NO_GROUP");

  const ana = await requireMembership(
    await requireProfile(await requireUser(authed(await mintToken(ANA)), "GET /")),
  );
  assertEquals(ana.role, "admin");
  assert(ana.groupId);
});

Deno.test("requireAdmin: a member cannot change group settings", () => {
  const member = { role: "member" } as MemberCtx;
  const admin = { role: "admin" } as MemberCtx;
  assertEquals(assertThrows(() => requireAdmin(member), ApiError).code, "NOT_ADMIN");
  assertEquals(requireAdmin(admin), admin);
});

Deno.test("requirePhase: wrong phase reports the state; voided has its own code", () => {
  requirePhase({ state: "open" }, ["open"]);
  const wrong = assertThrows(() => requirePhase({ state: "scored" }, ["open"]), ApiError);
  assertEquals(wrong.code, "WRONG_PHASE");
  assertEquals(wrong.detail.state, "scored");

  const voided = assertThrows(() => requirePhase({ state: "voided" }, ["open"]), ApiError);
  assertEquals(voided.code, "ROUND_VOIDED");
});

Deno.test("requireJoinedBefore: joining after the reveal sits the round out", () => {
  const reveals = "2026-08-10T00:00:00Z";
  requireJoinedBefore({ joinedAt: "2026-08-09T23:59:59Z" } as MemberCtx, reveals);
  const error = assertThrows(
    () => requireJoinedBefore({ joinedAt: reveals } as MemberCtx, reveals),
    ApiError,
  );
  assertEquals(error.code, "JOINED_LATE");
});

// ─── rate limiting — docs/04 §8 ──────────────────────────────────────────────

Deno.test("enforceRateLimit admits up to the limit, then 429s with a Retry-After", async () => {
  const db = serviceClient();
  const bucket = `test:${crypto.randomUUID()}`;
  await enforceRateLimit(db, bucket, 2, 3600);
  await enforceRateLimit(db, bucket, 2, 3600);

  const error = await assertRejects(() => enforceRateLimit(db, bucket, 2, 3600), ApiError);
  assertEquals(error.code, "RATE_LIMITED");
  assert((error.detail.retryAfterSeconds ?? 0) > 0, "a 429 must say how long to wait");

  // A different bucket is unaffected — limits are per user per route, never shared.
  await enforceRateLimit(db, `test:${crypto.randomUUID()}`, 2, 3600);
});

function authed(token: string): Request {
  return new Request("http://localhost/me", { headers: { authorization: `Bearer ${token}` } });
}
