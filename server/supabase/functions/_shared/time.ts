// _shared/time.ts — server time and calendar arithmetic. docs/02 §1, docs/04 §1.
//
// The server owns time (CLAUDE.md §2.2). Every response carries `server_now` so the client
// can hold a clock offset and render countdowns from it. Nothing here reads a client-supplied
// timestamp.

export type RoundState = "open" | "revealed" | "scored" | "voided";

/** The single reading of the clock for one request. Pass it down; do not re-read it. */
export function serverNow(): Date {
  return new Date();
}

/**
 * RFC 3339 UTC with a `Z`, truncated to whole seconds (docs/04 §1).
 *
 * Postgres hands timestamptz back as `2026-08-10T16:11:02.184362+00:00`; every timestamp
 * that reaches a client goes through here first, so the wire format is one format. Seconds
 * precision keeps every timestamp the same width, which the leak audit's byte-length
 * invariant (docs/14 §3) is happier with than a variable-length fraction.
 */
export function rfc3339(t: Date | string): string {
  const d = t instanceof Date ? t : new Date(t);
  if (Number.isNaN(d.getTime())) throw new TypeError(`not a timestamp: ${String(t)}`);
  return `${d.toISOString().slice(0, 19)}Z`;
}

/** The calendar date at `at` in `timezone`, as `YYYY-MM-DD`. docs/02 §1: rounds are keyed by
 *  group-local date, never by a fixed UTC hour. `timezone` must already be validated. */
export function localDate(timezone: string, at: Date): string {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(at);
  const get = (type: Intl.DateTimeFormatPartTypes) =>
    parts.find((p) => p.type === type)?.value ?? "";
  return `${get("year")}-${get("month")}-${get("day")}`;
}

/** The day after a `YYYY-MM-DD` date, as `YYYY-MM-DD`. Calendar arithmetic only — no clock. */
export function nextDate(date: string): string {
  const [y, m, d] = date.split("-").map(Number);
  const next = new Date(Date.UTC(y, m - 1, d + 1));
  return next.toISOString().slice(0, 10);
}

/** True once `at` has arrived. Used for phase *predicates*, never for phase *transitions* —
 *  those belong to `tick_rounds()` (docs/02 §2). A handler reads `rounds.state`; it may use
 *  this only to explain a state it has already been given. */
export function hasPassed(at: Date | string, now: Date): boolean {
  const t = at instanceof Date ? at : new Date(at);
  return now.getTime() >= t.getTime();
}
