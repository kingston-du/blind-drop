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

/**
 * A roster row, specifically — `MemberDTO` plus which of the two roles they hold (`E21-01`,
 * docs/04 §3). Its own type rather than widening `MemberDTO` itself: `MemberDTO` is also
 * `name_pool`'s shape, a results card's `owner`, and a Record entry, and each of those routes'
 * golden tests assert an exact key set that does not include `role`. A member's role is static
 * circle governance, not participation — safe in every phase the same way the roster itself is
 * (docs/04 §3) — but it belongs only on the one response that is actually about the roster.
 */
export interface RosterMemberDTO extends MemberDTO {
  role: "member" | "admin";
}

export function rosterMemberDTO(
  row: { user_id: string; display_name: string; role: "member" | "admin" },
): RosterMemberDTO {
  return {
    user_id: row.user_id,
    display_name: row.display_name,
    role: row.role,
  };
}

export interface GroupDTO {
  id: string;
  name: string;
  timezone: string;
  reveal_hour: number;
  invite_code: string;
  is_admin: boolean;
  members: RosterMemberDTO[];
}

export function groupDTO(
  group: { id: string; name: string; timezone: string; reveal_hour: number; invite_code: string },
  isAdmin: boolean,
  members: RosterMemberDTO[],
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

// ─── invitations — E20-01 ─────────────────────────────────────────────────────
//
// A pending invitation, distinct from membership: an inviter, an outcome, and the circle it
// names. Deliberately carries nothing about the circle's roster or its round — accepting it
// is the only way to see any of that, exactly like the invite-code path.

export interface InvitationDTO {
  id: string;
  group: { id: string; name: string };
  invited_by: MemberDTO;
  created_at: string;
  expires_at: string;
}

export function invitationDTO(row: {
  id: string;
  group: { id: string; name: string };
  invitedBy: MemberDTO;
  createdAt: string;
  expiresAt: string;
}): InvitationDTO {
  return {
    id: row.id,
    group: { id: row.group.id, name: row.group.name },
    invited_by: row.invitedBy,
    created_at: rfc3339(new Date(row.createdAt)),
    expires_at: rfc3339(new Date(row.expiresAt)),
  };
}

/** A person the caller knows through an active shared group. This is intentionally only an
 * identity: no membership date, group count, profile, or participation facts cross this
 * boundary. `E20-02` orders this server-side by the newest shared membership. */
export interface KnownPersonDTO {
  user_id: string;
  display_name: string;
}

export function knownPersonDTO(row: { user_id: string; display_name: string }): KnownPersonDTO {
  return { user_id: row.user_id, display_name: row.display_name };
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
  const str = (
    key: keyof TrackDTO,
  ): string => (typeof raw[key] === "string" ? raw[key] as string : "");
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
  return [
    "round_id",
    "local_date",
    "state",
    "opens_at",
    "reveals_at",
    "scores_at",
    "my_submission",
  ];
}

// ─── the switcher — docs/04 §3, docs/02 §2, `E18-02` ─────────────────────────

/**
 * The caller's own next move in one circle. `docs/11` names these `Drop a song`, `Sealed`,
 * `Guess` and `Answers`; `voided` has no UI copy of its own in that set because there is
 * nothing to do about a round that never revealed — it is here so the state machine stays
 * total rather than forcing a caller to reuse `answers` for a round that produced none.
 */
export type CallerCircleState = "drop" | "sealed" | "guess" | "answers" | "voided";

/**
 * One row of `GET /groups` (`E18-02`) — the entire payload the switcher gets, and
 * deliberately the entire payload it needs.
 *
 * **The key set is exactly `{id, name, my_state, needs_action}` and it does not grow with how
 * many other members have done anything.** No submission count, no member count, no "N of M
 * assigned", nothing timestamped by somebody else's action — the same rule `RoundDTO` enforces
 * for one circle, applied across every circle the caller holds (CLAUDE.md §2.1). `my_state`
 * and `needs_action` are both derived from rows keyed by the caller's own id: their own
 * submission, their own guess sheet, never anyone else's.
 */
export interface CircleSummaryDTO {
  id: string;
  name: string;
  my_state: CallerCircleState;
  needs_action: boolean;
}

export function circleSummaryDTO(
  group: { id: string; name: string },
  myState: CallerCircleState,
  needsAction: boolean,
): CircleSummaryDTO {
  return { id: group.id, name: group.name, my_state: myState, needs_action: needsAction };
}

/** The exact key set of a `CircleSummaryDTO`, for the golden-file test. */
export function circleSummaryFields(): readonly string[] {
  return ["id", "name", "my_state", "needs_action"];
}

// ─── the reveal — docs/04 §4, docs/02 §3 ─────────────────────────────────────

/**
 * A card: a number and a song, and deliberately nothing that identifies whose it is.
 *
 * **`submission_id` never crosses the wire before `scored`** (ADR-003). Cards are addressed by
 * `card_no` everywhere in the revealed phase — the guess sheet posts `card_no`, the server
 * resolves it against the round's stored `card_order`. A submission id in a card would be a
 * durable handle to a row whose owner is the answer to the game, and no amount of care
 * elsewhere would make it safe to hand out.
 */
export interface CardDTO {
  card_no: number;
  track: TrackDTO;
}

export function cardDTO(cardNo: number, meta: unknown): CardDTO {
  return { card_no: cardNo, track: trackDTO(meta) };
}

/** One saved assignment on the caller's own sheet. `card_no`, never a submission id. */
export interface GuessDTO {
  card_no: number;
  guessed_user_id: string;
}

export type CannotGuessReason = "not_a_submitter" | "joined_late";

/**
 * The `revealed` payload. docs/04 §4.
 *
 * Two of these fields look like leaks and are not, and the reasoning matters because the
 * instinct to trim them is wrong:
 *
 *   · **`cards` includes the caller's own card.** The client removes it from the *guessing*
 *     sheet using `my_card_no`, but the card is still listed — the numbering is the game's
 *     spine and a hole in it is worse than the information it would save (docs/08 §6).
 *   · **`name_pool` is exactly this round's submitters, caller included.** That does reveal
 *     who participated, and docs/02 §3 accepts it explicitly: the game is unsolvable
 *     otherwise, and a padded pool is both less fun and worked out within two rounds. It is
 *     safe *now* and would not have been an hour ago — which is why nothing resembling it
 *     exists on the `open` payload.
 *
 * `my_guesses` is the caller's own sheet and nothing else. There is no endpoint at any URL
 * that returns another user's guesses before `scored`.
 */
export interface RevealedRoundDTO extends RoundDTO {
  my_card_no: number | null;
  can_guess: boolean;
  cannot_guess_reason: CannotGuessReason | null;
  cards: CardDTO[];
  name_pool: MemberDTO[];
  my_guesses: GuessDTO[];
}

export function revealedRoundDTO(
  base: RoundDTO,
  parts: {
    myCardNo: number | null;
    cannotGuessReason: CannotGuessReason | null;
    cards: CardDTO[];
    namePool: MemberDTO[];
    myGuesses: GuessDTO[];
  },
): RevealedRoundDTO {
  return {
    round_id: base.round_id,
    local_date: base.local_date,
    state: base.state,
    opens_at: base.opens_at,
    reveals_at: base.reveals_at,
    scores_at: base.scores_at,
    my_submission: base.my_submission,
    my_card_no: parts.myCardNo,
    // Derived from the reason rather than passed alongside it, so the two cannot contradict
    // each other — a `can_guess: true` with a reason set would be a client bug nobody could
    // debug from the payload.
    can_guess: parts.cannotGuessReason === null,
    cannot_guess_reason: parts.cannotGuessReason,
    cards: parts.cards,
    name_pool: parts.namePool,
    my_guesses: parts.myGuesses,
  };
}

/** `PUT /rounds/current/guesses` — docs/04 §4.
 *
 *  `assignable_count` is `S − 1`: every card the caller could be asked about. Both counts are
 *  about the caller's own sheet, so neither says anything about whether anyone else has
 *  guessed — and there is no field here that could. */
export interface GuessSheetDTO {
  assignments: GuessDTO[];
  assigned_count: number;
  assignable_count: number;
}

export function guessSheetDTO(assignments: GuessDTO[], assignableCount: number): GuessSheetDTO {
  return {
    assignments,
    assigned_count: assignments.length,
    assignable_count: assignableCount,
  };
}

// ─── results — docs/04 §4, docs/02 §4 ────────────────────────────────────────
// Everything below here is `scored`-phase only, so the blind-window rules that shape the DTOs
// above have stopped applying: who submitted, who guessed what, and how well everybody read
// the room are all on the table at once, which is the entire point of the phase.
//
// **The rule that replaces them is `null` means *not applicable*, never *zero*.** docs/04 §4 is
// unusually blunt about it, and so is docs/08 §7.2: an ear of `null` renders as "—" above "You
// sat this one out", where `0` would render as "0%" above "0 of 7 correct". One of those is a
// statement about a night somebody spent elsewhere and the other is a judgement the product
// refuses to make. Every nullable field down here is that distinction, and the counts beside a
// rate go null with it — "0 of 7 read you" is exactly as wrong as "0%".

/** The caller's own guess on one card, and whether it landed. Absent — `null` — when they did
 *  not guess that card, or could not guess at all. */
export interface MyGuessDTO {
  guessed_user_id: string;
  display_name: string;
  is_correct: boolean;
}

/**
 * One card, resolved: the song, whose it was, and how the room did on it.
 *
 * `eligible_guesser_count` is `S − 1` on every card in the round, not the number of people who
 * actually guessed this one. docs/02 §4.1: the denominator is every *other* submitter whether
 * or not they opened the sheet, "because a room that didn't look is a room that didn't read
 * you". A denominator that shrank to the people who tried would quietly make readability
 * measure enthusiasm instead.
 */
export interface ResultCardDTO {
  card_no: number;
  track: TrackDTO;
  owner: MemberDTO;
  correct_guess_count: number;
  eligible_guesser_count: number;
  my_guess: MyGuessDTO | null;
}

export function resultCardDTO(parts: {
  cardNo: number;
  meta: unknown;
  owner: MemberDTO;
  correctGuessCount: number;
  eligibleGuesserCount: number;
  myGuess: MyGuessDTO | null;
}): ResultCardDTO {
  return {
    card_no: parts.cardNo,
    track: trackDTO(parts.meta),
    owner: parts.owner,
    correct_guess_count: parts.correctGuessCount,
    eligible_guesser_count: parts.eligibleGuesserCount,
    my_guess: parts.myGuess,
  };
}

/**
 * The caller's own two numbers for the round, each with the fraction behind it.
 *
 * Both rates are decimals in `0..1` and the client formats them (docs/04 §4) — no percentage,
 * no rounding, no pre-formatted string. Two independent reasons a field here is `null`:
 *
 *   · `readability*` — the caller did not submit, so no card of theirs was in the room.
 *   · `ear*` — the caller submitted but assigned nothing, so `0/0`. docs/02 §4.1 drops that
 *     round from their average rather than scoring it zero.
 *
 * The counts are `null` alongside their rate rather than `0`, because the copy that consumes
 * them is `"%lld of %lld read you"` (docs/11) and there is no honest pair of numbers to put in
 * it. The client renders `results.readability.none` / `results.ear.none` instead.
 */
export interface PersonalScoreDTO {
  readability: number | null;
  readability_correct: number | null;
  readability_possible: number | null;
  ear: number | null;
  ear_correct: number | null;
  ear_possible: number | null;
}

/** A row in `round_scores`, or `null` when the caller has none — which is exactly the case of
 *  a member who did not submit. */
export interface RoundScoreRow {
  readability: number | null;
  readability_correct: number | null;
  ear: number | null;
  ear_correct: number | null;
  possible: number | null;
}

export function personalScoreDTO(row: RoundScoreRow | null): PersonalScoreDTO {
  // No row at all: not a submitter. Not a zero anywhere.
  if (!row) {
    return {
      readability: null,
      readability_correct: null,
      readability_possible: null,
      ear: null,
      ear_correct: null,
      ear_possible: null,
    };
  }
  const readable = row.readability !== null;
  const heard = row.ear !== null;
  return {
    readability: row.readability,
    readability_correct: readable ? row.readability_correct : null,
    readability_possible: readable ? row.possible : null,
    ear: row.ear,
    ear_correct: heard ? row.ear_correct : null,
    ear_possible: heard ? row.possible : null,
  };
}

/**
 * One submitter as the room sees them, so the results screen can show everybody at a glance
 * (docs/04 §4, "`people` is every submitter").
 *
 * Only submitters appear. Somebody who sat the round out has no card and could not guess, so
 * they have neither number — and a row of two dashes next to their name would read as a
 * scoreline rather than an absence.
 */
export interface PersonScoreDTO {
  user_id: string;
  display_name: string;
  readability: number | null;
  ear: number | null;
}

export function personScoreDTO(
  member: MemberDTO,
  row: { readability: number | null; ear: number | null },
): PersonScoreDTO {
  return {
    user_id: member.user_id,
    display_name: member.display_name,
    readability: row.readability,
    ear: row.ear,
  };
}

/** `GET /rounds/{round_id}/results` — docs/04 §4. */
export interface ResultsDTO {
  round_id: string;
  local_date: string;
  submitter_count: number;
  cards: ResultCardDTO[];
  me: PersonalScoreDTO;
  people: PersonScoreDTO[];
}

export function resultsDTO(
  round: { id: string; local_date: string },
  parts: {
    submitterCount: number;
    cards: ResultCardDTO[];
    me: PersonalScoreDTO;
    people: PersonScoreDTO[];
  },
): ResultsDTO {
  return {
    round_id: round.id,
    local_date: round.local_date,
    submitter_count: parts.submitterCount,
    cards: parts.cards,
    me: parts.me,
    people: parts.people,
  };
}

// ─── standings — docs/04 §4, docs/02 §4.5 ────────────────────────────────────

export type ReadabilityBand =
  | "open_book"
  | "legible"
  | "mixed_signals"
  | "hard_to_place"
  | "unreadable";

/**
 * A row in the Best Ear leaderboard. **Ranked**, ties sharing a rank and the next rank
 * skipping — 1, 2, 2, 4 (docs/04 §4).
 */
export interface EarStandingDTO {
  rank: number;
  user_id: string;
  display_name: string;
  ear_all_time: number;
  ear_correct_total: number;
}

export function earStandingDTO(
  rank: number,
  member: MemberDTO,
  row: { ear_all_time: number; ear_correct_total: number },
): EarStandingDTO {
  return {
    rank,
    user_id: member.user_id,
    display_name: member.display_name,
    ear_all_time: row.ear_all_time,
    ear_correct_total: row.ear_correct_total,
  };
}

/**
 * A row in the readability list, which **has no `rank` field and must never gain one.**
 *
 * docs/02 §4.5 makes this a product rule rather than a presentation preference: readability is
 * a spectrum, not a leaderboard, and low readability is its own kind of win. The array is
 * sorted descending purely so the list is stable between refreshes.
 *
 * The reason it is enforced here and asserted by test rather than left to the client is that a
 * client which *receives* a rank will render it — someone will reasonably assume a field that
 * exists is meant to be shown. The only durable way to not show a rank is to not send one.
 */
export interface ReadabilityStandingDTO {
  user_id: string;
  display_name: string;
  readability_all_time: number;
  band: ReadabilityBand;
}

export function readabilityStandingDTO(
  member: MemberDTO,
  row: { readability_all_time: number; band: ReadabilityBand },
): ReadabilityStandingDTO {
  return {
    user_id: member.user_id,
    display_name: member.display_name,
    readability_all_time: row.readability_all_time,
    band: row.band,
  };
}

/** `GET /groups/current/standings` — docs/04 §4. */
export interface StandingsDTO {
  rounds_played: number;
  best_ear: EarStandingDTO[];
  readability: ReadabilityStandingDTO[];
}

export function standingsDTO(
  roundsPlayed: number,
  bestEar: EarStandingDTO[],
  readability: ReadabilityStandingDTO[],
): StandingsDTO {
  return { rounds_played: roundsPlayed, best_ear: bestEar, readability };
}

export interface ProfileRateDTO {
  value: number | null;
  samples: number;
}

export interface ProfileTrackDTO {
  local_date: string;
  track: TrackDTO;
}

export interface PairwiseReadDTO {
  correct: number;
  possible: number;
}

/** `GET /groups/:group_id/members/:user_id/profile`, scoped entirely to scored rounds. */
export interface MemberProfileDTO {
  member: MemberDTO;
  ear: ProfileRateDTO;
  readability: ProfileRateDTO;
  drop_count: number;
  recent_tracks: ProfileTrackDTO[];
  you_read_them: PairwiseReadDTO | null;
  they_read_you: PairwiseReadDTO | null;
}

export function memberProfileDTO(parts: MemberProfileDTO): MemberProfileDTO {
  return {
    member: memberDTO(parts.member),
    ear: { ...parts.ear },
    readability: { ...parts.readability },
    drop_count: parts.drop_count,
    recent_tracks: parts.recent_tracks.map((entry) => ({
      local_date: entry.local_date,
      track: trackDTO(entry.track),
    })),
    you_read_them: parts.you_read_them && { ...parts.you_read_them },
    they_read_you: parts.they_read_you && { ...parts.they_read_you },
  };
}

// ─── Insights — E25-01 ─────────────────────────────────────────────────────

/**
 * One directed read across the scored rounds two people share in this circle.
 *
 * `lower_bound`/`upper_bound` are the Wilson score interval on `correct/possible` at 95%
 * confidence (`E28-07`) — carried alongside the raw counts, not instead of them, so the client
 * can rank the same array two different ways (`your_reads` sorted by the lower bound for "best",
 * by the upper bound for "hardest") without a second round trip or a second array.
 */
export interface InsightReadDTO {
  member: MemberDTO;
  correct: number;
  possible: number;
  lower_bound: number;
  upper_bound: number;
}

export function insightReadDTO(parts: InsightReadDTO): InsightReadDTO {
  return {
    member: memberDTO(parts.member),
    correct: parts.correct,
    possible: parts.possible,
    lower_bound: parts.lower_bound,
    upper_bound: parts.upper_bound,
  };
}

/** A two-way relationship. `possible` counts both directions, so 2 shared nights is 4 reads. */
export interface InsightPairDTO {
  members: MemberDTO[];
  correct: number;
  possible: number;
}

export function insightPairDTO(parts: InsightPairDTO): InsightPairDTO {
  return {
    members: parts.members.map(memberDTO),
    correct: parts.correct,
    possible: parts.possible,
  };
}

/** A repeated wrong attribution: the first member's card was named as the second member. */
export interface InsightConfusionPairDTO {
  actual_member: MemberDTO;
  mistaken_for_member: MemberDTO;
  count: number;
}

export function insightConfusionPairDTO(parts: InsightConfusionPairDTO): InsightConfusionPairDTO {
  return {
    actual_member: memberDTO(parts.actual_member),
    mistaken_for_member: memberDTO(parts.mistaken_for_member),
    count: parts.count,
  };
}

/** The gated confusion lens. Pairs stay empty until the circle has enough scored history. */
export interface InsightConfusionDTO {
  scored_rounds: number;
  minimum_rounds: number;
  pairs: InsightConfusionPairDTO[];
}

export function insightConfusionDTO(parts: InsightConfusionDTO): InsightConfusionDTO {
  return {
    scored_rounds: parts.scored_rounds,
    minimum_rounds: parts.minimum_rounds,
    pairs: parts.pairs.map(insightConfusionPairDTO),
  };
}

/**
 * `GET /groups/:group_id/insights`, derived entirely from scored rounds.
 *
 * **`E28-07` replaced the three single-best fields with two full, ranked arrays.** `you_know_best`
 * and `hardest_to_read` used to be two separate server-computed picks off the same underlying
 * set — the caller's read of every co-scored member — sorted two different ways; sending that set
 * once, with both Wilson bounds on every entry, lets the client derive both headline cards *and*
 * back a tap-through leaderboard for each stat without a second endpoint or a second array.
 * `your_reads.first` is "You read best"; `your_reads` sorted by `upper_bound` ascending is
 * "Hardest to read". `reads_you.first` is "Reads you best". Sort order is the server's, always —
 * a client re-sorting by a *different key already present in the payload* is picking a lens on
 * data it already has, not re-deriving a statistic the server is supposed to own.
 */
export interface InsightsDTO {
  your_reads: InsightReadDTO[];
  reads_you: InsightReadDTO[];
  mutual_recognition: InsightPairDTO[];
  mutual_misses: InsightPairDTO[];
  confusion: InsightConfusionDTO;
}

export function insightsDTO(parts: InsightsDTO): InsightsDTO {
  return {
    your_reads: parts.your_reads.map(insightReadDTO),
    reads_you: parts.reads_you.map(insightReadDTO),
    mutual_recognition: parts.mutual_recognition.map(insightPairDTO),
    mutual_misses: parts.mutual_misses.map(insightPairDTO),
    confusion: insightConfusionDTO(parts.confusion),
  };
}

// ─── The Record — docs/04 §5 ─────────────────────────────────────────────────

/**
 * One song in the archive, with whose it was.
 *
 * The name is on the entry rather than looked up from the roster, because The Record keeps its
 * attribution after somebody leaves (docs/02 §3): the night happened, and a page of songs
 * belonging to nobody is not an archive of it. `display_name` is `profiles`, which is where a
 * deleted account has already been anonymised in place (docs/03 §6).
 */
export interface RecordEntryDTO {
  user_id: string;
  display_name: string;
  track: TrackDTO;
}

export function recordEntryDTO(member: MemberDTO, meta: unknown): RecordEntryDTO {
  return {
    user_id: member.user_id,
    display_name: member.display_name,
    track: trackDTO(meta),
  };
}

/** One night, in full. `round_id` is here so the screen can link back to that night's results
 *  (docs/11 `record.results`) without a second lookup. */
export interface RecordDayDTO {
  local_date: string;
  round_id: string;
  entries: RecordEntryDTO[];
}

export function recordDayDTO(
  day: { local_date: string; round_id: string },
  entries: RecordEntryDTO[],
): RecordDayDTO {
  return { local_date: day.local_date, round_id: day.round_id, entries };
}

/**
 * `GET /groups/current/record` — docs/04 §5.
 *
 * **Only `scored` rounds are ever in here.** Tonight's `open` round is not an archive entry,
 * and a `voided` round never becomes one: its submissions came back to their owners unseen,
 * and publishing them a day later would retroactively break the blind window they were sealed
 * inside (CLAUDE.md §2.1). The filter is a `where` on a view that cannot see the other states
 * rather than a check in this file, so there is no branch here to get wrong.
 *
 * `next_cursor` is `null` on the last page — an absent cursor is the end of the archive, not
 * an error, and the client stops paging when it sees one.
 */
export interface RecordDTO {
  days: RecordDayDTO[];
  next_cursor: string | null;
}

export function recordDTO(days: RecordDayDTO[], nextCursor: string | null): RecordDTO {
  return { days, next_cursor: nextCursor };
}

/**
 * One track in an export, in the shape a playlist call needs and no other.
 *
 * Deliberately not a `TrackDTO`: artwork, previews, durations and album names are what The
 * Record renders, and none of them takes part in creating a playlist. The client sends
 * `spotify_uri`s to Spotify or `apple_music_id`s to MusicKit (docs/06 §6); `isrc`, `title` and
 * `artist` are here so a failed add can be reported as a song rather than as an identifier.
 */
export interface ExportTrackDTO {
  spotify_uri: string | null;
  apple_music_id: string | null;
  isrc: string | null;
  title: string;
  artist: string;
}

export function exportTrackDTO(track: TrackDTO): ExportTrackDTO {
  return {
    spotify_uri: track.spotify_id === null ? null : `spotify:track:${track.spotify_id}`,
    apple_music_id: track.apple_music_id === "" ? null : track.apple_music_id,
    isrc: track.isrc,
    title: track.title,
    artist: track.artist,
  };
}

/**
 * `GET /groups/current/record/export` — docs/04 §5, docs/06 §6.
 *
 * The server builds the *list*. It never creates the playlist and never holds a user's Spotify
 * or Apple Music credentials — the client does it with the user's own token, which is why
 * there is no write side to this endpoint at all.
 *
 * `unresolved_count` is the number of archive tracks with no id for the requested service.
 * They are skipped from `tracks` and **stated** (docs/11 `record.export.partial`): a song that
 * is not on Spotify is a fact about the catalog, and silently shipping a shorter playlist is
 * how somebody discovers it three weeks later.
 */
export interface ExportDTO {
  playlist_name: string;
  tracks: ExportTrackDTO[];
  unresolved_count: number;
}

export function exportDTO(
  playlistName: string,
  tracks: ExportTrackDTO[],
  unresolvedCount: number,
): ExportDTO {
  return { playlist_name: playlistName, tracks, unresolved_count: unresolvedCount };
}

// ─── shared field helpers ────────────────────────────────────────────────────

/** Every timestamp that reaches a client goes through here, so the wire format is one format
 *  (docs/04: RFC 3339 UTC with a `Z`). */
export function timestamp(value: string | Date): string {
  return rfc3339(value);
}
