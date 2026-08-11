// groups/index.ts — the group and its roster. docs/04 §3, docs/02 §1, docs/14 §4.
//
//   POST /groups                create a group, become its admin
//   POST /groups/join           join by invite code
//   GET  /groups/current        the group and its roster
//   PATCH /groups/current       admin only; name and reveal_hour
//   POST /groups/current/leave  set left_at
//
// **There is no route here that takes a group id.** Every one of them resolves the group from
// the caller's active membership (ADR-005, docs/14 §4), which is what leaves group data with
// no IDOR surface: there is no id to tamper with, so there is nothing to fuzz.

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
  enforceRateLimit,
  ipBucket,
  type MemberCtx,
  requireAdmin,
  requireMembership,
  requireProfile,
  requireUser,
} from "../_shared/auth.ts";
import { ALREADY_IN_GROUP, type Db, dbFailure, isUniqueViolation } from "../_shared/db.ts";
import { type GroupDTO, groupDTO, groupPatchDTO, type MemberDTO, memberDTO } from "../_shared/dto.ts";
import { generateInviteCode, normaliseInviteCode } from "../_shared/invite.ts";
import { localDate, nextDate, serverNow } from "../_shared/time.ts";

interface GroupRow {
  id: string;
  name: string;
  timezone: string;
  reveal_hour: number;
  invite_code: string;
}
const GROUP_COLUMNS = "id, name, timezone, reveal_hour, invite_code";

/** The active roster: `user_id` and `display_name`, and deliberately nothing else. No
 *  `joined_at` (docs/14 §3), no counts, no ordering derived from activity. */
async function roster(db: Db, groupId: string): Promise<MemberDTO[]> {
  const { data: memberships, error: membershipError } = await db
    .from("memberships")
    .select("user_id")
    .eq("group_id", groupId)
    .is("left_at", null);
  if (membershipError) throw dbFailure("groups.roster.memberships", membershipError);

  const ids = memberships.map((m) => m.user_id);
  if (ids.length === 0) return [];

  const { data: profiles, error: profileError } = await db
    .from("profiles")
    .select("id, display_name")
    .in("id", ids)
    .order("display_name", { ascending: true })
    .order("id", { ascending: true });
  if (profileError) throw dbFailure("groups.roster.profiles", profileError);

  return profiles.map((p) => memberDTO({ user_id: p.id, display_name: p.display_name }));
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

const MAX_INVITE_ATTEMPTS = 5;

// docs/04 §8: `POST /groups/join` is limited to 10/hour per user and, additionally, 30/hour
// per hashed IP. The space of codes is 31^6 ≈ 8.9e8, which is not what stops a brute force —
// these two counters are. Ten guesses an hour turns an exhaustive search into a project
// measured in millennia, and the per-IP half stops one attacker from buying more attempts by
// signing up more users.
const JOIN_LIMIT_PER_USER = 10;
const JOIN_LIMIT_PER_IP = 30;
const ONE_HOUR_IN_SECONDS = 60 * 60;

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
        return ok(groupDTO(group, true, [memberDTO({ user_id: ctx.userId, display_name: ctx.displayName })]));
      }
      if (error.code === ALREADY_IN_GROUP) throw new ApiError("ALREADY_IN_GROUP");
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
    await enforceRateLimit(ctx.db, `join:u:${ctx.userId}`, JOIN_LIMIT_PER_USER, ONE_HOUR_IN_SECONDS);
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
    // `memberships_one_active_per_user` is the enforcement of ADR-005, so a second group is a
    // unique violation rather than a race we have to check for first.
    if (isUniqueViolation(joinError)) throw new ApiError("ALREADY_IN_GROUP");
    if (joinError) throw dbFailure("groups.join", joinError);

    return ok(groupDTO(group, false, await roster(ctx.db, group.id)));
  },

  // ─── current ───────────────────────────────────────────────────────────────
  "GET /current": async (req, route) => {
    const ctx = await requireMembership(await requireProfile(await requireUser(req, route)));
    return ok(await currentGroupDTO(ctx));
  },

  "PATCH /current": async (req, route) => {
    const ctx = requireAdmin(
      await requireMembership(await requireProfile(await requireUser(req, route))),
    );
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
  },

  // ─── leave ─────────────────────────────────────────────────────────────────
  "POST /current/leave": async (req, route) => {
    const ctx = await requireMembership(await requireProfile(await requireUser(req, route)));
    // Soft, always: submissions and guesses stay, and past attribution in The Record is
    // preserved (docs/03 §6). The next request from this token gets NO_GROUP.
    const { error } = await ctx.db
      .from("memberships")
      .update({ left_at: new Date().toISOString() })
      .eq("user_id", ctx.userId)
      .is("left_at", null);
    if (error) throw dbFailure("groups.leave", error);
    return noContent();
  },
});
