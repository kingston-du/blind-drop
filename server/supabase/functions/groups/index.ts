// groups/index.ts — the group and its roster. docs/04 §3, docs/02 §1, docs/14 §4, ADR-011.
//
//   POST  /groups                              create a group, become its admin
//   POST  /groups/join                         join by invite code
//   POST  /groups/current/invitations           invite a user_id to the caller's default circle
//   POST  /groups/:group_id/invitations          the same, for a named circle
//   GET   /groups/invitations                    the caller's own pending invitations, any circle
//   POST  /groups/invitations/:invitation_id/accept   accept — creates the membership (E20-01)
//   POST  /groups/invitations/:invitation_id/decline  decline — terminal, re-invitable
//   GET   /groups/people-you-played-with             caller's shared-group people, newest first
//   GET   /groups                              every circle the caller holds, and their own
//                                               next move in each (`E18-02`) — the switcher
//   GET   /groups/current                      the group and its roster — oldest circle
//   GET   /groups/:group_id                    the same, for a named circle
//   PATCH /groups/current                      admin only; name and reveal_hour
//   PATCH /groups/:group_id                    the same, for a named circle
//   GET   /groups/current/standings            all-time, ranked one way and not the other
//   GET   /groups/:group_id/standings          the same, for a named circle
//   GET   /groups/:group_id/members/:user_id/profile   scored history and pairwise reads only
//   GET   /groups/:group_id/insights                    scored circle relationships only
//   GET   /groups/current/record                the archive, newest night first, paginated
//   GET   /groups/:group_id/record              the same, for a named circle
//   GET   /groups/current/record/export?service=  the ordered track list, for the client to
//                                               turn into a playlist with its own credentials
//   GET   /groups/:group_id/record/export?service=  the same, for a named circle
//   POST  /groups/current/leave                set left_at
//   POST  /groups/:group_id/leave              the same, for a named circle
//   PATCH /groups/:group_id/members/:user_id   admin only; promote or demote an active member
//   DELETE /groups/:group_id/members/:user_id  admin only; remove an active member
//
// **Every `:group_id` route proves membership of that id before it does anything else**
// (`requireMembership`, ADR-011) — a non-member gets the same `NOT_FOUND` a fabricated id
// would. The `current` forms are compatibility: they resolve to the caller's oldest active
// circle (`requireDefaultMembership`) so the shipped app keeps working unmodified until `E19`
// gives it a switcher. Each pair shares one handler function; only the group resolution
// differs, so there is exactly one code path per route to review, not two.

import {
  ApiError,
  clientIp,
  int,
  noContent,
  ok,
  optional,
  parseBody,
  serveFunction,
  str,
} from "../_shared/http.ts";
import {
  activeMemberships,
  enforceRateLimit,
  ipBucket,
  type MemberCtx,
  type ProfileCtx,
  requireAdmin,
  requireDefaultMembership,
  requireMembership,
  requireProfile,
  requireUser,
} from "../_shared/auth.ts";
import {
  type Db,
  dbFailure,
  isCircleLimitReached,
  isInvitationGone,
  isUniqueViolation,
} from "../_shared/db.ts";
import {
  type CallerCircleState,
  circleSummaryDTO,
  earStandingDTO,
  type ExportTrackDTO,
  exportDTO,
  exportTrackDTO,
  type GroupDTO,
  groupDTO,
  groupPatchDTO,
  invitationDTO,
  knownPersonDTO,
  type MemberDTO,
  memberDTO,
  memberProfileDTO,
  type MemberProfileDTO,
  insightsDTO,
  type InsightsDTO,
  type ReadabilityBand,
  readabilityStandingDTO,
  type RecordDayDTO,
  recordDayDTO,
  recordDTO,
  type RecordEntryDTO,
  recordEntryDTO,
  type RosterMemberDTO,
  rosterMemberDTO,
  standingsDTO,
} from "../_shared/dto.ts";
import {
  confusionMinimumRounds,
  confusionPairs,
  type InsightGuessRow,
  wilsonLowerBound,
  wilsonUpperBound,
} from "../_shared/insights.ts";
import { generateInviteCode, normaliseInviteCode } from "../_shared/invite.ts";
import { localDate, nextDate, type RoundState, serverNow } from "../_shared/time.ts";

interface GroupRow {
  id: string;
  name: string;
  timezone: string;
  reveal_hour: number;
  invite_code: string;
}
const GROUP_COLUMNS = "id, name, timezone, reveal_hour, invite_code";

/** The active roster: `user_id`, `display_name` and `role` — the last is `E21-01`'s addition,
 *  static circle governance rather than participation, so it carries none of `joined_at`'s
 *  leak risk (docs/14 §3). Still no counts, no ordering derived from activity. */
async function roster(db: Db, groupId: string): Promise<RosterMemberDTO[]> {
  const { data: memberships, error: membershipError } = await db
    .from("memberships")
    .select("user_id, role")
    .eq("group_id", groupId)
    .is("left_at", null);
  if (membershipError) throw dbFailure("groups.roster.memberships", membershipError);

  const roleByUserId = new Map(memberships.map((m) => [m.user_id as string, m.role as "member" | "admin"]));
  const ids = memberships.map((m) => m.user_id);
  if (ids.length === 0) return [];

  const { data: profiles, error: profileError } = await db
    .from("profiles")
    .select("id, display_name")
    .in("id", ids)
    .order("display_name", { ascending: true })
    .order("id", { ascending: true });
  if (profileError) throw dbFailure("groups.roster.profiles", profileError);

  return profiles.map((p) =>
    rosterMemberDTO({
      user_id: p.id,
      display_name: p.display_name,
      role: roleByUserId.get(p.id) ?? "member",
    })
  );
}

async function loadGroup(db: Db, groupId: string): Promise<GroupRow> {
  const { data, error } = await db
    .from("groups")
    .select(GROUP_COLUMNS)
    .eq("id", groupId)
    .maybeSingle();
  if (error) throw dbFailure("groups.load", error);
  if (!data) throw new ApiError("NOT_FOUND");
  return data;
}

async function currentGroupDTO(ctx: MemberCtx, group?: GroupRow): Promise<GroupDTO> {
  const row = group ?? (await loadGroup(ctx.db, ctx.groupId));
  return groupDTO(row, ctx.role === "admin", await roster(ctx.db, ctx.groupId));
}

/**
 * The local date of the first round that does not exist yet.
 *
 * A `reveal_hour` change never re-times a round that has already been created — `ensure_rounds`
 * is `on conflict do nothing` (docs/03 §4) — so the change lands the day after the last round
 * on the books, and the UI can say which day precisely (docs/02 §1, docs/11
 * `settings.hour.effective`).
 */
async function effectiveFrom(db: Db, group: GroupRow): Promise<string> {
  const { data, error } = await db
    .from("rounds")
    .select("local_date")
    .eq("group_id", group.id)
    .order("local_date", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) throw dbFailure("groups.effectiveFrom", error);

  const today = localDate(group.timezone, serverNow());
  if (!data) return today;
  return data.local_date >= today ? nextDate(data.local_date) : today;
}

// ─── the switcher — docs/04 §3, docs/02 §2, `E18-02` ─────────────────────────
// One request, answering for every circle the caller holds: its name, and the caller's own
// next move in it. Nothing here is shaped by anyone else's participation — every query below
// is keyed by the caller's own `user_id`, the same discipline `rounds/index.ts`'s header
// documents for the single-circle routes.

/**
 * The caller's own state in one circle's round today, and whether it needs them to do
 * something about it, or `null` if this circle has nothing to report yet. `docs/11` calls the
 * four live states `Drop a song`, `Sealed`, `Guess` and `Answers`; `voided` is a fifth answer
 * for a round that revealed nothing; see `CallerCircleState`.
 *
 * Deliberately not `currentRound`/`currentRoundResponse` from `rounds/index.ts`: those load a
 * card list, a name pool and a full guess sheet, which is far more than a switcher row needs
 * and — for up to `E18-01`'s cap of circles, all resolved for one request — real cost to skip.
 *
 * `ensureRounds` is a caller-supplied, request-scoped once-only trigger rather than an
 * unconditional `db.rpc("ensure_rounds")` here: that RPC sweeps every group in the database
 * (`0004_round_lifecycle.sql`), not just this one, so calling it once per circle that happens
 * to be missing today's round would fire the whole sweep up to ADR-011's cap times,
 * concurrently, for a single request. `myCirclesResponse` builds one and hands it to every
 * circle; only the first miss actually runs it.
 *
 * The round looked up is not necessarily dated the caller's actual calendar `today`.
 * `ensure_rounds()` refuses to create a round whose reveal has already passed for the day it
 * would cover (`0004_round_lifecycle.sql`'s `where d.reveals_at > v_now`), which is exactly
 * what happens to a circle created — or simply first read — after its own `reveal_hour`: there
 * is a round for tomorrow, and none for today, ever, until tomorrow's own calendar date
 * arrives. A lookup pinned to `local_date = today` misses that row outright and the circle
 * silently drops out of the switcher for the rest of the day, which is the bug `E18-02b` fixes:
 * the query below takes the earliest round dated `today` or later, matching whichever of
 * `ensure_rounds()`'s two candidate dates it actually materialised. An ordinary circle with
 * today's round still open, revealed or scored gets that row back, exactly as before, because
 * it sorts before tomorrow's; only a circle with nothing dated today falls through to
 * tomorrow's row, and reports it — correctly, since that IS the circle's live round, just not
 * one dated today.
 *
 * `null` still covers the one case no sweep can produce a row for: a group whose timezone
 * `ensure_rounds()` cannot evaluate (`0004_round_lifecycle.sql`'s per-group exception guard).
 * `GET /rounds/current` answers that with a scoped `NOT_FOUND` for the one circle asked about;
 * the switcher cannot 404 one row out of a list, so it leaves the circle out rather than
 * failing the whole request over a single member's gap. `docs/04`'s example still lists the
 * circle by id from `activeMemberships`, so a caller that later paginates or counts membership
 * separately is not misled — only the switcher row is missing, briefly.
 *
 * Demo-group ticking (`demo_tick`) is included, unlike `ensure_rounds`: `rounds/index.ts` runs
 * it before every read because `tick_rounds()` never advances a demo round on its own
 * (`20260815090500_demo_lifecycle.sql`), and skipping it here would leave a demo circle's row
 * stuck at whatever it last was until its own screen was opened directly.
 */
