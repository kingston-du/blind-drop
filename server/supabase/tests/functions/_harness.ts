// _harness.ts — what every Edge Function test needs. Not a test itself (the leading
// underscore keeps it out of the runner's glob).
//
// The tests are black box: they speak HTTP to the running stack with a real access token, so
// what they assert is what a device would actually receive — including the status code and
// the exact key set of the body. Nothing here reaches into the database to arrange state that
// the API itself can arrange.

const env = (name: string): string => {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(
      `${name} is not set. Run the suite with \`npm run test:functions\`, which reads it from \`supabase status\`.`,
    );
  }
  return value;
};

export const API_URL = env("SUPABASE_URL");
export const ANON_KEY = env("SUPABASE_ANON_KEY");
export const SERVICE_KEY = env("SUPABASE_SERVICE_ROLE_KEY");
const JWT_SECRET = env("SUPABASE_JWT_SECRET");

// ─── access tokens ───────────────────────────────────────────────────────────
// Tokens are minted here rather than obtained by signing in. Sign in with Apple cannot run
// against a local stack, and the password grant is rate-limited per IP by GoTrue
// (`sign_in_sign_ups`), which would make a second run of this suite in five minutes fail for
// a reason that has nothing to do with the code. The minted token is a real HS256 token that
// GoTrue itself validates — `requireUser` verifies it by calling GoTrue, not by trusting us.

const encoder = new TextEncoder();

function base64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

export async function mintToken(
  userId: string,
  opts: { expiresIn?: number } = {},
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(encoder.encode(JSON.stringify({ alg: "HS256", typ: "JWT" })));
  const payload = base64url(
    encoder.encode(
      JSON.stringify({
        sub: userId,
        aud: "authenticated",
        role: "authenticated",
        iss: `${API_URL}/auth/v1`,
        iat: now,
        exp: now + (opts.expiresIn ?? 3600),
      }),
    ),
  );
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(JWT_SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, encoder.encode(`${header}.${payload}`)),
  );
  return `${header}.${payload}.${base64url(signature)}`;
}

// ─── people ──────────────────────────────────────────────────────────────────

export interface TestUser {
  id: string;
  email: string;
  token: string;
}

