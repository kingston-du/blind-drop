// _shared/http.ts — the envelope, the router, and the parse step. docs/04 §1, docs/14 §3, §7.
//
// **This is the only file in the project that constructs a `Response`.** `scripts/lint.mjs`
// fails the build on a `new Response` anywhere else, because an ad-hoc response is an
// envelope that nobody reviewed and a `server_now` the client cannot trust.

import { rfc3339, type RoundState, serverNow } from "./time.ts";

// ─── error codes ─────────────────────────────────────────────────────────────
// Every code in docs/04 §1, with its HTTP status and its copy-deck string. `message` is
// user-presentable and is the *only* prose the client ever shows for a failure; `code` is
// what the client switches on. A raw database message never reaches either field.

export type ErrorCode =
  | "UNAUTHENTICATED"
  | "NO_PROFILE"
  | "NO_GROUP"
  | "NOT_FOUND"
  | "WRONG_PHASE"
  | "NOT_A_SUBMITTER"
  | "JOINED_LATE"
  | "ROUND_VOIDED"
  | "INVALID_INPUT"
  | "ALREADY_IN_GROUP"
  | "CIRCLE_LIMIT_REACHED"
  | "NOT_ADMIN"
  | "RATE_LIMITED"
  | "UPSTREAM_UNAVAILABLE"
  | "REAUTHENTICATION_REQUIRED"
  | "REAUTHENTICATION_FAILED"
  | "AUTH_PROVIDER_UNAVAILABLE"
  | "INTERNAL";

const ERRORS: Record<ErrorCode, { status: number; message: string; copyKey: string }> = {
  UNAUTHENTICATED: {
    status: 401,
    message: "Sign in again to keep playing.",
    copyKey: "error.unauthenticated",
  },
  NO_PROFILE: { status: 409, message: "Pick a name first.", copyKey: "error.noprofile" },
  NO_GROUP: { status: 409, message: "You're not in a group yet.", copyKey: "error.nogroup" },
  NOT_FOUND: { status: 404, message: "That doesn't exist.", copyKey: "error.notfound" },
  WRONG_PHASE: {
    status: 409,
    message: "That's not available right now.",
    copyKey: "error.wrongphase",
  },
  NOT_A_SUBMITTER: {
    status: 403,
    message: "You didn't drop a song tonight.",
    copyKey: "error.notsubmitter",
  },
  JOINED_LATE: {
    status: 403,
    message: "You joined after the reveal. You're in from tomorrow.",
    copyKey: "error.joinedlate",
  },
  ROUND_VOIDED: {
    status: 409,
    message: "Not enough drops tonight. Nothing revealed.",
    copyKey: "error.roundvoided",
  },
  INVALID_INPUT: {
    status: 400,
    message: "Check that and try again.",
    copyKey: "error.invalidinput",
  },
  ALREADY_IN_GROUP: {
    status: 409,
    message: "You're already in that circle.",
    copyKey: "error.alreadyingroup",
  },
  CIRCLE_LIMIT_REACHED: {
    status: 409,
    message: "You're already in three circles. Leave one to join another.",
    copyKey: "error.circlelimitreached",
  },
  NOT_ADMIN: {
    status: 403,
    message: "Only the group's admin can change that.",
    copyKey: "error.notadmin",
  },
  RATE_LIMITED: { status: 429, message: "Slow down a second.", copyKey: "error.ratelimited" },
  UPSTREAM_UNAVAILABLE: {
    status: 502,
    message: "The music catalog isn't answering. Try again in a minute.",
    copyKey: "error.upstream",
  },
  REAUTHENTICATION_REQUIRED: {
    status: 409,
    message: "Sign in with Apple again to finish deleting your account.",
    copyKey: "settings.delete.reauth",
  },
  REAUTHENTICATION_FAILED: {
    status: 403,
    message: "Use the same Apple Account to finish deleting your account.",
    copyKey: "settings.delete.reauth",
  },
  AUTH_PROVIDER_UNAVAILABLE: {
    status: 502,
    message: "Apple sign-in isn't answering. Try again.",
    copyKey: "error.authprovider",
  },
  INTERNAL: { status: 500, message: "That didn't work. Try again.", copyKey: "error.generic" },
};

/** What a failing code is allowed to carry beyond `code` and `message`. Deliberately tiny:
 *  docs/14 §3 closes the "`WRONG_PHASE` body mentions how many people submitted" channel by
 *  making it impossible to attach anything but the state. */
export interface ErrorDetail {
  /** `WRONG_PHASE` only — the round's state, and nothing else about the round. */
  state?: RoundState;
  /** `INVALID_INPUT` only — the offending field name. Never the offending value. */
  field?: string;
  /** `RATE_LIMITED` only — seconds until the window frees up, for `Retry-After`. */
  retryAfterSeconds?: number;
}

