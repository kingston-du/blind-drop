// _shared/dto.ts — every response shape in the API, in one file. docs/04, docs/14 §3.
//
// **This is the file a security reviewer reads.** Two rules hold everywhere in it:
//
//   1. Every DTO is built by naming its fields. No spread, no `select *`, no passing a row
//      through. A column added to a table in a future migration cannot appear on the wire by
//      accident — someone has to come here and type its name (docs/01 §2, the shape step).
//   2. Nothing derived from another user's participation may appear on an `open`-phase
//      response. The friction of editing this file *is* the control (docs/14 §3).

import { rfc3339, type RoundState } from "./time.ts";

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

// ─── tracks — docs/06 §2 ─────────────────────────────────────────────────────

/**
 * The single track shape used everywhere in docs/04, and — verbatim — the shape of
 * `submissions.track_meta`.
 *
 * `artwork_url` is Apple's literal `{w}x{h}` template, never a resolved size: the app needs
 * four different sizes from 120 to 900 (docs/06 §2.1) and picking one here would freeze it.
 * `artwork_bg_color` exists for exactly one purpose, the placeholder fill behind artwork while
 * it loads, and is never a UI accent (docs/07).
 *
 * Four fields are nullable and each nullable-ness is a real case, not defensiveness: a track
 * with no ISRC keys as `am:` and can never have a Spotify link; a track with no preview
 * renders with no play control; and `spotify_*` may simply not have resolved yet.
 */
export interface TrackDTO {
  track_key: string;
  isrc: string | null;
  title: string;
  artist: string;
  album: string;
  artwork_url: string | null;
  artwork_bg_color: string | null;
  duration_ms: number;
  preview_url: string | null;
  apple_music_id: string;
  apple_music_url: string;
  spotify_id: string | null;
  spotify_url: string | null;
}

const TRACK_FIELDS: readonly (keyof TrackDTO)[] = [
  "track_key",
  "isrc",
  "title",
  "artist",
  "album",
  "artwork_url",
  "artwork_bg_color",
  "duration_ms",
  "preview_url",
  "apple_music_id",
  "apple_music_url",
  "spotify_id",
  "spotify_url",
];

/**
 * A stored `track_meta` blob → a Track DTO, field by field.
 *
 * This one has to name its fields even harder than the rest of the file, because `track_meta`
 * is `jsonb`: whatever was written into it comes back out, so a passthrough here would put an
 * arbitrary key set on the wire and quietly break the golden-file key assertions (E04-03) for
 * every row written before the field was added. Naming the fields makes the DTO the schema.
 */
export function trackDTO(meta: unknown): TrackDTO {
  const raw = (meta ?? {}) as Record<string, unknown>;
  const str = (key: keyof TrackDTO): string => (typeof raw[key] === "string" ? raw[key] as string : "");
  const nullable = (key: keyof TrackDTO): string | null =>
    typeof raw[key] === "string" && raw[key] !== "" ? raw[key] as string : null;

  return {
    track_key: str("track_key"),
    isrc: nullable("isrc"),
    title: str("title"),
    artist: str("artist"),
    album: str("album"),
    artwork_url: nullable("artwork_url"),
    artwork_bg_color: nullable("artwork_bg_color"),
    duration_ms: typeof raw.duration_ms === "number" ? raw.duration_ms : 0,
    preview_url: nullable("preview_url"),
    apple_music_id: str("apple_music_id"),
    apple_music_url: str("apple_music_url"),
    spotify_id: nullable("spotify_id"),
    spotify_url: nullable("spotify_url"),
  };
}

/** The exact key set of a Track, for the tests that assert docs/06 §2 and this file agree. */
export function trackFields(): readonly string[] {
  return TRACK_FIELDS;
}

// ─── the round — docs/04 §4 ──────────────────────────────────────────────────

/**
 * The caller's own submission, and only ever the caller's own.
 *
 * `sealed_at` is their `submissions.updated_at`: a replacement moves it, which is right,
 * because it is when the thing that is currently sealed was sealed. It is safe to return
 * during `open` for the single reason that it is their own data — the same field about
 * anybody else would be a participation leak (docs/14 §3).
 */
export interface SubmissionDTO {
  track: TrackDTO;
  sealed_at: string;
}

export function submissionDTO(row: { track_meta: unknown; updated_at: string }): SubmissionDTO {
  return {
    track: trackDTO(row.track_meta),
    sealed_at: rfc3339(row.updated_at),
  };
}

/**
 * **The `open`-phase payload, in full.** docs/04 §4, and the single most security-sensitive
 * shape in the codebase.
 *
 * The key set is exactly `{round_id, local_date, state, opens_at, reveals_at, scores_at,
 * my_submission}` and the golden files in `tests/golden/` assert it byte for byte. There is no
 * `submission_count`, no `members_submitted`, no `participants`, no `pool`, no `card_count`,
 * and adding one is not a decision an agent gets to make (CLAUDE.md §2.1).
 *
 * Nothing in it depends on anyone else's participation, which is what makes the response size
 * invariant: a round with eleven other submitters serialises to exactly the same bytes as a
 * round with none, holding the caller's own track fixed. That invariant is a test (E04-02),
 * not an aspiration.
 *
 * `voided` uses this same shape — the user's own song comes back to them, unseen and
 * unscored, with **no count of how many did submit**. "Only 2 dropped" tells you something
 * about specific people in a group of eight (docs/08 §5).
 */
export interface RoundDTO {
  round_id: string;
  local_date: string;
  state: RoundState;
  opens_at: string;
  reveals_at: string;
  scores_at: string;
  my_submission: SubmissionDTO | null;
}

export function roundDTO(
  round: {
    id: string;
    local_date: string;
    state: RoundState;
    opens_at: string;
    reveals_at: string;
    scores_at: string;
  },
  mySubmission: SubmissionDTO | null,
): RoundDTO {
  return {
    round_id: round.id,
    local_date: round.local_date,
    state: round.state,
    opens_at: rfc3339(round.opens_at),
    reveals_at: rfc3339(round.reveals_at),
    scores_at: rfc3339(round.scores_at),
    my_submission: mySubmission,
  };
}

/** The `open`/`voided` key set, for the golden-file test. Exported so the assertion and the
 *  builder cannot drift apart. */
export function roundFields(): readonly string[] {
  return ["round_id", "local_date", "state", "opens_at", "reveals_at", "scores_at", "my_submission"];
}

// ─── shared field helpers ────────────────────────────────────────────────────

/** Every timestamp that reaches a client goes through here, so the wire format is one format
 *  (docs/04: RFC 3339 UTC with a `Z`). */
export function timestamp(value: string | Date): string {
  return rfc3339(value);
}