async function circleCallerState(
  db: Db,
  member: { groupId: string; userId: string; joinedAt: string; timezone: string; isDemo: boolean },
  ensureRounds: () => Promise<void>,
): Promise<{ myState: CallerCircleState; needsAction: boolean } | null> {
  const today = localDate(member.timezone, serverNow());

  // `.gte` + earliest-first, not `.eq`: see the doc comment above. `ensure_rounds()` may have
  // skipped today's local_date entirely and materialised only tomorrow's; ordering ascending
  // picks today's row when it exists (it always sorts first) and falls back to the next one
  // that does when it doesn't, which is the same round `effectiveFrom` would call current.
  const loadRound = async () => {
    const { data, error } = await db
      .from("rounds")
      .select("id, state, reveals_at, card_order")
      .eq("group_id", member.groupId)
      .gte("local_date", today)
      .order("local_date", { ascending: true })
      .limit(1)
      .maybeSingle();
    if (error) throw dbFailure("groups.myCircles.round", error);
    return data as
      | { id: string; state: RoundState; reveals_at: string; card_order: string[] | null }
      | null;
  };

  if (member.isDemo) {
    const { error } = await db.rpc("demo_tick", { p_group_id: member.groupId });
    if (error) throw dbFailure("groups.myCircles.demo_tick", error);
  }

  let round = await loadRound();
  if (!round && !member.isDemo) {
    await ensureRounds();
    round = await loadRound();
  }
  if (!round) return null;

  if (round.state === "voided") return { myState: "voided", needsAction: false };
  if (round.state === "scored") return { myState: "answers", needsAction: false };

  // Left: `open` and `revealed`, and both need the same fact — did the caller submit tonight?
  // One row, keyed by `(round_id, user_id)`, exactly as `rounds/index.ts`'s `mySubmission` is.
  const { data: submission, error: submissionError } = await db
    .from("submissions")
    .select("id")
    .eq("round_id", round.id)
    .eq("user_id", member.userId)
    .maybeSingle();
  if (submissionError) throw dbFailure("groups.myCircles.submission", submissionError);

  if (round.state === "open") {
    return submission
      ? { myState: "sealed", needsAction: false }
      : { myState: "drop", needsAction: true };
  }

  // revealed. `joinedLate` mirrors `rounds/index.ts`'s `cannotGuessReason`: joining after the
  // reveal means having no submission either, so a member who cannot guess always lands here
  // with `needs_action: false` — there is nothing for them to do about a sheet they were never
  // eligible to fill in.
  const joinedLate =
    new Date(member.joinedAt).getTime() >= new Date(round.reveals_at).getTime();
  if (joinedLate || !submission) return { myState: "guess", needsAction: false };

  const { count, error: guessError } = await db
    .from("guesses")
    .select("submission_id", { count: "exact", head: true })
    .eq("round_id", round.id)
    .eq("guesser_id", member.userId);
  if (guessError) throw dbFailure("groups.myCircles.guesses", guessError);

  const eligible = Math.max((round.card_order ?? []).length - 1, 0);
  return { myState: "guess", needsAction: (count ?? 0) < eligible };
}

/**
 * `GET /groups`'s whole body. Ordering is left to the client (`E18-02`'s checklist) — this
 * returns the caller's circles oldest-active-first, the same stable order `activeMemberships`
 * already establishes, and states no priority of its own.
 */
async function myCirclesResponse(ctx: ProfileCtx): Promise<Response> {
  const memberships = await activeMemberships(ctx);
  if (memberships.length === 0) return ok({ circles: [] });

  const groupIds = memberships.map((m) => m.groupId);
  const { data: groups, error } = await ctx.db
    .from("groups")
    .select("id, name, timezone, is_demo")
    .in("id", groupIds);
  if (error) throw dbFailure("groups.myCircles.groups", error);
  const groupById = new Map(groups.map((g) => [g.id, g]));

  // Shared across every circle in this request — see `circleCallerState`'s doc comment for why
  // a plain `db.rpc("ensure_rounds")` per circle would be a system-wide sweep run several times.
  let ensureRoundsOnce: Promise<void> | null = null;
  const ensureRounds = (): Promise<void> => {
    if (!ensureRoundsOnce) {
      ensureRoundsOnce = (async () => {
        const { error } = await ctx.db.rpc("ensure_rounds");
        if (error) throw dbFailure("groups.myCircles.ensure_rounds", error);
      })();
    }
    return ensureRoundsOnce;
  };

  const rows = await Promise.all(
    memberships.map(async (membership) => {
      const group = groupById.get(membership.groupId);
      if (!group) {
        throw new Error(
          `groups.myCircles.group: membership names group ${membership.groupId}, which has no row`,
        );
      }
      const state = await circleCallerState(
        ctx.db,
        {
          groupId: group.id,
          userId: ctx.userId,
          joinedAt: membership.joinedAt,
          timezone: group.timezone,
          isDemo: group.is_demo === true,
        },
        ensureRounds,
      );
      return state && circleSummaryDTO(group, state.myState, state.needsAction);
    }),
  );

  return ok({ circles: rows.filter((row) => row !== null) });
}

// ─── standings — docs/04 §4, docs/02 §4.2, §4.5 ──────────────────────────────

interface StandingRow {
  user_id: string;
  ear_all_time: number | null;
  ear_correct_total: number | null;
  ear_rounds: number;
  readability_all_time: number | null;
  band: ReadabilityBand;
}

/**
 * The group's all-time table, straight out of the `standings` view (0005).
 *
 * **Nothing here recomputes an average.** The pooled-ear / mean-readability asymmetry in
 * docs/02 §4.2 lives in SQL, and it is the kind of rule that a second implementation gets
 * subtly wrong — one `reduce` in the wrong place turns a mean of rates into a pooled ratio and
 * produces a number that is plausible, stable, and not the one the game is scored on. This
 * function sorts and ranks. It does not do arithmetic.
 */
async function standingRows(db: Db, groupId: string): Promise<StandingRow[]> {
  const { data, error } = await db
    .from("standings")
    .select("user_id, ear_all_time, ear_correct_total, ear_rounds, readability_all_time, band")
    .eq("group_id", groupId);
  if (error) throw dbFailure("groups.standings", error);
  return data as StandingRow[];
}

/** How many nights this group has actually played. Scored rounds only — `round_submitter_counts`
 *  holds exactly one row per scored round and excludes voided ones by construction, which is
 *  the same universe every rate on the page is computed over (docs/02 §4.2). */
async function roundsPlayed(db: Db, groupId: string): Promise<number> {
  const { count, error } = await db
    .from("round_submitter_counts")
    .select("round_id", { count: "exact", head: true })
    .eq("group_id", groupId);
  if (error) throw dbFailure("groups.roundsPlayed", error);
  return count ?? 0;
}

/**
 * Competition ranking: ties share a rank and the next rank skips it — 1, 2, 2, 4 (docs/04 §4).
 *
 * The comparison is exact equality on the rate rather than a tolerance. Both numbers came out
 * of the same `numeric` division at the same scale, so two people who genuinely tie produce the
 * same value and two people who do not differ by far more than a rounding error. A tolerance
 * here would invent ties that the arithmetic does not have.
 */
function ranked<T extends { ear_all_time: number }>(rows: T[]): { rank: number; row: T }[] {
  let rank = 0;
  let previous: number | null = null;
  return rows.map((row, index) => {
    if (previous === null || row.ear_all_time !== previous) rank = index + 1;
    previous = row.ear_all_time;
    return { rank, row };
  });
}

// ─── The Record — docs/04 §5, docs/06 §6 ─────────────────────────────────────
//
// The archive, and the export built from it. Both read the same two things — `scored` rounds
// and their submissions — and the reason that is one sentence rather than a filter is
// `round_submitter_counts` (0005), a view over `state = 'scored'` alone. Neither an `open`
// round nor a `voided` one is visible from here at all: there is no `state` column in either
// query below to get wrong, and a `voided` round in particular must never surface, because its
// songs were returned to their owners unseen and publishing them a day later would retroactively
// break the window they were sealed inside (CLAUDE.md §2.1, docs/04 §5).