/** Thrown by guards and validators; turned into a response by `serveFunction`. */
export class ApiError extends Error {
  constructor(readonly code: ErrorCode, readonly detail: ErrorDetail = {}) {
    super(code);
    this.name = "ApiError";
  }
}

// ─── the envelope ────────────────────────────────────────────────────────────

function json(body: unknown, status: number, headers: HeadersInit = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...headers },
  });
}

/** `{ server_now, data }` — docs/04 §1.
 *
 *  `headers` exists for one caller: `GET /tracks/search` sets `Cache-Control` so the edge can
 *  hold a catalog answer for ten minutes (docs/06 §4). It is deliberately not a general escape
 *  hatch — a header that varies with group state is the same leak as a body field that does
 *  (docs/14 §3), so anything added here belongs to the *catalog*, never to a round. */
export function ok(data: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return json({ server_now: rfc3339(serverNow()), data }, status, headers);
}

/** `{ server_now, error: { code, message, … } }` — docs/04 §1.
 *
 *  The body is assembled field by field per code rather than by spreading `detail`, so a
 *  future caller cannot smuggle an extra key onto an error response. */
export function fail(code: ErrorCode, detail: ErrorDetail = {}): Response {
  const spec = ERRORS[code];
  const error: Record<string, unknown> = { code, message: spec.message };
  if (code === "WRONG_PHASE" && detail.state) error.state = detail.state;
  if (code === "INVALID_INPUT" && detail.field) error.details = { field: detail.field };

  const headers: Record<string, string> = {};
  if (code === "RATE_LIMITED" && detail.retryAfterSeconds) {
    headers["retry-after"] = String(detail.retryAfterSeconds);
  }
  return json({ server_now: rfc3339(serverNow()), error }, spec.status, headers);
}

/** 204, for the bodiless routes: leaving a group, registering a device, and deleting an
 *  account. They are the only responses without `server_now`, because a 204 by definition
 *  has no body to put one in. */
export function noContent(): Response {
  return new Response(null, { status: 204 });
}

/** The copy-deck key backing each code, for the test that asserts docs/11 and this file
 *  still agree. Exported for tests only. */
export function errorSpec(code: ErrorCode): { status: number; message: string; copyKey: string } {
  return ERRORS[code];
}

// ─── routing ─────────────────────────────────────────────────────────────────

/**
 * A handler receives the request, the route key it matched, and any path parameters.
 *
 * `route` is the *pattern* — `"GET /:round_id/results"`, never the concrete path — and it is
 * what the rate-limit bucket is keyed on (docs/04 §8). That distinction is the whole reason
 * this parameter exists as a string rather than being derived from `req.url`: a bucket keyed on
 * the concrete path would give every round id its own 120/min allowance, so a caller could have
 * as many allowances as they could name ids. Limits are per user per *route*.
 */
export type Handler = (
  req: Request,
  route: string,
  params: Record<string, string>,
) => Promise<Response>;

/**
 * The path *within* a function: Supabase serves `/functions/v1/<name>/<rest>`, and only
 * `<rest>` is ours to route on. `/functions/v1/groups/current/leave` → `/current/leave`.
 */
export function routePath(url: string, functionName: string): string {
  const pathname = new URL(url).pathname;
  const marker = `/${functionName}`;
  const at = pathname.indexOf(marker);
  if (at === -1) return "/";
  const rest = pathname.slice(at + marker.length).replace(/\/+$/, "");
  return rest === "" ? "/" : rest;
}

/**
 * Matches a concrete request against one route key, returning its path parameters or `null`.
 *
 * A segment written `:name` in the key matches exactly one non-empty segment and binds it. The
 * matching is segment-by-segment rather than by regular expression on purpose: a `.*` in a
 * hand-rolled route pattern is how `/current/submission` ends up being served by the handler
 * for `/{round_id}/results`, and the arity check below makes that class of mistake unwriteable.
 *
 * **A parameter is a string that came from the caller and is worth exactly that much.** Nothing
 * here validates one — the handler does, against the caller's own membership, which is the only
 * check that means anything (docs/14 §4).
 */
function matchRoute(key: string, method: string, path: string): Record<string, string> | null {
  const [keyMethod, keyPath] = key.split(" ", 2);
  if (keyMethod !== method) return null;

  const keySegments = keyPath.split("/");
  const pathSegments = path.split("/");
  if (keySegments.length !== pathSegments.length) return null;

  const params: Record<string, string> = {};
  for (let i = 0; i < keySegments.length; i += 1) {
    const expected = keySegments[i];
    const actual = pathSegments[i];
    if (expected.startsWith(":")) {
      if (actual === "") return null;
      params[expected.slice(1)] = decodeURIComponent(actual);
      continue;
    }
    if (expected !== actual) return null;
  }
  return params;
}

