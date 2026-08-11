// _shared/dto.ts — every response shape in the API, in one file. docs/04, docs/14 §3.
//
// **This is the file a security reviewer reads.** Two rules hold everywhere in it:
//
//   1. Every DTO is built by naming its fields. No spread, no `select *`, no passing a row
//      through. A column added to a table in a future migration cannot appear on the wire by
//      accident — someone has to come here and type its name (docs/01 §2, the shape step).
//   2. Nothing derived from another user's participation may appear on an `open`-phase
//      response. The friction of editing this file *is* the control (docs/14 §3).

import { rfc3339 } from "./time.ts";

// ─── identity — docs/04 §2 ───────────────────────────────────────────────────

export interface MeDTO {
  user_id: string;
  display_name: string;
  has_group: boolean;
}

export function meDTO(
  profile: { id: string; display_name: string },
  hasGroup: boolean,
): MeDTO {
  return {
    user_id: profile.id,
    display_name: profile.display_name,
    has_group: hasGroup,
  };
}

// ─── groups — docs/04 §3 ─────────────────────────────────────────────────────

/**
 * A member of the roster: who is in the group, not what they have done.
 *
 * `joined_at` is deliberately absent and must stay absent. During `open`, a `joined_at` that
 * changed today plus a missing name in tonight's pool is an inference channel (docs/14 §3).
 */
export interface MemberDTO {
  user_id: string;
  display_name: string;
}

export function memberDTO(row: { user_id: string; display_name: string }): MemberDTO {
  return {
    user_id: row.user_id,
    display_name: row.display_name,
  };
}

export interface GroupDTO {
  id: string;
  name: string;
  timezone: string;
  reveal_hour: number;
  invite_code: string;
  is_admin: boolean;
  members: MemberDTO[];
}

export function groupDTO(
  group: { id: string; name: string; timezone: string; reveal_hour: number; invite_code: string },
  isAdmin: boolean,
  members: MemberDTO[],
): GroupDTO {
  return {
    id: group.id,
    name: group.name,
    timezone: group.timezone,
    reveal_hour: group.reveal_hour,
    invite_code: group.invite_code,
    is_admin: isAdmin,
    members,
  };
}

/**
 * `PATCH /groups/current`, which is the group DTO plus the date the settings start applying.
 *
 * `effective_from` is the local date of the first round that does not exist yet: a
 * `reveal_hour` change never re-times a round that has already been created (docs/02 §1,
 * docs/03 §4). It is `null` when the patch did not touch `reveal_hour`, because then there is
 * nothing to wait for.
 */
export interface GroupPatchDTO extends GroupDTO {
  effective_from: string | null;
}

export function groupPatchDTO(group: GroupDTO, effectiveFrom: string | null): GroupPatchDTO {
  return {
    id: group.id,
    name: group.name,
    timezone: group.timezone,
    reveal_hour: group.reveal_hour,
    invite_code: group.invite_code,
    is_admin: group.is_admin,
    members: group.members,
    effective_from: effectiveFrom,
  };
}

// ─── shared field helpers ────────────────────────────────────────────────────

/** Every timestamp that reaches a client goes through here, so the wire format is one format
 *  (docs/04: RFC 3339 UTC with a `Z`). */
export function timestamp(value: string | Date): string {
  return rfc3339(value);
}
