// _shared/auth.ts — the authorization pipeline. docs/14 §4.
//
//   1. requireUser(req, route)        → user_id, or 401 UNAUTHENTICATED
//   2. requireProfile(ctx)            → display_name, or 409 NO_PROFILE
//   3. requireMembership(ctx)         → group_id, role, joined_at, or 409 NO_GROUP
//   4. requirePhase(round, [...])     → or 409 WRONG_PHASE
//
// Guess handlers apply joined-in-time before submitter eligibility through the shared helper
// in `rounds/index.ts`; that owner-approved order keeps JOINED_LATE reachable for newcomers.
//
// The guards compose: each takes the context the previous one returned and widens it, so a
// handler cannot reach step 3 without having passed steps 1 and 2. **`requireMembership`
// takes no group parameter** — the group comes from the caller's active membership and never
// from the request, which is what leaves the client-facing API with no IDOR surface for group
// data (ADR-005, docs/14 §4).

import { ApiError } from "./http.ts";
import { type Db, dbFailure, serviceClient } from "./db.ts";
import type { RoundState } from "./time.ts";

export interface UserCtx {
  readonly db: Db;
  readonly userId: string;
  /** `"GET /current"` — the rate-limit bucket label. Per user per route, never per group. */
  readonly route: string;
}

export interface ProfileCtx extends UserCtx {
  readonly displayName: string;
}

export interface MemberCtx extends ProfileCtx {
  readonly groupId: string;
  readonly role: "member" | "admin";
  readonly joinedAt: string;
}

// ─── 1. authenticate ─────────────────────────────────────────────────────────

function bearerToken(req: Request): string | null {
  const header = req.headers.get("authorization");
  if (!header) return null;
  const [scheme, token] = header.split(/\s+/, 2);
  if (!token || scheme.toLowerCase() !== "bearer") return null;
  return token.trim() || null;
}

/**
 * Verifies the access token with Supabase Auth and admits the request.
 *
 * Verification is a live call rather than a local signature check on purpose: a signed-out or
 * deleted user's token stops working immediately instead of at expiry (docs/14 §5, §9).
 *
 * The default rate limit (120/min, docs/04 §8) is applied *here* rather than in each handler,
 * so a route added later is limited by construction rather than by remembering.
 */
export async function requireUser(req: Request, route: string): Promise<UserCtx> {
  const token = bearerToken(req);
  if (!token) throw new ApiError("UNAUTHENTICATED");

  const db = serviceClient();
  const { data, error } = await db.auth.getUser(token);
  if (error || !data?.user) throw new ApiError("UNAUTHENTICATED");

  const ctx: UserCtx = { db, userId: data.user.id, route };
  await enforceRateLimit(ctx.db, `route:${route}:u:${ctx.userId}`, 120, 60);
  return ctx;
}

// ─── the other kind of caller: a job ─────────────────────────────────────────

/**
 * Admits a request from the scheduler, and nothing else.
 *
 * The worker functions (`links-worker`, and `push-worker` when E06 lands) are driven by pg_cron
 * through pg_net, carrying the service key from a database setting (0016). They have no user, so
 * none of the pipeline above applies to them — and they must be unreachable from a device, since
 * a member who could POST to a worker could drain the notification outbox at will (docs/14 §8).
 *
 * The comparison is over SHA-256 digests rather than the raw strings. `===` on secrets returns
 * as soon as two bytes differ, which is a timing oracle that leaks the key a character at a time
 * to anybody willing to make enough requests. Digesting first makes every comparison the same
 * length and the same cost, and a wrong guess reveals nothing about how nearly right it was.
 */
export async function requireServiceRole(req: Request): Promise<void> {
  const token = bearerToken(req);
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!token || !key) throw new ApiError("UNAUTHENTICATED");

  const digest = async (value: string): Promise<Uint8Array> =>
    new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)));
  const [a, b] = await Promise.all([digest(token), digest(key)]);

  let difference = 0;
  for (let i = 0; i < a.length; i += 1) difference |= a[i] ^ b[i];
  if (difference !== 0) throw new ApiError("UNAUTHENTICATED");
}