const DEFAULT_RECORD_LIMIT = 50;
const MAX_RECORD_LIMIT = 100;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const LOCAL_DATE = /^\d{4}-\d{2}-\d{2}$/;

/** How many round ids go into one `in (…)` — a bound on the query string, not on the answer.
 *  The export walks the whole archive, and a group that has played for a year would otherwise
 *  put thirteen kilobytes of uuids in a URL. Every chunk is fetched; nothing is dropped. */
const ID_CHUNK = 60;

/**
 * The page cursor: base64url of `{"d":"<local_date>"}`, meaning *strictly older than this day*.
 *
 * A day, not a row offset, because the page boundary has to be a boundary the archive itself
 * has. An offset would shift under the caller the moment tonight's round scores, and the
 * second page would repeat or skip a night; a date names a place in the archive that a new
 * round at the top cannot move. It is opaque on the wire so that it stays a cursor rather than
 * becoming a date filter the client hand-writes — this is the only parameter that can select
 * *which* days come back, and it must not grow a second meaning.
 */
function encodeCursor(localDate: string): string {
  return btoa(JSON.stringify({ d: localDate }))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function decodeCursor(raw: string): string {
  try {
    const base64 = raw.replace(/-/g, "+").replace(/_/g, "/");
    const parsed = JSON.parse(atob(base64.padEnd(Math.ceil(base64.length / 4) * 4, "=")));
    const day = (parsed as { d?: unknown }).d;
    if (typeof day === "string" && LOCAL_DATE.test(day)) return day;
  } catch {
    // A cursor we did not mint is indistinguishable from one we did but mangled, and both are
    // INVALID_INPUT. Falls through.
  }
  throw new ApiError("INVALID_INPUT", { field: "cursor" });
}

/** `?limit=`, defaulting to 50 and capped at 100 (docs/04 §5). An out-of-range value is
 *  refused rather than clamped: a client asking for 500 has a bug, and quietly serving 100
 *  makes it look like the archive ended. */
function recordLimit(raw: string | null): number {
  if (raw === null || raw === "") return DEFAULT_RECORD_LIMIT;
  const value = Number(raw);
  if (!Number.isInteger(value) || value < 1 || value > MAX_RECORD_LIMIT) {
    throw new ApiError("INVALID_INPUT", { field: "limit" });
  }
  return value;
}

/**
 * `?member=`, the filter behind `record.filter.member` (docs/11).
 *
 * A user id from the caller is not a way into anyone's data here: it narrows a query that is
 * already keyed on the caller's own group and on `scored` rounds, so an id belonging to a
 * stranger selects nothing and an id belonging to an ex-member selects exactly the songs the
 * archive already shows everyone. It is checked for shape only, and an unknown id returns an
 * empty archive rather than `NOT_FOUND` — "that person is not in this group" is not an answer
 * this endpoint should be able to give (docs/14 §4).
 */
function memberFilter(raw: string | null): string | null {
  if (raw === null || raw === "") return null;
  if (!UUID.test(raw)) throw new ApiError("INVALID_INPUT", { field: "member" });
  return raw;
}

interface ArchiveRound {
  round_id: string;
  local_date: string;
  submitter_count: number;
}

/** Scored rounds of this group, newest first, optionally older than a cursor's day. `limit`
 *  is left off for the export, which is the whole archive by definition. */
async function archiveRounds(
  db: Db,
  groupId: string,
  before: string | null,
  limit?: number,
): Promise<ArchiveRound[]> {
  let query = db
    .from("round_submitter_counts")
    .select("round_id, local_date, submitter_count")
    .eq("group_id", groupId)
    .order("local_date", { ascending: false });
  if (before !== null) query = query.lt("local_date", before);
  if (limit !== undefined) query = query.limit(limit);

  const { data, error } = await query;
  if (error) throw dbFailure("groups.record.rounds", error);
  return data as ArchiveRound[];
}

/** Display names for a set of ids, including people who have left. The Record keeps its
 *  attribution (docs/02 §3) — the night happened — so this reads `profiles` rather than the
 *  roster, and a deleted account arrives already anonymised in place (docs/03 §6). */
async function namesByIds(db: Db, ids: string[]): Promise<Map<string, MemberDTO>> {
  if (ids.length === 0) return new Map();
  const { data, error } = await db
    .from("profiles")
    .select("id, display_name")
    .in("id", ids);
  if (error) throw dbFailure("groups.record.profiles", error);
  return new Map(
    data.map((p) => [p.id as string, memberDTO({ user_id: p.id, display_name: p.display_name })]),
  );
}

/**
 * The songs of a set of rounds, grouped by round and sorted within a night by name.
 *
 * Name order, not submission order: `created_at` on a submission is when somebody sealed, and
 * an archive page that ordered by it would publish the one thing every `open`-phase payload in
 * this codebase refuses to — who was early and who was late (docs/14 §3). The night is over,
 * but the habit is the point: nothing outside a round's own results screen orders people by
 * what they did.
 */
async function archiveEntries(
  db: Db,
  roundIds: string[],
  member: string | null,
): Promise<Map<string, RecordEntryDTO[]>> {
  const rows: { round_id: string; user_id: string; track_meta: unknown }[] = [];
  for (let i = 0; i < roundIds.length; i += ID_CHUNK) {
    let query = db
      .from("submissions")
      .select("round_id, user_id, track_meta")
      .in("round_id", roundIds.slice(i, i + ID_CHUNK));
    if (member !== null) query = query.eq("user_id", member);
    const { data, error } = await query;
    if (error) throw dbFailure("groups.record.submissions", error);
    rows.push(...data);
  }

  const names = await namesByIds(db, [...new Set(rows.map((row) => row.user_id))]);
  const unknown = (userId: string): MemberDTO =>
    names.get(userId) ?? memberDTO({ user_id: userId, display_name: "" });

  const byRound = new Map<string, RecordEntryDTO[]>();
  for (const row of rows) {
    const entries = byRound.get(row.round_id) ?? [];
    entries.push(recordEntryDTO(unknown(row.user_id), row.track_meta));
    byRound.set(row.round_id, entries);
  }
  for (const entries of byRound.values()) {
    entries.sort((a, b) =>
      a.display_name.localeCompare(b.display_name) || a.user_id.localeCompare(b.user_id)
    );
  }
  return byRound;
}

/** The days of one page, in order, with their songs. Empty days are dropped — under a `member`
 *  filter most nights have nothing to show, and a day with an empty `entries` array would say
 *  "this person played and dropped nothing", which is not a thing that can happen. */
function daysWithEntries(
  rounds: ArchiveRound[],
  entries: Map<string, RecordEntryDTO[]>,
): RecordDayDTO[] {
  return rounds
    .map((round) => recordDayDTO(round, entries.get(round.round_id) ?? []))
    .filter((day) => day.entries.length > 0);
}

/**
 * How many nights fit on this page.
 *
 * `limit` counts *songs*, and a night is never split across pages — the cursor is a date, so
 * half a night has no cursor that could resume it. Nights are taken while their songs fit, and
 * the first one is always taken whether it fits or not, so a group larger than the requested
 * limit still turns the page instead of returning nothing forever.
 */
function fitPage(rounds: ArchiveRound[], limit: number, member: string | null): ArchiveRound[] {
  const chosen: ArchiveRound[] = [];
  let budget = limit;
  for (const round of rounds) {
    // Under a `member` filter a night contributes at most one song, and `submitter_count`
    // would over-count it by an order of magnitude.
    const cost = member === null ? round.submitter_count : 1;
    if (chosen.length > 0 && cost > budget) break;
    chosen.push(round);
    budget -= cost;
    if (budget <= 0) break;
  }
  return chosen;
}

// ─── the shared handlers ─────────────────────────────────────────────────────
// One function per route, called from both its `current`-shaped and its `:group_id`-shaped
// entry — the two differ only in how `ctx.groupId` was resolved, never in what happens after.

async function patchGroup(req: Request, ctx: MemberCtx): Promise<Response> {
  const body = await parseBody(req, {
    name: optional(str({ min: 1, max: 40 })),
    reveal_hour: optional(int({ min: 18, max: 21 })),
  });
  // `timezone` is immutable after creation (docs/04 §3). It is not in the schema above, so
  // sending it is an unknown key and fails with INVALID_INPUT naming the field — which is
  // exactly the answer the UI needs to show `settings.timezone.locked`.
  if (body.name === undefined && body.reveal_hour === undefined) {
    throw new ApiError("INVALID_INPUT", { field: "body" });
  }

  const patch: Record<string, string | number> = {};
  if (body.name !== undefined) {
    const name = body.name.trim();
    if (name.length === 0) throw new ApiError("INVALID_INPUT", { field: "name" });
    patch.name = name;
  }
  if (body.reveal_hour !== undefined) patch.reveal_hour = body.reveal_hour;

  const { data, error } = await ctx.db
    .from("groups")
    .update(patch)
    .eq("id", ctx.groupId)
    .select(GROUP_COLUMNS)
    .single();
  if (error) throw dbFailure("groups.patch", error);

  const group = data as GroupRow;
  return ok(
    groupPatchDTO(
      await currentGroupDTO(ctx, group),
      body.reveal_hour === undefined ? null : await effectiveFrom(ctx.db, group),
    ),
  );
}

// docs/04 §4. Two lists that deliberately do not have the same shape.
//
// **Best Ear is ranked. Readability is not, and carries no `rank` field.** docs/02 §4.5 makes
// that a product rule rather than a presentation preference: guessing well is a scoreboard,
// being hard to read is a trait, and low readability is its own kind of win. The reason the
// rule is enforced *here*, by not sending the field, is that a client which receives a rank
// will render it — someone will reasonably assume a field that exists is meant to be shown.
// The readability array is sorted descending purely so the list is stable between refreshes.
//
// Safe in every phase. Every number on it comes from `scored` rounds only, so nothing here
// moves while tonight's round is open — the standings a member reads at 19:00 are the same
// ones they read at 09:00, and a member watching them for a change learns nothing (docs/14
// §3).
async function standingsForGroup(ctx: MemberCtx): Promise<Response> {
  const [rows, played, members] = await Promise.all([
    standingRows(ctx.db, ctx.groupId),
    roundsPlayed(ctx.db, ctx.groupId),
    roster(ctx.db, ctx.groupId),
  ]);

  // Scoped to the active roster. Someone who left keeps their attribution in The Record and
  // in every past round's results — the rounds happened, and their guesses still count toward
  // everyone else's readability — but a leaderboard is about the room as it is now, and a
  // departed member sitting at rank 2 forever is a scoreline nobody can respond to. See the
  // owner-approved resolution in tasks/E05.
  const byId = new Map(rows.map((row) => [row.user_id, row]));
  const present = members
    .map((member) => ({ member, row: byId.get(member.user_id) }))
    .filter((entry): entry is { member: RosterMemberDTO; row: StandingRow } => entry.row !== undefined);

  // A member with no ear at all — every round they played, they assigned nothing — is absent
  // from Best Ear rather than ranked last with a dash. docs/02 §4.1 draws that line for a
  // single round and it holds all the way up: never guessing is not the same as guessing
  // badly, and the leaderboard is the one surface where the difference would read as a score.
  const earRows = present
    .filter((entry) => entry.row.ear_all_time !== null)
    .sort((a, b) =>
      b.row.ear_all_time! - a.row.ear_all_time! ||
      a.member.display_name.localeCompare(b.member.display_name) ||
      a.member.user_id.localeCompare(b.member.user_id)
    );

  const bestEar = ranked(
    earRows.map((entry) => ({ ...entry, ear_all_time: entry.row.ear_all_time! })),
  )
    .map(({ rank, row }) =>
      earStandingDTO(rank, row.member, {
        ear_all_time: row.ear_all_time,
        ear_correct_total: row.row.ear_correct_total ?? 0,
      })
    );

  const readability = present
    .filter((entry) => entry.row.readability_all_time !== null)
    .sort((a, b) =>
      b.row.readability_all_time! - a.row.readability_all_time! ||
      a.member.display_name.localeCompare(b.member.display_name) ||
      a.member.user_id.localeCompare(b.member.user_id)
    )
    .map((entry) =>
      readabilityStandingDTO(entry.member, {
        readability_all_time: entry.row.readability_all_time!,
        band: entry.row.band,
      })
    );

  return ok(standingsDTO(played, bestEar, readability));
}

// docs/04 §5. The archive: every night this group has finished, newest first, grouped by the
// group-local date it was played on.
//
// Safe in every phase for the same reason the standings are: it is a function of `scored`
// rounds only, so nothing on it moves while tonight's round is in flight. A member who
// refreshes The Record all evening watching for it to grow sees exactly what they saw at
// 09:00 — and at 22:00, when tonight's round scores, it grows by a whole night at once for
// everybody, which is a fact about the clock rather than about any person (docs/14 §3).
async function recordForGroup(req: Request, ctx: MemberCtx): Promise<Response> {
  const params = new URL(req.url).searchParams;
  const limit = recordLimit(params.get("limit"));
  const member = memberFilter(params.get("member"));
  const rawCursor = params.get("cursor");
  const before = rawCursor === null || rawCursor === "" ? null : decodeCursor(rawCursor);

  // One more night than could possibly fit, which is what makes `next_cursor` honest: a
  // cursor is sent when a night was left behind, and withheld when the archive ran out.
  // Every scored round holds at least three songs (docs/02 §2, below that it voids), so
  // `limit + 1` nights always over-covers a budget of `limit` songs — and under a `member`
  // filter, where a night is worth one song, it over-covers it exactly.
  const planned = await archiveRounds(ctx.db, ctx.groupId, before, limit + 1);
  const page = fitPage(planned, limit, member);
  const more = planned.length > page.length;

  const entries = await archiveEntries(ctx.db, page.map((round) => round.round_id), member);
  const cursor = more && page.length > 0 ? encodeCursor(page[page.length - 1].local_date) : null;
  return ok(recordDTO(daysWithEntries(page, entries), cursor));
}

// ─── member profiles — E24-02 ───────────────────────────────────────────────
//
// A profile is a lens on finished play, never a second results route. Its score views and
// archive readers all exclude open, revealed and voided rounds by construction (0005_scoring).

interface ProfileScoreRow {
  round_id: string;
}

async function profileScores(db: Db, groupId: string, userId: string): Promise<ProfileScoreRow[]> {
  const { data, error } = await db
    .from("round_scores")
    .select("round_id")
    .eq("group_id", groupId)
    .eq("user_id", userId);
  if (error) throw dbFailure("groups.profile.scores", error);
  return data as ProfileScoreRow[];
}

/** The one direction of "read" that a profile can state honestly: the caller's correct reads
 * of the other person's actual cards. A shared scored round is one opportunity; unanswered
 * cards remain in the denominator, so this cannot quietly turn two guesses into 100%. */
async function pairwiseRead(
  db: Db,
  groupId: string,
  guesserId: string,
  cardOwnerId: string,
): Promise<{ correct: number; possible: number }> {
  const [guesserRows, ownerRows] = await Promise.all([
    profileScores(db, groupId, guesserId),
    profileScores(db, groupId, cardOwnerId),
  ]);
  const guesserRounds = new Set(guesserRows.map((row) => row.round_id));
  const shared = ownerRows.filter((row) => guesserRounds.has(row.round_id));
  if (shared.length === 0) return { correct: 0, possible: 0 };

  const { data, error } = await db
    .from("guess_results")
    .select("is_correct")
    .in("round_id", shared.map((row) => row.round_id))
    .eq("guesser_id", guesserId)
    .eq("card_owner_id", cardOwnerId);
  if (error) throw dbFailure("groups.profile.pairwise", error);
  return {
    correct: (data as { is_correct: boolean }[]).filter((row) => row.is_correct).length,
    possible: shared.length,
  };
}

async function profileForMember(ctx: MemberCtx, userId: string): Promise<Response> {
  const members = await roster(ctx.db, ctx.groupId);
  const target = members.find((member) => member.user_id === userId);
  if (!target) throw new ApiError("NOT_FOUND");

  const [scores, standings, rounds] = await Promise.all([
    profileScores(ctx.db, ctx.groupId, userId),
    standingRows(ctx.db, ctx.groupId),
    // A member may have missed the most recent few nights. Read the scored archive first and
    // then take *their* five songs, rather than accidentally calling a shorter list "recent".
    archiveRounds(ctx.db, ctx.groupId, null),
  ]);
  const entries = await archiveEntries(ctx.db, rounds.map((round) => round.round_id), userId);
  const recentTracks = rounds.flatMap((round) =>
    (entries.get(round.round_id) ?? []).map((entry) => ({ local_date: round.local_date, track: entry.track })),
  ).slice(0, 5);
  const standing = standings.find((row) => row.user_id === userId);

  const [youReadThem, theyReadYou] = userId === ctx.userId
    ? [null, null]
    : await Promise.all([
      pairwiseRead(ctx.db, ctx.groupId, ctx.userId, userId),
      pairwiseRead(ctx.db, ctx.groupId, userId, ctx.userId),
    ]);

  const profile: MemberProfileDTO = {
    member: memberDTO(target),
    // The SQL view owns the pooled-ear / mean-readability asymmetry. Do not average the round
    // values here: it would look plausible while silently changing both product definitions.
    ear: { value: standing?.ear_all_time ?? null, samples: standing?.ear_rounds ?? 0 },
    readability: { value: standing?.readability_all_time ?? null, samples: scores.length },
    drop_count: scores.length,
    recent_tracks: recentTracks,
    you_read_them: youReadThem,
    they_read_you: theyReadYou,
  };
  return ok(memberProfileDTO(profile));
}

// ─── Insights — E25-01 ─────────────────────────────────────────────────────
//
// This is deliberately not a new score. It is a small set of views over the same scored-only
// guess results that make profiles' pairwise reads. The server keeps the aggregation here so a
// client never receives a circle's raw guesses, and so an `open` round cannot become visible by
// accident when a later screen adds a field.

interface InsightScoreRow {
  round_id: string;
  user_id: string;
}

interface DirectedInsight {
  member: MemberDTO;
  correct: number;
  possible: number;
  lower_bound: number;
  upper_bound: number;
}

const MUTUAL_PAIR_LIMIT = 3;
const CONFUSION_PAIR_LIMIT = 3;
// `E28-06`, amendment A1: the test stage shows the confusion lens from the first wrong guess.
// Restore before public beta by dropping this flag and its one call site below.
const CONFUSION_GATE_ENABLED = false;

function relationshipKey(from: string, to: string): string {
  return `${from}:${to}`;
}

function compareMembers(a: MemberDTO, b: MemberDTO): number {
  return a.display_name.localeCompare(b.display_name) || a.user_id.localeCompare(b.user_id);
}

/// `E28-07`: ranked by the Wilson lower bound, not the raw rate — a well-supported 8-of-12
/// always outranks a thin 3-of-4. Ties (equal bound) fall to the larger sample, per the owner:
/// whatever is tied, more history ranks first.
function compareReadDescending(a: DirectedInsight, b: DirectedInsight): number {
  return b.lower_bound - a.lower_bound || b.possible - a.possible || compareMembers(a.member, b.member);
}

async function insightsForGroup(ctx: MemberCtx): Promise<Response> {
  const members = (await roster(ctx.db, ctx.groupId)).map(memberDTO).sort(compareMembers);
  const memberIDs = new Set(members.map((member) => member.user_id));
  const memberByID = new Map(members.map((member) => [member.user_id, member]));

  const { data: scoreRows, error: scoreError } = await ctx.db
    .from("round_scores")
    .select("round_id, user_id")
    .eq("group_id", ctx.groupId)
    .in("user_id", members.map((member) => member.user_id));
  if (scoreError) throw dbFailure("groups.insights.scores", scoreError);

  const roundsByUser = new Map<string, Set<string>>();
  for (const row of scoreRows as InsightScoreRow[]) {
    const rounds = roundsByUser.get(row.user_id) ?? new Set<string>();
    rounds.add(row.round_id);
    roundsByUser.set(row.user_id, rounds);
  }
  const roundIDs = [...new Set((scoreRows as InsightScoreRow[]).map((row) => row.round_id))];

  const correctByDirection = new Map<string, number>();
  let guessRows: InsightGuessRow[] = [];
  if (roundIDs.length > 0) {
    const { data, error: guessError } = await ctx.db
      .from("guess_results")
      .select("guesser_id, card_owner_id, guessed_user_id, is_correct")
      .in("round_id", roundIDs);
    if (guessError) throw dbFailure("groups.insights.guesses", guessError);
    guessRows = data as InsightGuessRow[];
    for (const row of guessRows) {
      // `round_id` confines the source query to this circle; this roster check additionally
      // omits former members, because Insights is about the current room rather than its archive.
      if (!row.is_correct || !memberIDs.has(row.guesser_id) || !memberIDs.has(row.card_owner_id)) continue;
      const key = relationshipKey(row.guesser_id, row.card_owner_id);
      correctByDirection.set(key, (correctByDirection.get(key) ?? 0) + 1);
    }
  }

  // Confusion needs more history than a directed read: it is a matrix of actual owners and
  // named members, and a single odd evening can otherwise make a pair look like a pattern.
  // The gate applies to the whole surface, never individual pairs, so an empty cell does not
  // become an accidental claim about two people while the rest of the matrix is still thin.
  const minimumConfusionRounds = confusionMinimumRounds(members.length);
  const visibleConfusions = (!CONFUSION_GATE_ENABLED || roundIDs.length >= minimumConfusionRounds)
    ? confusionPairs(guessRows, memberByID, CONFUSION_PAIR_LIMIT)
    : [];

  const directed = (from: string, to: string): DirectedInsight | null => {
    const target = memberByID.get(to);
    if (!target || from === to) return null;
    const sourceRounds = roundsByUser.get(from) ?? new Set<string>();
    const targetRounds = roundsByUser.get(to) ?? new Set<string>();
    let possible = 0;
    for (const roundID of sourceRounds) if (targetRounds.has(roundID)) possible += 1;
    if (possible === 0) return null;
    const correct = correctByDirection.get(relationshipKey(from, to)) ?? 0;
    return {
      member: target,
      correct,
      possible,
      lower_bound: wilsonLowerBound(correct, possible),
      upper_bound: wilsonUpperBound(correct, possible),
    };
  };

  // Full lists, not a single best (`E28-07`) — the client derives both headline cards and each
  // one's tap-through leaderboard off these, sorted by whichever bound the stat calls for.
  const yourReads = members
    .flatMap((member) => {
      const read = directed(ctx.userId, member.user_id);
      return read ? [read] : [];
    })
    .sort(compareReadDescending);
  const readsYou = members
    .flatMap((member) => {
      const read = directed(member.user_id, ctx.userId);
      // `directed` names its target, which is the caller in this direction. The insight needs
      // the person doing the reading, or the UI would claim that the caller knows themselves.
      return read ? [{ ...read, member }] : [];
    })
    .sort(compareReadDescending);

  const mutualRecognition: { members: MemberDTO[]; correct: number; possible: number }[] = [];
  const mutualMisses: { members: MemberDTO[]; correct: number; possible: number }[] = [];
  for (let first = 0; first < members.length; first += 1) {
    for (let second = first + 1; second < members.length; second += 1) {
      const left = directed(members[first].user_id, members[second].user_id);
      const right = directed(members[second].user_id, members[first].user_id);
      if (!left || !right) continue;
      const pair = {
        members: [members[first], members[second]],
        correct: left.correct + right.correct,
        possible: left.possible + right.possible,
      };
      if (left.correct > 0 && right.correct > 0) mutualRecognition.push(pair);
      if (left.correct === 0 && right.correct === 0) mutualMisses.push(pair);
    }
  }
  // `E28-07`: the Wilson lower bound again, with the same volume tie-break — the owner's "ties
  // rank on volume" rule applies everywhere a stat is ranked, mutual pairs included.
  const comparePair = (a: { members: MemberDTO[]; correct: number; possible: number },
                       b: { members: MemberDTO[]; correct: number; possible: number }): number =>
    wilsonLowerBound(b.correct, b.possible) - wilsonLowerBound(a.correct, a.possible)
      || b.possible - a.possible
      || compareMembers(a.members[0], b.members[0]) || compareMembers(a.members[1], b.members[1]);

  const response: InsightsDTO = {
    your_reads: yourReads,
    reads_you: readsYou,
    mutual_recognition: mutualRecognition.sort(comparePair).slice(0, MUTUAL_PAIR_LIMIT),
    // Every mutual miss has a Wilson bound of zero (`correct` is always 0), so `comparePair`
    // already falls straight to the volume tie-break — the larger denominator is the more
    // interesting miss, and there is nothing left to sort by after that.
    mutual_misses: mutualMisses.sort(comparePair).slice(0, MUTUAL_PAIR_LIMIT),
    confusion: {
      scored_rounds: roundIDs.length,
      minimum_rounds: minimumConfusionRounds,
      pairs: visibleConfusions,
    },
  };
  return ok(insightsDTO(response));
}

// docs/04 §5, docs/06 §6. The ordered track list, and nothing else.
//
// **The server never creates the playlist.** It holds no Spotify or Apple Music credential
// belonging to a user and has no write side to this route: the client authorises with its
// own token — Spotify by PKCE, Apple by MusicKit — and posts the ids below to the service
// itself. What arrives here is a list; what happens to it happens in the user's account.
//
// Unresolved tracks are counted, not hidden. A song with no id for the requested service is
// skipped from `tracks` and shows up in `unresolved_count`, which the UI states plainly
// ("3 songs aren't on Spotify. The rest are in.", docs/11 `record.export.partial`). Silently
// shipping a shorter playlist is how somebody finds out three weeks later.
//
// The whole archive, uncapped: a group plays one round a night, so a year is a few hundred
// nights and the playlist the user asked for is the playlist they get. If this ever needs a
// cap it has to arrive as a number in the payload, the way `unresolved_count` did, and never
// as a silent `.limit()`.
async function exportForGroup(req: Request, ctx: MemberCtx): Promise<Response> {
  const service = new URL(req.url).searchParams.get("service");
  if (service !== "spotify" && service !== "apple") {
    throw new ApiError("INVALID_INPUT", { field: "service" });
  }

  const [group, rounds] = await Promise.all([
    loadGroup(ctx.db, ctx.groupId),
    archiveRounds(ctx.db, ctx.groupId, null),
  ]);
  const entries = await archiveEntries(ctx.db, rounds.map((round) => round.round_id), null);

  // Newest night first, and within a night the order The Record shows on screen, so the
  // playlist reads top to bottom the way the archive does (docs/06 §6).
  const tracks: ExportTrackDTO[] = [];
  let unresolved = 0;
  for (const round of rounds) {
    for (const entry of entries.get(round.round_id) ?? []) {
      const track = exportTrackDTO(entry.track);
      const id = service === "spotify" ? track.spotify_uri : track.apple_music_id;
      if (id === null) unresolved += 1;
      else tracks.push(track);
    }
  }

  // docs/06 §6: `"{Group name} — Blind Drop"`, and a new playlist every time. An existing
  // one with the same name is never reused — silently mutating a playlist the user may have
  // edited is worse than a duplicate they can delete.
  return ok(exportDTO(`${group.name} — Blind Drop`, tracks, unresolved));
}

/** Soft, always: submissions and guesses stay, and past attribution in The Record is
 *  preserved (docs/03 §6). The next request naming this circle gets `NOT_FOUND`; the next
 *  request through the `current` compat routes falls to whichever circle is now oldest.
 *  Scoped to `ctx.groupId` specifically — leaving one circle must never end active membership
 *  in another (ADR-011: circles do not interact).
 *
 *  **`E21-01`'s open question, resolved here:** the last admin may not leave a circle that
 *  still has other active members, because there would be no one left to change its settings
 *  or — once `E21-02` lands — promote a successor. Enforced server-side (`LAST_ADMIN_MUST_TRANSFER`)
 *  rather than only hidden in a client, the same way `NOT_ADMIN` is: a stale or tampered client
 *  gets the same refusal. Today this is unreachable through the app's own UI — there is no
 *  promote or remove yet (`E21-02`), so a solo admin genuinely has no way to arrange for
 *  someone else to hold the role first — but the guard is defensive and forward-looking rather
 *  than something to add only once `E21-02` makes it reachable. A sole admin of a circle they
 *  are the only active member of may still leave: there is nobody left to strand. */
async function leaveGroup(ctx: MemberCtx): Promise<Response> {
  if (ctx.role === "admin") {
    const { data: activeMembers, error: rosterError } = await ctx.db
      .from("memberships")
      .select("user_id, role")
      .eq("group_id", ctx.groupId)
      .is("left_at", null);
    if (rosterError) throw dbFailure("groups.leave.roster", rosterError);

    const others = activeMembers.filter((m) => m.user_id !== ctx.userId);
    const anotherAdminRemains = others.some((m) => m.role === "admin");
    if (others.length > 0 && !anotherAdminRemains) {
      throw new ApiError("LAST_ADMIN_MUST_TRANSFER");
    }
  }

  const { error } = await ctx.db
    .from("memberships")
    .update({ left_at: new Date().toISOString() })
    .eq("user_id", ctx.userId)
    .eq("group_id", ctx.groupId)
    .is("left_at", null);
  if (error) throw dbFailure("groups.leave", error);
  return noContent();
}

// ─── roles — E21-02 ─────────────────────────────────────────────────────────
// A membership's role is circle governance, not round participation. Changing it or ending
// it only touches the active membership row; submissions and guesses are historical facts and
// deliberately stay where they are. A round already on the books therefore keeps its cards,
// attribution and scoring intact.

interface ActiveMembershipRow {
  user_id: string;
  role: "member" | "admin";
}

async function activeMember(db: Db, groupId: string, userId: string): Promise<ActiveMembershipRow> {
  const { data, error } = await db
    .from("memberships")
    .select("user_id, role")
    .eq("group_id", groupId)
    .eq("user_id", userId)
    .is("left_at", null)
    .maybeSingle();
  if (error) throw dbFailure("groups.member", error);
  if (!data) throw new ApiError("NOT_FOUND");
  return data as ActiveMembershipRow;
}

async function activeAdminCount(db: Db, groupId: string): Promise<number> {
  const { count, error } = await db
    .from("memberships")
    .select("user_id", { count: "exact", head: true })
    .eq("group_id", groupId)
    .eq("role", "admin")
    .is("left_at", null);
  if (error) throw dbFailure("groups.member.adminCount", error);
  return count ?? 0;
}

async function setMemberRole(req: Request, ctx: MemberCtx, userId: string): Promise<Response> {
  const body = await parseBody(req, { role: str({ pattern: /^(member|admin)$/ }) });
  const member = await activeMember(ctx.db, ctx.groupId, userId);
  const role = body.role as "member" | "admin";

  // A lone admin may leave an otherwise empty circle, but may never demote themselves out of
  // it: the circle would remain, with nobody able to administer it or appoint a successor.
  if (member.role === "admin" && role === "member" && await activeAdminCount(ctx.db, ctx.groupId) <= 1) {
    throw new ApiError("LAST_ADMIN_MUST_TRANSFER");
  }

  if (member.role !== role) {
    const { error } = await ctx.db
      .from("memberships")
      .update({ role })
      .eq("group_id", ctx.groupId)
      .eq("user_id", userId)
      .is("left_at", null);
    if (error) throw dbFailure("groups.member.role", error);
  }

  // `ctx.role` was read before the update. Replace it when the caller changed their own role so
  // the returned DTO is truthful and the app removes admin controls immediately.
  return ok(await currentGroupDTO({ ...ctx, role: userId === ctx.userId ? role : ctx.role }));
}

async function removeMember(ctx: MemberCtx, userId: string): Promise<Response> {
  const member = await activeMember(ctx.db, ctx.groupId, userId);
  if (member.role === "admin" && await activeAdminCount(ctx.db, ctx.groupId) <= 1) {
    const { count, error } = await ctx.db
      .from("memberships")
      .select("user_id", { count: "exact", head: true })
      .eq("group_id", ctx.groupId)
      .is("left_at", null);
    if (error) throw dbFailure("groups.member.rosterCount", error);
    // Match leave exactly: a sole admin may close an otherwise empty circle, but cannot strand
    // other active members without an admin.
    if ((count ?? 0) > 1) throw new ApiError("LAST_ADMIN_MUST_TRANSFER");
  }

  const { error } = await ctx.db
    .from("memberships")
    .update({ left_at: new Date().toISOString() })
    .eq("group_id", ctx.groupId)
    .eq("user_id", userId)
    .is("left_at", null);
  if (error) throw dbFailure("groups.member.remove", error);
  return noContent();
}

// ─── invitations — E20-01, docs/02 §2 (the invite-code path is unchanged and untouched) ─────
//
// A second door into a circle, for someone the inviter already knows the account of — the
// invite-code door above stays exactly as it was, for someone who has none yet. Pending
// invitations are their own state (`public.invitations`, distinct from `memberships`), so
// every reader of `memberships` elsewhere in this file and in `rounds/index.ts` needs no
// change: a pending invitee has no membership row and is invisible to the name pool, the
// minimum-of-three, `card_order`, standings, scoring and every push audience by construction.

const INVITE_LIMIT_PER_USER = 20;
const ONE_HOUR_IN_SECONDS = 60 * 60;

/** Invites `user_id` — a real, distinct account — to `ctx.groupId`. Any active member may
 *  invite, not only the admin; there is no admin-only gate in this slice (E21 owns roles). */
async function inviteMember(req: Request, ctx: MemberCtx): Promise<Response> {
  // Charged before the body is even parsed, same discipline as `POST /groups/join`: every
  // attempt costs the same, so the quota itself never becomes an oracle for who has an
  // account (docs/14 §8).
  await enforceRateLimit(
    ctx.db,
    `invite:u:${ctx.userId}`,
    INVITE_LIMIT_PER_USER,
    ONE_HOUR_IN_SECONDS,
  );

  const body = await parseBody(req, { user_id: str({ min: 1, max: 64 }) });
  if (!UUID.test(body.user_id)) throw new ApiError("INVALID_INPUT", { field: "user_id" });
  if (body.user_id === ctx.userId) throw new ApiError("INVALID_INPUT", { field: "user_id" });

  const { data: existing, error: membershipError } = await ctx.db
    .from("memberships")
    .select("id")
    .eq("group_id", ctx.groupId)
    .eq("user_id", body.user_id)
    .is("left_at", null)
    .maybeSingle();
  if (membershipError) throw dbFailure("groups.invite.membership", membershipError);
  if (existing) throw new ApiError("ALREADY_IN_GROUP");

  // The invited id must name a real profile. An unknown id gets the same INVALID_INPUT a
  // malformed one gets — distinguishing them would be an account-existence oracle, the same
  // reasoning `POST /groups/join` already applies to invite codes (docs/14 §8).
  const { data: invitedProfile, error: profileError } = await ctx.db
    .from("profiles")
    .select("id")
    .eq("id", body.user_id)
    .maybeSingle();
  if (profileError) throw dbFailure("groups.invite.profile", profileError);
  if (!invitedProfile) throw new ApiError("INVALID_INPUT", { field: "user_id" });

  const { data, error } = await ctx.db.rpc("create_invitation", {
    p_group: ctx.groupId,
    p_invited_by: ctx.userId,
    p_invited_user: body.user_id,
  });
  if (isUniqueViolation(error)) throw new ApiError("ALREADY_INVITED");
  if (error) throw dbFailure("groups.invite", error);

  const row = data as { id: string; created_at: string; expires_at: string };
  const group = await loadGroup(ctx.db, ctx.groupId);
  return ok(
    invitationDTO({
      id: row.id,
      group: { id: group.id, name: group.name },
      invitedBy: memberDTO({ user_id: ctx.userId, display_name: ctx.displayName }),
      createdAt: row.created_at,
      expiresAt: row.expires_at,
    }),
  );
}

/**
 * `GET /groups/invitations` — every circle the caller has been invited to and has not yet
 * answered, oldest first. `expires_at > now` is filtered here rather than left to the client:
 * a lazily-expired row is filtered exactly like a genuinely absent one until something tries
 * to act on it (`accept_invitation`/`decline_invitation` do the actual state flip).
 *
 * Nothing here is shaped by anyone else's participation in a round — this reads
 * `invitations`, `groups` and `profiles` only, never a round, a submission or a guess.
 */
async function myInvitationsResponse(ctx: ProfileCtx): Promise<Response> {
  const { data: rows, error } = await ctx.db
    .from("invitations")
    .select("id, group_id, invited_by, created_at, expires_at")
    .eq("invited_user", ctx.userId)
    .eq("status", "pending")
    .gt("expires_at", serverNow().toISOString())
    .order("created_at", { ascending: true });
  if (error) throw dbFailure("groups.myInvitations", error);
  if (rows.length === 0) return ok({ invitations: [] });

  const groupIds = [...new Set(rows.map((r) => r.group_id as string))];
  const inviterIds = [...new Set(rows.map((r) => r.invited_by as string))];

  const [{ data: groups, error: groupsError }, { data: profiles, error: profilesError }] =
    await Promise.all([
      ctx.db.from("groups").select("id, name").in("id", groupIds),
      ctx.db.from("profiles").select("id, display_name").in("id", inviterIds),
    ]);
  if (groupsError) throw dbFailure("groups.myInvitations.groups", groupsError);
  if (profilesError) throw dbFailure("groups.myInvitations.profiles", profilesError);

  const groupById = new Map(groups.map((g) => [g.id as string, g]));
  const profileById = new Map(profiles.map((p) => [p.id as string, p]));

  const invitations = rows.map((row) => {
    const group = groupById.get(row.group_id as string);
    const inviter = profileById.get(row.invited_by as string);
    return invitationDTO({
      id: row.id,
      // Both lookups come from foreign keys this row could not exist without — `on delete
      // cascade` on both `group_id` and `invited_by` (`20260819100000_invitations.sql`), so
      // the fallback below is unreachable in practice and only keeps this from throwing.
      group: { id: row.group_id, name: group?.name ?? "" },
      invitedBy: memberDTO({ user_id: row.invited_by, display_name: inviter?.display_name ?? "" }),
      createdAt: row.created_at,
      expiresAt: row.expires_at,
    });
  });

  return ok({ invitations });
}

/** `POST /groups/invitations/:invitation_id/accept` — atomic with the membership insert
 *  (`accept_invitation`, ADR-011's cap included), and answers with the same `GroupDTO` shape
 *  `POST /groups/join` does, so the client's "you're in" screen does not need a second shape. */
async function acceptInvitation(ctx: ProfileCtx, invitationId: string): Promise<Response> {
  if (!UUID.test(invitationId)) throw new ApiError("NOT_FOUND");

  const { data, error } = await ctx.db.rpc("accept_invitation", {
    p_invitation: invitationId,
    p_user: ctx.userId,
  });
  if (isInvitationGone(error)) throw new ApiError("NOT_FOUND");
  if (isCircleLimitReached(error)) throw new ApiError("CIRCLE_LIMIT_REACHED");
  if (isUniqueViolation(error)) throw new ApiError("ALREADY_IN_GROUP");
  if (error) throw dbFailure("groups.invitations.accept", error);

  const outcome = data as { outcome: "accepted" | "expired"; group_id?: string };
  if (outcome.outcome !== "accepted" || !outcome.group_id) throw new ApiError("NOT_FOUND");
  const group = await loadGroup(ctx.db, outcome.group_id);
  return ok(groupDTO(group, false, await roster(ctx.db, group.id)));
}

/** `POST /groups/invitations/:invitation_id/decline` — terminal, and re-invitable: the next
 *  `create_invitation` for this pair inserts cleanly, because this row is no longer pending. */
async function declineInvitation(ctx: ProfileCtx, invitationId: string): Promise<Response> {
  if (!UUID.test(invitationId)) throw new ApiError("NOT_FOUND");

  const { data, error } = await ctx.db.rpc("decline_invitation", {
    p_invitation: invitationId,
    p_user: ctx.userId,
  });
  if (isInvitationGone(error)) throw new ApiError("NOT_FOUND");
  if (error) throw dbFailure("groups.invitations.decline", error);
  if (data !== "declined") throw new ApiError("NOT_FOUND");
  return noContent();
}

/** `GET /groups/people-you-played-with` — the short invite list after creating a group.
 *
 * This is deliberately derived on the server. A client has neither the membership dates needed
 * for recency nor permission to turn every roster it has ever fetched into a durable people
 * list. The response is identities only: it says someone shares a group with the caller, not
 * how many groups, when they joined, or what either person did in a round. */
async function peopleYouPlayedWith(ctx: ProfileCtx): Promise<Response> {
  const { data: mine, error: mineError } = await ctx.db
    .from("memberships")
    .select("group_id")
    .eq("user_id", ctx.userId)
    .is("left_at", null);
  if (mineError) throw dbFailure("groups.people.mine", mineError);
  const groupIds = mine.map((row) => row.group_id as string);
  if (groupIds.length === 0) return ok({ people: [] });

  const { data: shared, error: sharedError } = await ctx.db
    .from("memberships")
    .select("user_id, joined_at")
    .in("group_id", groupIds)
    .neq("user_id", ctx.userId)
    .is("left_at", null);
  if (sharedError) throw dbFailure("groups.people.shared", sharedError);
  if (shared.length === 0) return ok({ people: [] });

  // Keep only each person's most recent shared membership. The date never leaves the server;
  // it is a sort key, not a new social graph or an activity signal.
  const newestByUser = new Map<string, string>();
  for (const row of shared) {
    const userID = row.user_id as string;
    const joinedAt = row.joined_at as string;
    if ((newestByUser.get(userID) ?? "") < joinedAt) newestByUser.set(userID, joinedAt);
  }
  const ids = [...newestByUser.keys()];
  const { data: profiles, error: profilesError } = await ctx.db
    .from("profiles")
    .select("id, display_name")
    .in("id", ids);
  if (profilesError) throw dbFailure("groups.people.profiles", profilesError);

  const people = profiles
    .map((profile) => ({
      person: knownPersonDTO({ user_id: profile.id, display_name: profile.display_name }),
      newest: newestByUser.get(profile.id) ?? "",
    }))
    .sort((a, b) => b.newest.localeCompare(a.newest) || a.person.display_name.localeCompare(b.person.display_name))
    .map((entry) => entry.person);
  return ok({ people });
}

const MAX_INVITE_ATTEMPTS = 5;

// docs/04 §8: `POST /groups/join` is limited to 10/hour per user and, additionally, 30/hour
// per hashed IP. The space of codes is 31^6 ≈ 8.9e8, which is not what stops a brute force —
// these two counters are. Ten guesses an hour turns an exhaustive search into a project
// measured in millennia, and the per-IP half stops one attacker from buying more attempts by
// signing up more users.
const JOIN_LIMIT_PER_USER = 10;
const JOIN_LIMIT_PER_IP = 30;

serveFunction("groups", {
  // ─── create ────────────────────────────────────────────────────────────────
  "POST /": async (req, route) => {
    const ctx = await requireProfile(await requireUser(req, route));
    const body = await parseBody(req, {
      name: str({ min: 1, max: 40 }),
      timezone: str({ min: 1, max: 64 }),
      reveal_hour: optional(int({ min: 18, max: 21 })),
    });

    const name = body.name.trim();
    if (name.length === 0) throw new ApiError("INVALID_INPUT", { field: "name" });

    const { data: timezoneOk, error: timezoneError } = await ctx.db.rpc("timezone_is_valid", {
      p_timezone: body.timezone,
    });
    if (timezoneError) throw dbFailure("groups.timezone_is_valid", timezoneError);
    if (!timezoneOk) throw new ApiError("INVALID_INPUT", { field: "timezone" });

    // 31^6 codes and ten groups: a collision is a curiosity, not a plan. Five attempts and
    // then a 500, rather than a loop that could spin (docs/14 §8).
    for (let attempt = 1; attempt <= MAX_INVITE_ATTEMPTS; attempt += 1) {
      const { data, error } = await ctx.db.rpc("create_group", {
        p_user: ctx.userId,
        p_name: name,
        p_timezone: body.timezone,
        p_reveal_hour: body.reveal_hour ?? 20,
        p_invite_code: generateInviteCode(),
      });

      if (!error) {
        const group = data as GroupRow;
        return ok(
          groupDTO(group, true, [
            rosterMemberDTO({ user_id: ctx.userId, display_name: ctx.displayName, role: "admin" }),
          ]),
        );
      }
      if (isCircleLimitReached(error)) throw new ApiError("CIRCLE_LIMIT_REACHED");
      if (!isUniqueViolation(error)) throw dbFailure("groups.create", error);
      // else: the invite code collided. Round again with a new one.
    }
    throw new Error(`could not find a free invite code in ${MAX_INVITE_ATTEMPTS} attempts`);
  },

  // ─── join ──────────────────────────────────────────────────────────────────
  "POST /join": async (req, route) => {
    const ctx = await requireProfile(await requireUser(req, route));

    // Charged on *every* attempt, before the body is even parsed and long before the code is
    // looked up, so that a malformed code, an unknown code and a real one all cost exactly
    // the same. Charging only for failures would make the quota itself the oracle the
    // identical `NOT_FOUND` below exists to deny: an attacker whose counter never moved would
    // have learned that the code was real (docs/14 §8).
    await enforceRateLimit(
      ctx.db,
      `join:u:${ctx.userId}`,
      JOIN_LIMIT_PER_USER,
      ONE_HOUR_IN_SECONDS,
    );
    await enforceRateLimit(
      ctx.db,
      await ipBucket("join", clientIp(req)),
      JOIN_LIMIT_PER_IP,
      ONE_HOUR_IN_SECONDS,
    );

    const { invite_code } = await parseBody(req, { invite_code: str({ min: 1, max: 32 }) });

    const code = normaliseInviteCode(invite_code);
    // A malformed code, an unknown code and a code the caller cannot use are one answer.
    // Distinguishing them is how invite-code enumeration starts (docs/14 §8).
    if (!code) throw new ApiError("NOT_FOUND");

    const { data: group, error: lookupError } = await ctx.db
      .from("groups")
      .select(GROUP_COLUMNS)
      .eq("invite_code", code)
      .maybeSingle();
    if (lookupError) throw dbFailure("groups.join.lookup", lookupError);
    if (!group) throw new ApiError("NOT_FOUND");

    const { error: joinError } = await ctx.db
      .from("memberships")
      .insert({ group_id: group.id, user_id: ctx.userId, role: "member" });
    // Two distinct failures, checked in this order because they can both be true at once and
    // the cap is the more informative answer: `memberships_circle_cap` (ADR-011) refuses a
    // fourth circle; `memberships_unique_active_pair` refuses rejoining one already held.
    if (isCircleLimitReached(joinError)) throw new ApiError("CIRCLE_LIMIT_REACHED");
    if (isUniqueViolation(joinError)) throw new ApiError("ALREADY_IN_GROUP");
    if (joinError) throw dbFailure("groups.join", joinError);

    return ok(groupDTO(group, false, await roster(ctx.db, group.id)));
  },

  // ─── the switcher ──────────────────────────────────────────────────────────
  "GET /": async (req, route) => {
    const ctx = await requireProfile(await requireUser(req, route));
    return myCirclesResponse(ctx);
  },

  // ─── current ───────────────────────────────────────────────────────────────
  "GET /current": async (req, route) => {
    const ctx = await requireDefaultMembership(await requireProfile(await requireUser(req, route)));
    return ok(await currentGroupDTO(ctx));
  },
  "GET /:group_id": async (req, route, params) => {
    const ctx = await requireMembership(
      await requireProfile(await requireUser(req, route)),
      params.group_id,
    );
    return ok(await currentGroupDTO(ctx));
  },

  "PATCH /current": async (req, route) => {
    const ctx = requireAdmin(
      await requireDefaultMembership(await requireProfile(await requireUser(req, route))),
    );
    return patchGroup(req, ctx);
  },
  "PATCH /:group_id": async (req, route, params) => {
    const ctx = requireAdmin(
      await requireMembership(await requireProfile(await requireUser(req, route)), params.group_id),
    );
    return patchGroup(req, ctx);
  },

  // ─── standings ─────────────────────────────────────────────────────────────
  // docs/04 §4. Two lists that deliberately do not have the same shape.
  //
  // **Best Ear is ranked. Readability is not, and carries no `rank` field.** docs/02 §4.5 makes
  // that a product rule rather than a presentation preference: guessing well is a scoreboard,
  // being hard to read is a trait, and low readability is its own kind of win. The reason the
  // rule is enforced *here*, by not sending the field, is that a client which receives a rank
  // will render it — someone will reasonably assume a field that exists is meant to be shown.
  // The readability array is sorted descending purely so the list is stable between refreshes.
  //
  // Safe in every phase. Every number on it comes from `scored` rounds only, so nothing here
  // moves while tonight's round is open — the standings a member reads at 19:00 are the same
  // ones they read at 09:00, and a member watching them for a change learns nothing (docs/14
  // §3).
  "GET /current/standings": async (req, route) => {
    const ctx = await requireDefaultMembership(await requireProfile(await requireUser(req, route)));
    return standingsForGroup(ctx);
  },
  "GET /:group_id/standings": async (req, route, params) => {
    const ctx = await requireMembership(
      await requireProfile(await requireUser(req, route)),
      params.group_id,
    );
    return standingsForGroup(ctx);
  },

  // ─── member profile — E24-02 ──────────────────────────────────────────────
  // The target must be an active member of this exact circle. A caller cannot use this as a
  // directory for former members or for people from another circle, and every fact below is
  // already constrained to scored rounds before it reaches the response.
  "GET /:group_id/members/:user_id/profile": async (req, route, params) => {
    const ctx = await requireMembership(
      await requireProfile(await requireUser(req, route)),
      params.group_id,
    );
    return profileForMember(ctx, params.user_id);
  },

  // ─── insights — E25-01 ────────────────────────────────────────────────────
  "GET /:group_id/insights": async (req, route, params) => {
    const ctx = await requireMembership(
      await requireProfile(await requireUser(req, route)),
      params.group_id,
    );
    return insightsForGroup(ctx);
  },

  // ─── the record ────────────────────────────────────────────────────────────
  // docs/04 §5. The archive: every night this group has finished, newest first, grouped by the
  // group-local date it was played on.
  //
  // Safe in every phase for the same reason the standings are: it is a function of `scored`
  // rounds only, so nothing on it moves while tonight's round is in flight. A member who
  // refreshes The Record all evening watching for it to grow sees exactly what they saw at
  // 09:00 — and at 22:00, when tonight's round scores, it grows by a whole night at once for
  // everybody, which is a fact about the clock rather than about any person (docs/14 §3).
  "GET /current/record": async (req, route) => {
    const ctx = await requireDefaultMembership(await requireProfile(await requireUser(req, route)));
    return recordForGroup(req, ctx);
  },
  "GET /:group_id/record": async (req, route, params) => {
    const ctx = await requireMembership(
      await requireProfile(await requireUser(req, route)),
      params.group_id,
    );
    return recordForGroup(req, ctx);
  },

  // ─── the export ────────────────────────────────────────────────────────────
  // docs/04 §5, docs/06 §6. The ordered track list, and nothing else.
  //
  // **The server never creates the playlist.** It holds no Spotify or Apple Music credential
  // belonging to a user and has no write side to this route: the client authorises with its
  // own token — Spotify by PKCE, Apple by MusicKit — and posts the ids below to the service
  // itself. What arrives here is a list; what happens to it happens in the user's account.
  //
  // Unresolved tracks are counted, not hidden. A song with no id for the requested service is
  // skipped from `tracks` and shows up in `unresolved_count`, which the UI states plainly
  // ("3 songs aren't on Spotify. The rest are in.", docs/11 `record.export.partial`). Silently
  // shipping a shorter playlist is how somebody finds out three weeks later.
  //
  // The whole archive, uncapped: a group plays one round a night, so a year is a few hundred
  // nights and the playlist the user asked for is the playlist they get. If this ever needs a
  // cap it has to arrive as a number in the payload, the way `unresolved_count` did, and never
  // as a silent `.limit()`.
  "GET /current/record/export": async (req, route) => {
    const ctx = await requireDefaultMembership(await requireProfile(await requireUser(req, route)));
    return exportForGroup(req, ctx);
  },
  "GET /:group_id/record/export": async (req, route, params) => {
    const ctx = await requireMembership(
      await requireProfile(await requireUser(req, route)),
      params.group_id,
    );
    return exportForGroup(req, ctx);
  },

  // ─── leave ─────────────────────────────────────────────────────────────────
  "POST /current/leave": async (req, route) => {
    const ctx = await requireDefaultMembership(await requireProfile(await requireUser(req, route)));
    return leaveGroup(ctx);
  },
  "POST /:group_id/leave": async (req, route, params) => {
    const ctx = await requireMembership(
      await requireProfile(await requireUser(req, route)),
      params.group_id,
    );
    return leaveGroup(ctx);
  },

  // ─── roles — E21-02 ───────────────────────────────────────────────────────
  "PATCH /:group_id/members/:user_id": async (req, route, params) => {
    const ctx = requireAdmin(
      await requireMembership(await requireProfile(await requireUser(req, route)), params.group_id),
    );
    return setMemberRole(req, ctx, params.user_id);
  },
  "DELETE /:group_id/members/:user_id": async (req, route, params) => {
    const ctx = requireAdmin(
      await requireMembership(await requireProfile(await requireUser(req, route)), params.group_id),
    );
    return removeMember(ctx, params.user_id);
  },

  // ─── invitations — E20-01 ────────────────────────────────────────────────────
  "POST /current/invitations": async (req, route) => {
    const ctx = await requireDefaultMembership(await requireProfile(await requireUser(req, route)));
    return inviteMember(req, ctx);
  },
  "POST /:group_id/invitations": async (req, route, params) => {
    const ctx = await requireMembership(
      await requireProfile(await requireUser(req, route)),
      params.group_id,
    );
    return inviteMember(req, ctx);
  },
  "GET /invitations": async (req, route) => {
    const ctx = await requireProfile(await requireUser(req, route));
    return myInvitationsResponse(ctx);
  },
  "GET /people-you-played-with": async (req, route) => {
    const ctx = await requireProfile(await requireUser(req, route));
    return peopleYouPlayedWith(ctx);
  },
  "POST /invitations/:invitation_id/accept": async (req, route, params) => {
    const ctx = await requireProfile(await requireUser(req, route));
    return acceptInvitation(ctx, params.invitation_id);
  },
  "POST /invitations/:invitation_id/decline": async (req, route, params) => {
    const ctx = await requireProfile(await requireUser(req, route));
    return declineInvitation(ctx, params.invitation_id);
  },
});
