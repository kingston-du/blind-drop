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
  | "NOT_ADMIN"
  | "RATE_LIMITED"
  | "UPSTREAM_UNAVAILABLE"
  | "INTERNAL";

const ERRORS: Record<ErrorCode, { status: number; message: string; copyKey: string }> = {
  UNAUTHENTICATED: { status: 401, message: "Sign in again to keep playing.", copyKey: "error.unauthenticated" },
  NO_PROFILE: { status: 409, message: "Pick a name first.", copyKey: "error.noprofile" },
  NO_GROUP: { status: 409, message: "You're not in a group yet.", copyKey: "error.nogroup" },
  NOT_FOUND: { status: 404, message: "That doesn't exist.", copyKey: "error.notfound" },
  WRONG_PHASE: { status: 409, message: "That's not available right now.", copyKey: "error.wrongphase" },
  NOT_A_SUBMITTER: { status: 403, message: "You didn't drop a song tonight.", copyKey: "error.notsubmitter" },
  JOINED_LATE: { status: 403, message: "You joined after the reveal. You're in from tomorrow.", copyKey: "error.joinedlate" },
  ROUND_VOIDED: { status: 409, message: "Not enough drops tonight. Nothing revealed.", copyKey: "error.roundvoided" },
  INVALID_INPUT: { status: 400, message: "Check that and try again.", copyKey: "error.invalidinput" },
  ALREADY_IN_GROUP: { status: 409, message: "You're already in a group. Leave it first.", copyKey: "error.alreadyingroup" },
  NOT_ADMIN: { status: 403, message: "Only the group's admin can change that.", copyKey: "error.notadmin" },
  RATE_LIMITED: { status: 429, message: "Slow down a second.", copyKey: "error.ratelimited" },
  UPSTREAM_UNAVAILABLE: { status: 502, message: "The music catalog isn't answering. Try again in a minute.", copyKey: "error.upstream" },
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

/** `{ server_now, data }` — docs/04 §1. */
export function ok(data: unknown, status = 200): Response {
  return json({ server_now: rfc3339(serverNow()), data }, status);
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

/** A handler receives the request and the route key it matched (used as the rate-limit
 *  bucket label, so limits are per user *per route*, never per group — docs/04 §8). */
export type Handler = (req: Request, route: string) => Promise<Response>;

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
 * One `Deno.serve` per function group, with the routes named as `"<METHOD> <path>"`.
 *
 * Everything a handler throws lands here: an `ApiError` becomes its envelope, anything else
 * becomes `INTERNAL` with the detail written to the server log and never to the client.
 */
export function serveFunction(functionName: string, routes: Record<string, Handler>): void {
  Deno.serve(async (req: Request) => {
    const route = `${req.method} ${routePath(req.url, functionName)}`;
    try {
      const handler = routes[route];
      if (!handler) return fail("NOT_FOUND");
      return await handler(req, route);
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

export function str(opts: { min?: number; max?: number; pattern?: RegExp } = {}): Validator<string> {
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
    if (value === undefined && !validator.optional) throw new ApiError("INVALID_INPUT", { field: key });
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
