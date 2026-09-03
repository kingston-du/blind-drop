// _shared/db.ts — the service-role client. docs/01 §2, docs/14 §4.
//
// Edge Functions hold the service role, which bypasses RLS. That is deliberate and it is why
// **every handler does its own authorization** (docs/14 §4): RLS is the second lock, not the
// only one. Nothing in this file authorizes anything; that is `auth.ts`.

import {
  createClient,
  type PostgrestError,
  type SupabaseClient,
} from "npm:@supabase/supabase-js@2.58.0";

export type Db = SupabaseClient;

/** Created once per invocation (tasks/E02-01) — not a module-level singleton, so a client
 *  can never outlive the request whose token it was built for. */
export function serviceClient(): Db {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw new Error(
      "SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set for the function to run",
    );
  }
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
}

export const UNIQUE_VIOLATION = "23505";
/** `memberships_circle_cap` (`20260818090000_circle_cap.sql`) — the caller is already at
 *  ADR-011's cap. Raised by both `POST /groups` and `POST /groups/join`, since both insert a
 *  membership through the same trigger. */
export const CIRCLE_LIMIT_REACHED = "BD002";
/** `upsert_submission` (`20260819090000_track_reuse_overlap.sql`) — the caller already used
 *  this track_key tonight in a different circle that shares another active member with this
 *  one. tasks/E18-03, docs/02 §3. */
export const TRACK_ALREADY_USED = "BD003";
/** `accept_invitation` / `decline_invitation` (`20260819100000_invitations.sql`) — the
 *  invitation named does not exist for this caller, or is no longer pending (already
 *  resolved, or lazily expired on this attempt). tasks/E20-01. */
export const INVITATION_GONE = "BD004";

export function isUniqueViolation(error: PostgrestError | null): boolean {
  return error?.code === UNIQUE_VIOLATION;
}

export function isCircleLimitReached(error: PostgrestError | null): boolean {
  return error?.code === CIRCLE_LIMIT_REACHED;
}

export function isTrackAlreadyUsed(error: PostgrestError | null): boolean {
  return error?.code === TRACK_ALREADY_USED;
}

export function isInvitationGone(error: PostgrestError | null): boolean {
  return error?.code === INVITATION_GONE;
}

/**
 * A database error the handler has no specific answer for. It becomes `INTERNAL` upstream;
 * the Postgrest message is logged, never returned — it can quote column values (docs/14 §9).
 */
export function dbFailure(where: string, error: PostgrestError): Error {
  console.error(`db ${where}: ${error.code ?? "?"} ${error.message}`);
  return new Error(`db failure in ${where}`);
}

// ─── reading a whole table, when the whole table is the answer — `E40-01` ────
//
// PostgREST applies `max_rows` (server/supabase/config.toml, 1000) to **every** select that does
// not ask for a range, service role included. There is no error and no flag on the response: a
// query that should have returned 4000 rows returns 1000 of them, in whatever order the planner
// felt like, and the aggregation on top computes a confident wrong answer that gets worse the
// longer a circle plays. `E40-01` found this in Insights, where the numerators quietly stopped
// growing at ~33 scored nights while the denominators did not.
//
// So an aggregation that needs the whole history pages for it. The caller supplies the query for
// one page **and a stable `.order(…)`** — without an ordering, two pages can overlap or skip, and
// the result is wrong in a way that looks exactly like the bug this replaces.

/** PostgREST's `max_rows`. A page asks for exactly this many, so a short page means the last one. */
export const MAX_ROWS = 1000;

/** Enough pages for any history this product can produce; past it, something is looping. */
const MAX_PAGES = 500;

type PageResult<T> = PromiseLike<{ data: T[] | null; error: PostgrestError | null }>;

/**
 * Every row a query matches, read `MAX_ROWS` at a time. `where` names the call site for
 * `dbFailure`, exactly as an unpaged read would.
 */
export async function selectAllRows<T>(
  where: string,
  page: (from: number, to: number) => PageResult<T>,
): Promise<T[]> {
  const rows: T[] = [];
  for (let index = 0; index < MAX_PAGES; index += 1) {
    const from = index * MAX_ROWS;
    const { data, error } = await page(from, from + MAX_ROWS - 1);
    if (error) throw dbFailure(where, error);
    const batch = data ?? [];
    rows.push(...batch);
    // A short page is the last page. An exactly-full one may or may not be, so it costs one
    // more round trip to find out — the alternative is guessing, which is the original bug.
    if (batch.length < MAX_ROWS) return rows;
  }
  throw new Error(`runaway pagination in ${where}: more than ${MAX_PAGES * MAX_ROWS} rows`);
}
