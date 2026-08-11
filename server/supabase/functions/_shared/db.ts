// _shared/db.ts — the service-role client. docs/01 §2, docs/14 §4.
//
// Edge Functions hold the service role, which bypasses RLS. That is deliberate and it is why
// **every handler does its own authorization** (docs/14 §4): RLS is the second lock, not the
// only one. Nothing in this file authorizes anything; that is `auth.ts`.

import { createClient, type PostgrestError, type SupabaseClient } from "npm:@supabase/supabase-js@2.58.0";

export type Db = SupabaseClient;

/** Created once per invocation (tasks/E02-01) — not a module-level singleton, so a client
 *  can never outlive the request whose token it was built for. */
export function serviceClient(): Db {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw new Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set for the function to run");
  }
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
}

export const UNIQUE_VIOLATION = "23505";
/** Raised by `create_group()` when the caller already holds an active membership (ADR-005). */
export const ALREADY_IN_GROUP = "BD001";

export function isUniqueViolation(error: PostgrestError | null): boolean {
  return error?.code === UNIQUE_VIOLATION;
}

/**
 * A database error the handler has no specific answer for. It becomes `INTERNAL` upstream;
 * the Postgrest message is logged, never returned — it can quote column values (docs/14 §9).
 */
export function dbFailure(where: string, error: PostgrestError): Error {
  console.error(`db ${where}: ${error.code ?? "?"} ${error.message}`);
  return new Error(`db failure in ${where}`);
}