// ─── 2. profile ──────────────────────────────────────────────────────────────

export async function requireProfile(ctx: UserCtx): Promise<ProfileCtx> {
  const { data, error } = await ctx.db
    .from("profiles")
    .select("id, display_name")
    .eq("id", ctx.userId)
    .maybeSingle();
  if (error) throw dbFailure("requireProfile", error);
  if (!data) throw new ApiError("NO_PROFILE");
  return { ...ctx, displayName: data.display_name };
}

// ─── 3. membership ───────────────────────────────────────────────────────────

/** Resolves the caller's one active membership (ADR-005). Takes no group parameter, by
 *  design. An ex-member's still-valid token lands here and gets `NO_GROUP` (docs/14 §5). */
export async function requireMembership(ctx: ProfileCtx): Promise<MemberCtx> {
  const { data, error } = await ctx.db
    .from("memberships")
    .select("group_id, role, joined_at")
    .eq("user_id", ctx.userId)
    .is("left_at", null)
    .maybeSingle();
  if (error) throw dbFailure("requireMembership", error);
  if (!data) throw new ApiError("NO_GROUP");
  return { ...ctx, groupId: data.group_id, role: data.role, joinedAt: data.joined_at };
}

export function requireAdmin(ctx: MemberCtx): MemberCtx {
  if (ctx.role !== "admin") throw new ApiError("NOT_ADMIN");
  return ctx;
}

// ─── 4. phase ────────────────────────────────────────────────────────────────

/** The round's stored state is the authority — never a comparison against the clock. A round
 *  is `revealed` because `tick_rounds()` said so (docs/02 §2), not because 20:00 has passed. */
export function requirePhase(
  round: { state: RoundState },
  allowed: readonly RoundState[],
): void {
  if (allowed.includes(round.state)) return;
  if (round.state === "voided") throw new ApiError("ROUND_VOIDED");
  throw new ApiError("WRONG_PHASE", { state: round.state });
}

// ─── submitter guard ─────────────────────────────────────────────────────────

/** Only submitters may guess, enforced server-side (CLAUDE.md §2.3). Reads one row keyed by
 *  `(round_id, user_id)`: the caller's own. It never counts, so its cost cannot vary with how
 *  many other people have submitted (docs/14 §3, the timing channel). */
export async function requireSubmitter(ctx: MemberCtx, roundId: string): Promise<void> {
  const { data, error } = await ctx.db
    .from("submissions")
    .select("id")
    .eq("round_id", roundId)
    .eq("user_id", ctx.userId)
    .maybeSingle();
  if (error) throw dbFailure("requireSubmitter", error);
  if (!data) throw new ApiError("NOT_A_SUBMITTER");
}

// ─── joined-in-time guard ────────────────────────────────────────────────────

export function requireJoinedBefore(ctx: MemberCtx, revealsAt: string): void {
  if (new Date(ctx.joinedAt).getTime() >= new Date(revealsAt).getTime()) {
    throw new ApiError("JOINED_LATE");
  }
}

// ─── rate limiting ───────────────────────────────────────────────────────────
// docs/04 §8. Buckets are keyed by user id or by hashed IP — **never by group**. A
// group-scoped counter would let one member detect another member's activity by watching for
// throttling, which is a genuine side channel on the blind window.

export async function enforceRateLimit(
  db: Db,
  bucket: string,
  limit: number,
  windowSeconds: number,
): Promise<void> {
  const { data, error } = await db.rpc("consume_rate_limit", {
    p_bucket: bucket,
    p_limit: limit,
    p_window: `${windowSeconds} seconds`,
  });
  if (error) throw dbFailure("consume_rate_limit", error);
  const retryAfterSeconds = data as number;
  if (retryAfterSeconds > 0) throw new ApiError("RATE_LIMITED", { retryAfterSeconds });
}

/** A stable, non-reversible bucket key for an IP. We do not store IP addresses (docs/14 §9);
 *  we store a hash of one for at most the length of the rate-limit window. */
export async function ipBucket(prefix: string, ip: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(ip));
  const hex = Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return `${prefix}:ip:${hex.slice(0, 32)}`;
}