/**
 * One `Deno.serve` per function group, with the routes named as `"<METHOD> <path>"`, where a
 * path segment may be `:a_parameter`.
 *
 * Literal routes are tried first and as a plain object lookup, so `GET /current` cannot be
 * captured by a `GET /:round_id` declared above it — the order routes happen to be written in
 * is not allowed to change which one answers. Only when no literal matches does the parameter
 * matching run.
 *
 * Everything a handler throws lands here: an `ApiError` becomes its envelope, anything else
 * becomes `INTERNAL` with the detail written to the server log and never to the client.
 */
export function serveFunction(functionName: string, routes: Record<string, Handler>): void {
  const patterns = Object.keys(routes).filter((key) => key.includes("/:"));

  Deno.serve(async (req: Request) => {
    const path = routePath(req.url, functionName);
    let route = `${req.method} ${path}`;
    let params: Record<string, string> = {};

    try {
      let handler = routes[route];
      if (!handler) {
        for (const key of patterns) {
          const matched = matchRoute(key, req.method, path);
          if (matched) {
            handler = routes[key];
            route = key;
            params = matched;
            break;
          }
        }
      }
      if (!handler) return fail("NOT_FOUND");
      return await handler(req, route, params);
    } catch (err) {
      if (err instanceof ApiError) return fail(err.code, err.detail);
      // Server-side only. Message, not payload: a thrown database error can quote the row
      // that caused it, and rows are exactly what must not be logged (docs/14 §9).
      console.error(`${route} failed:`, err instanceof Error ? err.message : String(err));
      return fail("INTERNAL");
    }
  });
}

// ─── the parse step ──────────────────────────────────────────────────────────
// docs/14 §7: "Every body validated against an explicit schema. Unknown keys are rejected,
// not ignored — a silently-ignored key is how a future field becomes a vulnerability."

export interface Validator<T> {
  readonly optional: boolean;
  parse(value: unknown, field: string): T;
}

function invalid(field: string): never {
  throw new ApiError("INVALID_INPUT", { field });
}

export function str(
  opts: { min?: number; max?: number; pattern?: RegExp } = {},
): Validator<string> {
  return {
    optional: false,
    parse(value, field) {
      if (typeof value !== "string") invalid(field);
      const v = value as string;
      // Length in code points, matching Postgres `char_length` — an emoji is one character
      // to a user and to the database, and must not be two here (docs/11: names may hold
      // emoji).
      const length = [...v].length;
      if (opts.min !== undefined && length < opts.min) invalid(field);
      if (opts.max !== undefined && length > opts.max) invalid(field);
      if (opts.pattern && !opts.pattern.test(v)) invalid(field);
      return v;
    },
  };
}

export function int(opts: { min?: number; max?: number } = {}): Validator<number> {
  return {
    optional: false,
    parse(value, field) {
      if (typeof value !== "number" || !Number.isInteger(value)) invalid(field);
      const v = value as number;
      if (opts.min !== undefined && v < opts.min) invalid(field);
      if (opts.max !== undefined && v > opts.max) invalid(field);
      return v;
    },
  };
}

/** Absent is fine; present-but-wrong is still `INVALID_INPUT`. An explicit `null` is treated
 *  as absent only where a route documents `null` as a value (guess sheets, docs/04 §4). */
export function optional<T>(inner: Validator<T>): Validator<T | undefined> {
  return {
    optional: true,
    parse(value, field) {
      if (value === undefined) return undefined;
      return inner.parse(value, field);
    },
  };
}

type Schema = Record<string, Validator<unknown>>;
type Parsed<S extends Schema> = { [K in keyof S]: ReturnType<S[K]["parse"]> };

/**
 * Reads the JSON body and returns exactly the fields in `schema` — no more, and no less than
 * the required ones. An unknown key fails the request naming that key.
 */
export async function parseBody<S extends Schema>(req: Request, schema: S): Promise<Parsed<S>> {
  let raw: unknown;
  try {
    const text = await req.text();
    raw = text.trim() === "" ? {} : JSON.parse(text);
  } catch {
    throw new ApiError("INVALID_INPUT", { field: "body" });
  }
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) {
    throw new ApiError("INVALID_INPUT", { field: "body" });
  }
  const body = raw as Record<string, unknown>;

  for (const key of Object.keys(body)) {
    if (!(key in schema)) throw new ApiError("INVALID_INPUT", { field: key });
  }

  const out: Record<string, unknown> = {};
  for (const [key, validator] of Object.entries(schema)) {
    const value = body[key];
    if (value === undefined && !validator.optional) {
      throw new ApiError("INVALID_INPUT", { field: key });
    }
    out[key] = validator.parse(value, key);
  }
  return out as Parsed<S>;
}

/** The caller's IP, for the per-IP half of the join limit (docs/04 §8). Trusted only as far
 *  as the platform's own proxy header; it is a rate-limit bucket, never an identity. */
export function clientIp(req: Request): string {
  const forwarded = req.headers.get("x-forwarded-for");
  if (forwarded) return forwarded.split(",")[0].trim();
  return req.headers.get("x-real-ip")?.trim() ?? "unknown";
}