/** A signed-in user with no profile yet — onboarding step 1 (docs/04 §2). */
export async function newUser(): Promise<TestUser> {
  const email = `t-${crypto.randomUUID()}@fixture.blinddrop.test`;
  const res = await fetch(`${API_URL}/auth/v1/admin/users`, {
    method: "POST",
    headers: {
      apikey: SERVICE_KEY,
      authorization: `Bearer ${SERVICE_KEY}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({ email, email_confirm: true }),
  });
  if (!res.ok) throw new Error(`could not create a test user: ${res.status} ${await res.text()}`);
  const user = await res.json();
  return { id: user.id, email, token: await mintToken(user.id) };
}

/** A user who has been through onboarding step 2 and has a display name. */
export async function newNamedUser(displayName: string): Promise<TestUser> {
  const user = await newUser();
  const named = await call("me", "/", {
    method: "PUT",
    token: user.token,
    body: { display_name: displayName },
  });
  if (named.status !== 200) throw new Error(`could not name a test user: ${named.status}`);
  return user;
}

/** A user in a group of their own, which is the state most handlers assume. */
export async function newGroupOwner(
  displayName: string,
  group: { name?: string; timezone?: string; reveal_hour?: number; cue_cadence?: number } = {},
): Promise<{ user: TestUser; group: Record<string, unknown> }> {
  const user = await newNamedUser(displayName);
  const created = await call("groups", "/", {
    method: "POST",
    token: user.token,
    body: {
      name: group.name ?? "The Cove",
      timezone: group.timezone ?? "America/New_York",
      ...(group.reveal_hour === undefined ? {} : { reveal_hour: group.reveal_hour }),
    },
  });
  if (created.status !== 200) {
    throw new Error(`could not create a group: ${created.status} ${JSON.stringify(created.body)}`);
  }
  const createdGroup = created.body.data as Record<string, unknown>;
  // A cadence is set through the PATCH path after creation, before any round exists, so a test
  // can pin cue presence deterministically rather than gambling on the random group id's hash.
  if (group.cue_cadence !== undefined) {
    const patched = await call("groups", `/${createdGroup.id}`, {
      method: "PATCH",
      token: user.token,
      body: { cue_cadence: group.cue_cadence },
    });
    if (patched.status !== 200) {
      throw new Error(`could not set cue_cadence: ${patched.status} ${JSON.stringify(patched.body)}`);
    }
  }
  return { user, group: createdGroup };
}

/** Somebody else in an existing group, by invite code. */
export async function newMember(inviteCode: string, displayName: string): Promise<TestUser> {
  const user = await newNamedUser(displayName);
  const joined = await call("groups", "/join", {
    method: "POST",
    token: user.token,
    body: { invite_code: inviteCode },
  });
  if (joined.status !== 200) {
    throw new Error(`could not join a test user: ${joined.status} ${JSON.stringify(joined.body)}`);
  }
  return user;
}

// ─── the scheduler, and the clock it runs against ────────────────────────────
// Phase transitions are the tick job's and nothing else's (docs/02 §2), so a test that needs a
// `voided` round cannot arrange one through the API — there is deliberately no route that
// moves a round. These two helpers are the exception to "arrange state through the API": one
// runs the real `tick_rounds()`, and the other picks a timezone that puts a group's reveal
// where the test needs it.
//
// Nothing here fakes a clock. `now_()` reads a session setting and PostgREST gives every
// request its own session, so there is no way to move the server's time from out here — and
// that is fine, because moving the *group* is equivalent and uses only real time. A group in
// `Etc/GMT-9` whose reveal hour has passed there is a genuinely late round, not a simulated
// one, and `tick_rounds()` treats it exactly as it treats a real one at 8pm in Brooklyn.

/** Calls a Postgres function as `service_role`, the way the Edge Functions do. */
export async function serviceRpc(name: string, args: Record<string, unknown> = {}): Promise<void> {
  const res = await fetch(`${API_URL}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: SERVICE_KEY,
      authorization: `Bearer ${SERVICE_KEY}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(args),
  });
  if (!res.ok) throw new Error(`rpc ${name} failed: ${res.status} ${await res.text()}`);
  await res.body?.cancel();
}

/** One run of the scheduler, right now, against real time. */
export async function tickRounds(): Promise<void> {
  await serviceRpc("tick_rounds");
}

/**
 * One run of the scheduler as if it were `hoursFromNow` hours later.
 *
 * `tick_rounds_at` is installed by `seed.sql` and exists in no deployed database — the note
 * there explains why it must stay out of the migrations. It is the function-test equivalent of
 * the pgTAP suite's `set_test_now()`: the transition it produces is the real one, computed by
 * the real `tick_rounds()`, and only the instant it is evaluated against is chosen.
 *
 * Keep the offset small enough that the group's *local date* does not change, because the
 * handlers still read the real clock and will go looking for today's round.
 */
export async function tickRoundsAt(hoursFromNow: number): Promise<void> {
  const at = new Date(Date.now() + hoursFromNow * 3_600_000).toISOString();
  await serviceRpc("tick_rounds_at", { p_at: at });
}

/**
 * Moves a member's `joined_at`, for the one scenario the API cannot reach.
 *
 * docs/02 §3 gives someone who joined after a reveal specific behaviour, but a round only
 * exists if its reveal was still ahead when it was created (0004) — so every join a test can
 * make lands before it, by an hour of real time. `set_membership_joined_at` is installed by
 * `seed.sql` and exists in no deployed database, for the same reason `tick_rounds_at` does.
 */
export async function setJoinedAt(userId: string, at: Date): Promise<void> {
  await serviceRpc("set_membership_joined_at", { p_user: userId, p_at: at.toISOString() });
}

/**
 * A fixed-offset IANA zone in which the local wall clock currently reads `hour`.
 *
 * `Etc/GMT±N` has no DST, so the offset is exact and the same all year — which is what makes a
 * test built on it deterministic rather than green until October. Note the inverted sign:
 * `Etc/GMT-9` is UTC+9, a POSIX convention old enough to vote.
 */
export function zoneWhereLocalHourIs(hour: number): string {
  const utcHour = new Date().getUTCHours();
  let offset = (hour - utcHour + 24) % 24;
  if (offset > 14) offset -= 24; // Etc/GMT spans UTC-12 … UTC+14
  if (offset === 0) return "UTC";
  return offset > 0 ? `Etc/GMT-${offset}` : `Etc/GMT+${-offset}`;
}

// ─── the call ────────────────────────────────────────────────────────────────

/** An address from 198.18.0.0/15, reserved for benchmarking by RFC 2544 and never a real
 *  client. 2^17 of them, so two calls colliding is rare and 30 colliding — the number it would
 *  take to matter — is not going to happen. `crypto.getRandomValues` rather than `Math.random`
 *  because `scripts/lint.mjs` fails the build on `Math.random` anywhere under `supabase/`. */
export function randomTestIp(): string {
  const [high, mid, low] = crypto.getRandomValues(new Uint8Array(3));
  return `198.${18 + (high % 2)}.${mid}.${low}`;
}

export interface ApiResponse {
  status: number;
  // deno-lint-ignore no-explicit-any
  body: any;
  headers: Headers;
}

export async function call(
  functionName: string,
  path: string,
  opts: {
    method?: string;
    token?: string | null;
    body?: unknown;
    headers?: Record<string, string>;
  } = {},
): Promise<ApiResponse> {
  const headers: Record<string, string> = {
    apikey: ANON_KEY,
    "content-type": "application/json",
    // Every call looks like a distinct client unless a test says otherwise. The per-IP half of
    // the join limit (30/hour, docs/04 §8) is real state in `rate_limit_events` that outlives a
    // test run, so a suite that shared one IP would poison itself: ~15 joins per run means the
    // second run inside an hour would start getting 429s that have nothing to do with the code
    // under test. Tests that are *about* the IP limit pin `x-forwarded-for` themselves.
    "x-forwarded-for": randomTestIp(),
    ...opts.headers,
  };
  if (opts.token) headers.authorization = `Bearer ${opts.token}`;

  const method = opts.method ?? "GET";
  const sendsBody = opts.body !== undefined && method !== "GET" && method !== "HEAD";
  const res = await fetch(`${API_URL}/functions/v1/${functionName}${path === "/" ? "" : path}`, {
    method,
    headers,
    body: sendsBody ? JSON.stringify(opts.body) : undefined,
  });
  const text = await res.text();
  return {
    status: res.status,
    body: text === "" ? null : JSON.parse(text),
    headers: res.headers,
  };
}

// ─── assertions the leak rules need ──────────────────────────────────────────

/** The exact key set, sorted. Used wherever docs/04 says "there is no other key". */
export function keysOf(value: unknown): string[] {
  return Object.keys(value as Record<string, unknown>).sort();
}

const RFC3339_Z = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;

export function isRfc3339Z(value: unknown): boolean {
  return typeof value === "string" && RFC3339_Z.test(value);
}
