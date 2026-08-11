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

export async function mintToken(userId: string, opts: { expiresIn?: number } = {}): Promise<string> {
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
  const named = await call("me", "/", { method: "PUT", token: user.token, body: { display_name: displayName } });
  if (named.status !== 200) throw new Error(`could not name a test user: ${named.status}`);
  return user;
}

/** A user in a group of their own, which is the state most handlers assume. */
export async function newGroupOwner(
  displayName: string,
  group: { name?: string; timezone?: string; reveal_hour?: number } = {},
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
  if (created.status !== 200) throw new Error(`could not create a group: ${created.status} ${JSON.stringify(created.body)}`);
  return { user, group: created.body.data as Record<string, unknown> };
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
