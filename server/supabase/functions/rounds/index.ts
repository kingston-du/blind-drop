// rounds/index.ts — the blind window. docs/04 §4, docs/02 §2–3, docs/14 §3, ADR-011.
// tasks/E04-01, E04-02, E05-01, E05-02, E05-04, E18-01.
//
//   GET /current                          today's round for the caller's oldest circle
//   GET /{group_id}/current               the same, for a named circle
//   PUT /current/submission               drop or replace a song, oldest circle
//   PUT /{group_id}/current/submission    the same, for a named circle
//   PUT /current/guesses                  the guess sheet, whole-sheet upsert, oldest circle
//   PUT /{group_id}/current/guesses       the same, for a named circle
//   GET /{round_id}/results               the answers, for any scored round the caller
//                                          belongs to — resolves the round's own group first
//
// The `current` forms are compatibility for the shipped app until `E19` gives it a switcher;
// each shares one handler function with its `{group_id}` sibling and differs only in how
// `ctx.groupId` was resolved (`requireDefaultMembership` vs `requireMembership`).
//
// **Read the whole header before editing anything below it.**
//
// This is the file CLAUDE.md §2.1 exists to protect. During `open`, no response from here may
// contain another user's submission, a count of submissions, any member's submitted status, a
// timestamp derived from someone else's activity, or a payload length that varies with
// participation. Three consequences, all of which look like over-caution until you see how
// each one gets violated by an ordinary-looking change:
//
//   1. **Every query in the `open` path is keyed by the caller's own user id.** Not filtered
//      down to it afterwards — keyed by it, so the plan touches one row. A `select … where
//      round_id = X` that the handler then filters in TypeScript is not compliance: the
//      database did the work, the timing shows it, and the leak audit measures exactly that
//      correlation (docs/14 §3).
//   2. **There is no `count(*)` anywhere in this file**, including "just for the log". The
//      round's own state already encodes the only fact about participation anyone is entitled
//      to — that at reveal time there were three or there were not — and `tick_rounds()` is
//      what computed it, hours earlier, out of band.
//   3. **The response shape comes from `dto.ts` and the key set is asserted by golden file.**
//      Adding a field here requires editing two other files and updating a golden. That
//      friction is the control, not an inconvenience to route around.
//
// What this file does *not* do is decide phases. `requirePhase` reads `rounds.state`, which
// `tick_rounds()` wrote; no handler compares a clock to `reveals_at` to work out what phase
// it is (docs/02 §2, CLAUDE.md §2.2). A round is `revealed` because the server said so.

import {
  ApiError,
  ok,
  optional,
  parseBody,
  serveFunction,
  str,
  type Validator,
} from "../_shared/http.ts";
import {
  enforceRateLimit,
  type MemberCtx,
  type ProfileCtx,
  requireDefaultMembership,
  requireMembership,
  requirePhase,
  requireProfile,
  requireUser,
} from "../_shared/auth.ts";
import { dbFailure, isTrackAlreadyUsed } from "../_shared/db.ts";
import {
  type CannotGuessReason,
  type CardDTO,
  cardDTO,
  type CardGuessDTO,
  cueDTO,
  type GuessDTO,
  guessSheetDTO,
  type MemberDTO,
  memberDTO,
  type MyGuessDTO,
  personalScoreDTO,
  personScoreDTO,
  type PreviousRoundDTO,
  type ResultCardDTO,
  resultCardDTO,
  resultsDTO,
  revealedRoundDTO,
  roundDTO,
  type RoundScoreRow,
  type SubmissionDTO,
  submissionDTO,
} from "../_shared/dto.ts";
import { cardShortlist } from "../_shared/shortlist.ts";
import { localDate, type RoundState, serverNow } from "../_shared/time.ts";
import { storefrontFor } from "../_shared/music/appleMusic.ts";
import { resolveTrack } from "../_shared/music/resolve.ts";
import { linkTrack } from "../_shared/music/trackLinks.ts";

// docs/04 §8. Twenty a minute is far above anyone changing their mind and far below anything
// that costs us an Apple lookup per second.
const SUBMIT_LIMIT_PER_MINUTE = 20;
const ONE_MINUTE_IN_SECONDS = 60;

// docs/04 §8. Sixty a minute, against a client that debounces at 600ms: the sheet is meant to
// be edited freely while people think, and the limit is there for a stuck retry loop, not for
// a player.
const GUESS_LIMIT_PER_MINUTE = 60;

/** Comfortably above the twelve-member ceiling in docs/08, and bounded, which is the point —
 *  an unbounded array in a request body is a way to make the server do arbitrary work. */
const MAX_ASSIGNMENTS = 64;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

interface Assignment {
  card_no: number;
  /** `null` is a value here, not an omission: it is how a card is cleared (docs/04 §4). */
  guessed_user_id: string | null;
}

/**
 * The one nested body in this API, so its validator lives with its route rather than in
 * `_shared/http.ts`.
 *
 * It holds to the same rule as everything there: unknown keys are rejected, not ignored
 * (docs/14 §7). What it does *not* do is check that a `card_no` is in range or that a user id
 * is in the name pool — those need the round, which the parse step does not have, and they
 * happen in the handler in the order docs/04 §4 sets out.
 */
function assignmentList(): Validator<Assignment[]> {
  return {
    optional: false,
    parse(value, field) {
      if (!Array.isArray(value)) throw new ApiError("INVALID_INPUT", { field });
      if (value.length > MAX_ASSIGNMENTS) throw new ApiError("INVALID_INPUT", { field });

      return value.map((entry) => {
        if (entry === null || typeof entry !== "object" || Array.isArray(entry)) {
          throw new ApiError("INVALID_INPUT", { field });
        }
        const row = entry as Record<string, unknown>;
        for (const key of Object.keys(row)) {
          if (key !== "card_no" && key !== "guessed_user_id") {
            throw new ApiError("INVALID_INPUT", { field: key });
          }
        }
        if (typeof row.card_no !== "number" || !Number.isInteger(row.card_no)) {
          throw new ApiError("INVALID_INPUT", { field: "card_no" });
        }
        // Absent and explicitly null are the same thing here — both clear the card — because
        // a client that omits the key while sending the entry has said the same thing.
        const guessed = row.guessed_user_id ?? null;
        if (guessed !== null && (typeof guessed !== "string" || !UUID.test(guessed))) {
          throw new ApiError("INVALID_INPUT", { field: "guessed_user_id" });
        }
        return { card_no: row.card_no, guessed_user_id: guessed as string | null };
      });
    },
  };
}

interface RoundRow {
  id: string;
  local_date: string;
  state: RoundState;
  opens_at: string;
  reveals_at: string;
  scores_at: string;
  card_order: string[] | null;
  prompt_key: string | null;
  prompt: string | null;
}
const ROUND_COLUMNS =
  "id, local_date, state, opens_at, reveals_at, scores_at, card_order, prompt_key, prompt";

/**
 * Today's round, and whether the group it belongs to is the App Review demo group.
 *
 * `isDemo` rides along on the group read this function already does, so knowing it costs
 * nothing. It gates the two `demo_arm` calls below and nothing else — no branch in this file
 * shapes a response differently for a demo group, and the golden files are the check on that.
 */
interface CurrentRound {
  round: RoundRow;
  isDemo: boolean;
}

/**
 * Today's round for the caller's group, keyed by the group's *local* calendar date.
 *
 * Not "the round whose window contains now" — the group-local date, which is what docs/02 §1
 * makes the identity of a round and what `rounds_group_date` is unique on. Between the score
 * at 22:00 and the next open at 10:00 there is no live round, and this correctly returns
 * today's `scored` one until local midnight and tomorrow's not-yet-open one after it. docs/02
 * §1 is explicit that the dark hours are "not a state"; the client renders from `opens_at`,
 * which is in the future, and says so.
 *
 * The lookup below takes the earliest round dated `today` or later, not an exact match on
 * `today`, for the same reason `groups/index.ts`'s `circleCallerState` does: `ensure_rounds()`
 * refuses to create a round whose reveal has already passed (`0004_round_lifecycle.sql`'s
 * `where d.reveals_at > v_now`), so a group first read after its own `reveal_hour` — most
 * often a brand-new one — has a round dated tomorrow and none dated today. An exact match
 * against `today` misses that row and 404s a founding member out of their own first submission
 * until the calendar date rolls over; `today` or later still returns today's round first
 * whenever one exists (it always sorts before tomorrow's), so the dark-hours behaviour two
 * paragraphs up is unchanged — only the brand-new-and-late case stops 404ing.
 *
 * `ensure_rounds()` is called on a miss rather than 404ing, because the one moment a round can
 * legitimately be absent is the first minute of a brand-new group — the scheduler runs each
 * minute (docs/03 §4) and the API is not going to make the founding member wait for it.
 *
 * A demo group gets `demo_tick()` instead, and gets it *before* the lookup rather than on a
 * miss. `tick_rounds()` does not run for demo groups (20260815090000), so this call is the
 * only thing that advances one — the reveal the reviewer's countdown is waiting on happens
 * here, on the refetch that countdown triggers. It is still the server deciding the phase:
 * the handler below reads `rounds.state` exactly as it does for everybody else, and never
 * compares a clock (CLAUDE.md §2.2).
 */
async function currentRound(ctx: MemberCtx): Promise<CurrentRound> {
  const { data: group, error: groupError } = await ctx.db
    .from("groups")
    .select("timezone, is_demo")
    .eq("id", ctx.groupId)
    .maybeSingle();
  if (groupError) throw dbFailure("rounds.group", groupError);
  if (!group) throw new ApiError("NOT_FOUND");

  const isDemo = group.is_demo === true;
  const today = localDate(group.timezone, serverNow());

  const load = async (): Promise<RoundRow | null> => {
    const { data, error } = await ctx.db
      .from("rounds")
      .select(ROUND_COLUMNS)
      .eq("group_id", ctx.groupId)
      .gte("local_date", today)
      .order("local_date", { ascending: true })
      .limit(1)
      .maybeSingle();
    if (error) throw dbFailure("rounds.current", error);
    return data;
  };

  if (isDemo) {
    const { error: tickError } = await ctx.db.rpc("demo_tick", { p_group_id: ctx.groupId });
    if (tickError) throw dbFailure("rounds.demo_tick", tickError);
    const ticked = await load();
    if (!ticked) throw new ApiError("NOT_FOUND");
    return { round: ticked, isDemo };
  }

  const existing = await load();
  if (existing) return { round: existing, isDemo };

  const { error: ensureError } = await ctx.db.rpc("ensure_rounds");
  if (ensureError) throw dbFailure("rounds.ensure_rounds", ensureError);

  const created = await load();
  if (!created) throw new ApiError("NOT_FOUND");
  return { round: created, isDemo };
}

/**
 * How long a demo round waits before its next transition, in seconds. docs/02 §6.
 *
 * Long enough that the screen it is on registers as a screen — the seal lands, the stamp
 * animates, the countdown is visibly a countdown — and short enough that a reviewer never
 * wonders whether the app has stopped. `DEMO_GUESS_CAP_SECONDS` is the backstop for a sheet
 * that is never completed, so the loop always finishes even if the reviewer wanders off
 * mid-guess.
 */
const DEMO_SEAL_SECONDS = 12;
const DEMO_GUESS_SECONDS = 20;
const DEMO_GUESS_CAP_SECONDS = 180;

/** Brings a demo round's next transition forward. A no-op for every real group — the guard is
 *  here *and* in `demo_arm()` itself, which refuses any round outside a demo group. */
async function armDemo(ctx: MemberCtx, roundId: string, seconds: number): Promise<void> {
  const { error } = await ctx.db.rpc("demo_arm", { p_round_id: roundId, p_seconds: seconds });
  if (error) throw dbFailure("rounds.demo_arm", error);
}

/**
 * The caller's own submission in a round, or `null`.
 *
 * One row, keyed by `(round_id, user_id)` on a unique index. It is the only read of
 * `submissions` in the `open` path and it can only ever see one row: the caller's. That is the
 * property that makes the timing channel in docs/14 §3 flat — the cost of this query does not
 * change when eleven other people submit, because it never looked at them.
 */
async function mySubmission(ctx: MemberCtx, roundId: string): Promise<SubmissionDTO | null> {
  const { data, error } = await ctx.db
    .from("submissions")
    .select("track_meta, updated_at")
    .eq("round_id", roundId)
    .eq("user_id", ctx.userId)
    .maybeSingle();
  if (error) throw dbFailure("rounds.mySubmission", error);
  return data ? submissionDTO(data) : null;
}

// ─── the reveal ──────────────────────────────────────────────────────────────
// Everything below this line runs only when `rounds.state` is already `revealed` or `scored`.
// The guard is `requirePhase` against the stored state, never a clock comparison: `card_order`
// exists because `tick_rounds()` wrote it at the transition, and its existence is the fact
// that the blind window is over (docs/02 §2).

interface CardRow {
  id: string;
  user_id: string;
  track_meta: unknown;
}

/**
 * The round's submissions, in `card_order`.
 *
 * `card_order` is the authority, not the shuffle seed and not any ordering the database
 * happens to return — it was generated once at the reveal, stored, and is identical for every
 * member (docs/02 §2). Position `i` is `card_no = i + 1`.
 *
 * A submission missing from `card_order` cannot happen: `rounds_card_order_is_permutation_trg`
 * (0002) is a deferred constraint trigger that makes it unwritable. The filter below is
 * therefore not defensive coding but a statement of what the mapping means — every card comes
 * from the stored order, and nothing else gets a number.
 */
async function cardsInOrder(
  ctx: MemberCtx,
  round: RoundRow,
): Promise<{
  cards: CardDTO[];
  rows: Map<string, CardRow>;
  order: string[];
  submitterIds: string[];
}> {
  const order = round.card_order ?? [];
  const { data, error } = await ctx.db
    .from("submissions")
    .select("id, user_id, track_meta")
    .eq("round_id", round.id);
  if (error) throw dbFailure("rounds.cards", error);

  const rows = new Map<string, CardRow>((data as CardRow[]).map((row) => [row.id, row]));
  // Every submitter in the round, in `card_order`. The shortlist draws from this and nothing
  // else, so a member who has since left the circle is still a candidate — the round happened,
  // and `namePool` keeps them for the same reason.
  const submitterIds = order
    .map((id) => rows.get(id)?.user_id)
    .filter((id): id is string => !!id);
  const cards = order
    .map((submissionId, index) => {
      const row = rows.get(submissionId);
      if (!row) return null;
      return cardDTO(
        index + 1,
        row.track_meta,
        cardShortlist({
          roundId: round.id,
          cardNo: index + 1,
          ownerId: row.user_id,
          viewerId: ctx.userId,
          submitterIds,
        }),
      );
    })
    .filter((card): card is CardDTO => card !== null);

  return { cards, rows, order, submitterIds };
}

/**
 * Display names for a set of user ids, in name order.
 *
 * Names come from `profiles` rather than from the roster, so someone who has since left the
 * group still appears under the name they had — the round happened, and a hole in it would
 * make the game unsolvable for everyone else (docs/02 §3, "historical rounds keep their
 * attribution"). A deleted account is anonymised to `Former member` in place (docs/03 §6), so
 * the row is always there to find.
 *
 * The `Map` preserves insertion order, which is the sort order, so callers that want a list
 * get one already sorted and callers that want a lookup do not pay for a second query.
 */
async function profilesByIds(ctx: MemberCtx, ids: string[]): Promise<Map<string, MemberDTO>> {
  if (ids.length === 0) return new Map();
  const { data, error } = await ctx.db
    .from("profiles")
    .select("id, display_name")
    .in("id", ids)
    .order("display_name", { ascending: true })
    .order("id", { ascending: true });
  if (error) throw dbFailure("rounds.profiles", error);
  return new Map(
    data.map((p) => [p.id as string, memberDTO({ user_id: p.id, display_name: p.display_name })]),
  );
}

/** The name pool: exactly this round's submitters, the caller included (docs/02 §3). */
async function namePool(ctx: MemberCtx, submitterIds: string[]): Promise<MemberDTO[]> {
  return [...(await profilesByIds(ctx, submitterIds)).values()];
}

/** The caller's own saved sheet, translated from submission ids to card numbers. Keyed by
 *  `guesser_id`, so it can only ever return the caller's rows. */
async function myGuesses(ctx: MemberCtx, round: RoundRow, order: string[]): Promise<GuessDTO[]> {
  const { data, error } = await ctx.db
    .from("guesses")
    .select("submission_id, guessed_user_id")
    .eq("round_id", round.id)
    .eq("guesser_id", ctx.userId);
  if (error) throw dbFailure("rounds.myGuesses", error);

  return data
    .map((g) => ({
      card_no: order.indexOf(g.submission_id) + 1,
      guessed_user_id: g.guessed_user_id,
    }))
    .filter((g) => g.card_no > 0)
    .sort((a, b) => a.card_no - b.card_no);
}

/**
 * The round immediately before this one — its id, its state and its cue — or `null`.
 *
 * Only ever called for a round that has not opened yet — see `currentRoundResponse`. One row,
 * keyed by `(group_id, local_date)`, reading nothing but the identity, the state and the two
 * frozen cue columns: no submission, no guess, no count. A finished round's cue is already
 * public on that night's results and in the Record, and so is its id, so this hands out nothing
 * new; it just puts both where the screen that is talking about that night can render them.
 *
 * `null` when there is no earlier round — a circle's first night. **Not** `null` for a round
 * that merely had no cue: the id is still wanted, and `roundDTO` drops each of the two keys on
 * its own terms (cue when there is one, id when that round scored).
 *
 * **The most recent earlier round, not yesterday's specifically**, and that is deliberate. The
 * screen's subject is *"the round that just ended"*, which is this one whether or not a night
 * was skipped; an adjacency filter would answer `null` — no card at all — in exactly the case
 * where there is still a last round to name. `ensure_rounds()` creates one round per circle per
 * day, so in practice the two are the same row and the copy's *"Last night's"* is literal; if a
 * night were ever genuinely missed, only that one word is approximate.
 */
async function previousRound(ctx: MemberCtx, round: RoundRow): Promise<PreviousRoundDTO | null> {
  const { data, error } = await ctx.db
    .from("rounds")
    .select("id, state, prompt_key, prompt")
    .eq("group_id", ctx.groupId)
    .lt("local_date", round.local_date)
    .order("local_date", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) throw dbFailure("rounds.previousRound", error);
  if (!data) return null;
  return { id: data.id, state: data.state as RoundState, cue: cueDTO(data) };
}

/**
 * `GET /current` and `GET /:group_id/current`'s shared body — the two entries differ only in
 * how `ctx.groupId` was resolved (`requireDefaultMembership` vs `requireMembership`).
 *
 * **The dark hours get one extra key.** Between local midnight and `opens_at` this endpoint
 * already returns the *coming* night's round (see `currentRound`), and the client draws
 * *"Tonight's round is done."* over it — so the cue on the base keys is the brief for a round
 * nobody has dropped against yet, and the screen showing it would be handing it out hours
 * early. `previous_cue` is the one that night is actually about, and `previous_round_id` is the
 * way through to that night's results — the only one that screen has, since `round_id` up there
 * is the coming night's. The id is gated on that round being `scored`, which is why the two keys
 * come off one lookup rather than two: a `voided` night has a cue and no results, and an uncued
 * night that scored has results and no cue. Reading a clock here decides
 * a *payload*, never a phase: `round.state` is still whatever `tick_rounds()` wrote, and
 * `opens_at` is the same instant the client is already counting down to (CLAUDE.md §2.2).
 *
 * Nothing is added once the round has opened, so the blind window's payload — the one docs/14
 * §3 times and `roundFields()` pins — is byte-for-byte unchanged.
 */
async function currentRoundResponse(ctx: MemberCtx): Promise<Response> {
  const { round } = await currentRound(ctx);
  const mine = await mySubmission(ctx, round.id);
  const isBeforeOpen = round.state === "open" && new Date(round.opens_at) > serverNow();
  const base = roundDTO(round, mine, isBeforeOpen ? await previousRound(ctx, round) : null);
  if (round.state !== "revealed") return ok(base);

  const { cards, rows, order, submitterIds } = await cardsInOrder(ctx, round);
  const mySubmissionId = order.find((id) => rows.get(id)?.user_id === ctx.userId) ?? null;

  return ok(
    revealedRoundDTO(base, {
      myCardNo: mySubmissionId === null ? null : order.indexOf(mySubmissionId) + 1,
      cannotGuessReason: cannotGuessReason(ctx, round, mySubmissionId),
      cards,
      namePool: await namePool(ctx, submitterIds),
      myGuesses: await myGuesses(ctx, round, order),
    }),
  );
}

// ─── the answers ─────────────────────────────────────────────────────────────
// `GET /{round_id}/results` is the only route in this file that takes an id from the caller,
// and the only one that reads the scoring views. Both facts get their own guard below.

/**
 * A round the caller belongs to, by id, or `NOT_FOUND`.
 *
 * Multi-circle (ADR-011) means the caller's default membership is no longer necessarily the
 * round's own group, so authorization can no longer be "one query filtered by the caller's
 * one `group_id`" the way `roundInMyGroup` had it under ADR-005. It stays a single round
 * query all the same: the caller's own active circles are fetched first — keyed by their own
 * `user_id`, so that lookup's cost never varies with which round was asked about — and the
 * round is then loaded filtered to `id` **and** that set of circles in one call. A round
 * belonging to a circle the caller does not belong to and a round that does not exist cost
 * the same round query and land at the same `NOT_FOUND`, so there is no id to probe with by
 * status, body, *or* timing (docs/14 §3, §4).
 *
 * A malformed id gets the same `NOT_FOUND` rather than `INVALID_INPUT`, which is why the shape
 * is checked here instead of being left to Postgres — an unparseable uuid reaching the database
 * is a `22P02` and therefore a 500, and a route that answers 500 for garbage and 404 for a real
 * id somewhere else has just told the caller which is which.
 */
async function requireRoundMembership(
  profileCtx: ProfileCtx,
  roundId: string,
): Promise<{ ctx: MemberCtx; round: RoundRow }> {
  if (!UUID.test(roundId)) throw new ApiError("NOT_FOUND");

  const { data: memberships, error: membershipError } = await profileCtx.db
    .from("memberships")
    .select("group_id, role, joined_at")
    .eq("user_id", profileCtx.userId)
    .is("left_at", null);
  if (membershipError) {
    throw dbFailure("rounds.requireRoundMembership.memberships", membershipError);
  }
  const byGroup = new Map(memberships.map((m) => [m.group_id, m]));
  const groupIds = [...byGroup.keys()];
  if (groupIds.length === 0) throw new ApiError("NOT_FOUND");

  const { data, error } = await profileCtx.db
    .from("rounds")
    .select(`${ROUND_COLUMNS}, group_id`)
    .eq("id", roundId)
    .in("group_id", groupIds)
    .maybeSingle();
  if (error) throw dbFailure("rounds.byId", error);
  if (!data) throw new ApiError("NOT_FOUND");

  const { group_id, ...round } = data as RoundRow & { group_id: string };
  const membership = byGroup.get(group_id)!;
  return {
    ctx: { ...profileCtx, groupId: group_id, role: membership.role, joinedAt: membership.joined_at },
    round: round as RoundRow,
  };
}

interface GuessResultRow {
  submission_id: string;
  guesser_id: string;
  guessed_user_id: string;
  is_correct: boolean;
}

/**
 * Every guess in the round, with `docs/02 §4.3` already applied by `guess_results` (0005).
 *
 * Reading the whole round's guesses is fine *here* and would be a serious leak two hours
 * earlier, which is the difference `requirePhase(round, ["scored"])` above the call site makes.
 * Correctness in particular is not recomputed in TypeScript: the duplicate rule — a guess is
 * correct iff the named person submitted *that track*, not iff they own the card — lives in the
 * view, so the number on the results screen and the number in the standings cannot disagree.
 */
async function guessResults(ctx: MemberCtx, roundId: string): Promise<GuessResultRow[]> {
  const { data, error } = await ctx.db
    .from("guess_results")
    .select("submission_id, guesser_id, guessed_user_id, is_correct")
    .eq("round_id", roundId);
  if (error) throw dbFailure("rounds.guessResults", error);
  return data as GuessResultRow[];
}

interface ScoreRow extends RoundScoreRow {
  user_id: string;
}

/** One row per submitter, from `round_scores` (0005). Non-submitters are absent by
 *  construction — they have no card and could not guess, so they have neither number. */
async function roundScores(ctx: MemberCtx, roundId: string): Promise<Map<string, ScoreRow>> {
  const { data, error } = await ctx.db
    .from("round_scores")
    .select("user_id, readability, readability_correct, ear, ear_correct, possible")
    .eq("round_id", roundId);
  if (error) throw dbFailure("rounds.roundScores", error);
  return new Map((data as ScoreRow[]).map((row) => [row.user_id, row]));
}

/**
 * Competition ranking: ties share a rank and the next rank skips it — 1, 2, 2, 4 (docs/04 §4).
 * Same rule as `groups/index.ts`'s `ranked()`, kept local here rather than shared: that helper
 * is typed to the all-time `ear_all_time` column, this round's rate lives in a differently
 * named field, and this is its only other caller.
 */
function rankedByEar<T>(rows: T[], earOf: (row: T) => number): { rank: number; row: T }[] {
  let rank = 0;
  let previous: number | null = null;
  return rows.map((row, index) => {
    const ear = earOf(row);
    if (previous === null || ear !== previous) rank = index + 1;
    previous = ear;
    return { rank, row };
  });
}

/**
 * Why the caller may not guess, or `null` if they may. docs/02 §3, docs/04 §4.
 *
 * **`joined_late` is checked first, matching the owner-approved order in docs/04 §4.**
 * The short version: joining after `reveals_at` implies
 * having no submission — you cannot submit to a round that is no longer `open` — so checking
 * for a submission first makes `joined_late` unreachable for everyone except the rare member
 * who submitted, left, and rejoined the same evening. A reason code that can never be returned
 * is a reason code that does not exist, and its copy ("You joined after the reveal. You're in
 * from tomorrow.") is the true and kinder thing to tell a new member, where "You didn't drop a
 * song tonight" blames them for a window they were not present for.
 *
 * Neither ordering discloses anything: both facts are the caller's own.
 *
 * Both are states of the round rather than errors — `GET /current` reports them so the client
 * can render a disabled sheet with an explanation instead of hiding the feature (docs/02 §3).
 */
function cannotGuessReason(
  ctx: MemberCtx,
  round: RoundRow,
  mySubmissionId: string | null,
): CannotGuessReason | null {
  if (new Date(ctx.joinedAt).getTime() >= new Date(round.reveals_at).getTime()) {
    return "joined_late";
  }
  if (!mySubmissionId) return "not_a_submitter";
  return null;
}

// ─── the shared write handlers ────────────────────────────────────────────────
// One function per route, called from both its `current`-shaped and its `:group_id`-shaped
// entry — the two differ only in how `ctx.groupId` was resolved, never in what happens after.

async function submitTrack(req: Request, ctx: MemberCtx): Promise<Response> {
  await enforceRateLimit(
    ctx.db,
    `submit:u:${ctx.userId}`,
    SUBMIT_LIMIT_PER_MINUTE,
    ONE_MINUTE_IN_SECONDS,
  );

  const body = await parseBody(req, {
    apple_music_id: optional(str({ min: 1, max: 32 })),
    spotify_url: optional(str({ min: 1, max: 512 })),
    isrc: optional(str({ min: 1, max: 24 })),
  });

  const { round, isDemo } = await currentRound(ctx);
  // `open` and nothing else. `voided` gets its own code, and `revealed`/`scored` get
  // `WRONG_PHASE` carrying the state and — by construction in `fail()` — nothing else.
  requirePhase(round, ["open"]);

  const resolved = await resolveTrack(storefrontFor(req), body);
  // Inline, 700ms, and structurally unable to fail the submission: `linkTrack` turns every
  // upstream problem into "no Spotify link yet" and leaves a `track_links` row for the
  // backfill (docs/06 §5, E07-05).
  const track = await linkTrack(ctx.db, resolved);

  // One upsert on `(round_id, user_id)`. Replacement is this same call — there is no
  // separate route, no announcement and no counter (docs/02 §3) — and repeating an
  // unchanged song does not move `sealed_at`, which is why this is a function rather than a
  // PostgREST upsert (0018).
  //
  // **A duplicate track within one round is never rejected.** If somebody else already
  // dropped this song this round the write succeeds exactly as if nobody had: the rejection
  // itself would be the leak (docs/02 §3), and the response is byte-identical either way
  // because nothing in it is derived from another row.
  //
  // **Across circles it can be refused, narrowly.** `upsert_submission` (E18-03) raises BD003
  // when this user already used this exact track tonight in a *different* circle that shares
  // another active member with this one — the one case where the repeat itself would let a
  // third person line up two reveals. The refusal names no circle and nobody else. The SQL
  // that decides this runs unconditionally, on both the accepted and the refused path, so it
  // is structurally the same cost either way — that property is not separately timed, the way
  // `leak_timing.test.ts` times `GET /rounds/current`; the only party who could observe this
  // response's latency is the caller themselves, who already sees the refusal in the body.
  const { data, error } = await ctx.db
    .rpc("upsert_submission", {
      p_round_id: round.id,
      p_user_id: ctx.userId,
      p_track_key: track.track_key,
      p_track_meta: track,
    })
    .single();
  if (error) {
    if (isTrackAlreadyUsed(error)) throw new ApiError("TRACK_ALREADY_USED");
    throw dbFailure("rounds.submit", error);
  }

  // The demo group's reveal is the reviewer's own drop, twelve seconds later. Nothing about
  // the response changes — the client adopts it, renders `SealedScreen`, and that screen's
  // countdown to `reveals_at` is simply short. The transition itself still happens on the
  // server, on the refetch the countdown triggers.
  if (isDemo) await armDemo(ctx, round.id, DEMO_SEAL_SECONDS);

  return ok(submissionDTO(data as { track_meta: unknown; updated_at: string }));
}

// A whole-sheet upsert: the client sends the sheet as it currently stands and the server
// diffs. docs/04 §4 lists seven validations and they are implemented in that order, so the
// error a client gets for a request that breaks two rules is predictable.
//
// Everything is addressed by `card_no`. The client has never seen a submission id (ADR-003)
// and the server resolves numbers against the round's own `card_order`, which means an
// out-of-range number is caught by arithmetic rather than by a lookup that might succeed
// against some other round's row.
async function saveGuesses(req: Request, ctx: MemberCtx): Promise<Response> {
  await enforceRateLimit(
    ctx.db,
    `guess:u:${ctx.userId}`,
    GUESS_LIMIT_PER_MINUTE,
    ONE_MINUTE_IN_SECONDS,
  );

  const body = await parseBody(req, { assignments: assignmentList() });
  const { round, isDemo } = await currentRound(ctx);

  // 1. Phase. Guesses are editable until `scores_at`, which is to say for exactly as long as
  //    the round is `revealed` — `tick_rounds()` moves it to `scored` at that instant and
  //    this stops accepting writes without a clock comparison of its own (docs/02 §2).
  requirePhase(round, ["revealed"]);

  const { rows, order } = await cardsInOrder(ctx, round);
  const owners = order.map((id) => rows.get(id)?.user_id ?? null);
  const mySubmissionId = order.find((id) => rows.get(id)?.user_id === ctx.userId) ?? null;

  // 2 and 3. Only submitters may guess, and only those who were in the round before it
  //    revealed — enforced here, server-side, not merely disabled in the UI (CLAUDE.md §2.3).
  //    The same helper as the read path, so the code a write is refused with and the reason
  //    the sheet is shown as disabled can never disagree. On the ordering, see its comment
  //    and the owner-approved resolution in tasks/E05.
  const reason = cannotGuessReason(ctx, round, mySubmissionId);
  if (reason === "joined_late") throw new ApiError("JOINED_LATE");
  if (reason === "not_a_submitter") throw new ApiError("NOT_A_SUBMITTER");

  const pool = new Set(owners.filter((id): id is string => id !== null));
  const myCardNo = mySubmissionId === null ? null : order.indexOf(mySubmissionId) + 1;

  const toUpsert: { submission_id: string; guessed_user_id: string }[] = [];
  const toClear: string[] = [];

  for (const assignment of body.assignments) {
    // 4. `card_no` in 1..N, and not the caller's own card. Guessing at your own song is
    //    meaningless and the `guesses_not_self` trigger (0002) would refuse it anyway; this
    //    turns a database exception into the documented 400.
    if (assignment.card_no < 1 || assignment.card_no > order.length) {
      throw new ApiError("INVALID_INPUT", { field: "card_no" });
    }
    if (assignment.card_no === myCardNo) {
      throw new ApiError("INVALID_INPUT", { field: "card_no" });
    }
    const submissionId = order[assignment.card_no - 1];

    // 7. An omitted `card_no` is left untouched; an explicit null clears that card. This is
    //    what makes the endpoint safe to call with a partial sheet, which the client does on
    //    every debounce.
    if (assignment.guessed_user_id === null) {
      toClear.push(submissionId);
      continue;
    }

    // 5. The named person must be in this round's name pool, and must not be the caller.
    //    The pool is the round's submitters — naming somebody who sat the round out is not a
    //    wrong guess, it is a malformed one.
    if (!pool.has(assignment.guessed_user_id) || assignment.guessed_user_id === ctx.userId) {
      throw new ApiError("INVALID_INPUT", { field: "guessed_user_id" });
    }

    // 6. Duplicates across two cards are *allowed*, deliberately: players double-assign
    //    while they think, the UI discourages it, and scoring handles it naturally
    //    (docs/04 §4). There is no check here and there should not be one.
    toUpsert.push({ submission_id: submissionId, guessed_user_id: assignment.guessed_user_id });
  }

  if (toClear.length > 0) {
    const { error } = await ctx.db
      .from("guesses")
      .delete()
      .eq("round_id", round.id)
      .eq("guesser_id", ctx.userId)
      .in("submission_id", toClear);
    if (error) throw dbFailure("rounds.guesses.clear", error);
  }

  if (toUpsert.length > 0) {
    const now = serverNow().toISOString();
    const { error } = await ctx.db.from("guesses").upsert(
      toUpsert.map((g) => ({
        round_id: round.id,
        guesser_id: ctx.userId,
        submission_id: g.submission_id,
        guessed_user_id: g.guessed_user_id,
        updated_at: now,
      })),
      { onConflict: "round_id,guesser_id,submission_id" },
    );
    if (error) throw dbFailure("rounds.guesses.upsert", error);
  }

  // The sheet as it now stands, read back rather than reconstructed from the request — a
  // partial update means the response is not a function of the body alone.
  const saved = await myGuesses(ctx, round, order);
  // `assignable_count` is S − 1: every card the caller could be asked about (docs/02 §4.1).
  // It is derived from the round's own card count, which the caller can already see in
  // `cards`, so it discloses nothing they did not have.
  const assignableCount = Math.max(order.length - 1, 0);

  // The demo group's score lands twenty seconds after the sheet is complete — which is the
  // same request `RevealStore.lockIn()` sends, since it flushes the whole sheet immediately.
  // A partial sheet gets the three-minute backstop instead, so the loop finishes even for a
  // reviewer who names two cards and puts the phone down. Re-armed on every write, so
  // changing a guess restarts the wait rather than losing it.
  if (isDemo) {
    await armDemo(
      ctx,
      round.id,
      saved.length >= assignableCount ? DEMO_GUESS_SECONDS : DEMO_GUESS_CAP_SECONDS,
    );
  }

  return ok(guessSheetDTO(saved, assignableCount));
}

serveFunction("rounds", {
  // ─── the workhorse ─────────────────────────────────────────────────────────
  // The client calls this on launch, on foreground, and when a countdown reaches zero.
  //
  // `open` and `voided` share one shape and this handler serves both with the same code path
  // — not by coincidence, but so that there is no branch where a `voided` payload could grow a
  // field an `open` one does not have. A voided round returns the caller's own song, unseen
  // and unscored, and **no count of how many did submit**: "only 2 dropped" identifies people
  // in a group of eight (docs/08 §5).
  //
  // `revealed` widens the payload — cards, the name pool, the caller's sheet — because at that
  // point the blind window is over and docs/02 §3 accepts that participation becomes visible.
  // `scored` returns the base shape and the client fetches `GET /rounds/{id}/results`
  // separately (E05-04), which keeps the launch call small and lets the results screen be
  // deep-linked from the push.
  "GET /current": async (req, route) => {
    const ctx = await requireDefaultMembership(await requireProfile(await requireUser(req, route)));
    return currentRoundResponse(ctx);
  },
  "GET /:group_id/current": async (req, route, params) => {
    const ctx = await requireMembership(
      await requireProfile(await requireUser(req, route)),
      params.group_id,
    );
    return currentRoundResponse(ctx);
  },

  // ─── the answers ───────────────────────────────────────────────────────────
  // `GET /{round_id}/results` — docs/04 §4. The only route here that takes an id, and the only
  // one that serves a round other than today's: The Record links back into a night from three
  // weeks ago and gets the same payload it got that evening.
  //
  // `scored` and nothing else. A `revealed` round is refused even though its cards are already
  // public, because its guess sheets are still being edited — the answers do not exist yet, and
  // half-scored numbers shown once cannot be un-shown. The refusal carries the round's state
  // and, by construction in `fail()`, nothing else: no cards, no counts, no names.
  "GET /:round_id/results": async (req, route, params) => {
    const profileCtx = await requireProfile(await requireUser(req, route));
    const { ctx, round } = await requireRoundMembership(profileCtx, params.round_id);
    requirePhase(round, ["scored"]);

    const { rows, order } = await cardsInOrder(ctx, round);
    const submitterIds = order
      .map((id) => rows.get(id)?.user_id)
      .filter((id): id is string => id !== undefined);

    const [results, scores, profiles] = await Promise.all([
      guessResults(ctx, round.id),
      roundScores(ctx, round.id),
      profilesByIds(ctx, submitterIds),
    ]);

    // Every card carries the same denominator: S − 1, every *other* submitter, whether or not
    // they opened the sheet (docs/02 §4.1).
    const eligibleGuesserCount = Math.max(order.length - 1, 0);

    // The card the caller owns, if any — `guesses` (E29-01) is populated on that one card only,
    // the same restriction `my_guess` already draws in the other direction.
    const mySubmissionId = order.find((id) => rows.get(id)?.user_id === ctx.userId) ?? null;

    const correctBySubmission = new Map<string, number>();
    const mineBySubmission = new Map<string, GuessResultRow>();
    const guessesOnMine: GuessResultRow[] = [];
    for (const result of results) {
      if (result.is_correct) {
        correctBySubmission.set(
          result.submission_id,
          (correctBySubmission.get(result.submission_id) ?? 0) + 1,
        );
      }
      if (result.guesser_id === ctx.userId) mineBySubmission.set(result.submission_id, result);
      if (mySubmissionId !== null && result.submission_id === mySubmissionId) {
        guessesOnMine.push(result);
      }
    }

    const unknown = (userId: string): MemberDTO =>
      profiles.get(userId) ?? memberDTO({ user_id: userId, display_name: "" });

    // Every guesser is necessarily a submitter (`CLAUDE.md` §2 rule 3, "only submitters may
    // guess"), so `profiles` — already scoped to this round's submitters — names them too.
    // Sorted by guesser name — `guess_results` carries no ordering guarantee of its own, and
    // "in name order" is the same convention `people` already uses below.
    const guesses: CardGuessDTO[] = guessesOnMine
      .map((result) => ({
        guesser_id: result.guesser_id,
        guesser_name: unknown(result.guesser_id).display_name,
        guessed_user_id: result.guessed_user_id,
        guessed_name: unknown(result.guessed_user_id).display_name,
        is_correct: result.is_correct,
      }))
      .sort((a, b) => a.guesser_name.localeCompare(b.guesser_name));

    const cards: ResultCardDTO[] = order.map((submissionId, index) => {
      const row = rows.get(submissionId);
      const mine = mineBySubmission.get(submissionId);
      const myGuess: MyGuessDTO | null = mine
        ? {
          guessed_user_id: mine.guessed_user_id,
          display_name: unknown(mine.guessed_user_id).display_name,
          is_correct: mine.is_correct,
        }
        : null;
      return resultCardDTO({
        cardNo: index + 1,
        meta: row?.track_meta,
        owner: unknown(row?.user_id ?? ""),
        correctGuessCount: correctBySubmission.get(submissionId) ?? 0,
        eligibleGuesserCount,
        myGuess,
        guesses: submissionId === mySubmissionId ? guesses : null,
      });
    });

    // `people` is every submitter, in name order, so the screen can show the room at a glance.
    // It is driven by the profile list rather than by the score map so that the ordering is the
    // one the rest of the API uses, and so a submitter whose row the view somehow lacked would
    // be visibly absent rather than silently dropped from the middle of an ordered list.
    const people = [...profiles.values()]
      .map((member) => {
        const score = scores.get(member.user_id);
        return score === undefined ? null : personScoreDTO(member, score);
      })
      .filter((person) => person !== null);

    // Tonight's top 3 by Ear, this round only — never readability (`docs/02` §4.5). A member
    // with no ear this round (sat the guessing out entirely) is absent rather than ranked last
    // with a dash, the same rule `groups/index.ts`'s all-time Best Ear draws.
    const tonightRows = [...scores.entries()]
      .filter(([, score]) => score.ear !== null)
      .map(([userId, score]) => ({ member: unknown(userId), ear: score.ear! }))
      .sort((a, b) =>
        b.ear - a.ear ||
        a.member.display_name.localeCompare(b.member.display_name) ||
        a.member.user_id.localeCompare(b.member.user_id)
      );
    const tonightTopEar = rankedByEar(tonightRows, (row) => row.ear)
      .filter(({ rank }) => rank <= 3)
      .map(({ rank, row }) => ({
        rank,
        user_id: row.member.user_id,
        display_name: row.member.display_name,
        ear: row.ear,
      }));

    return ok(
      resultsDTO(round, {
        submitterCount: order.length,
        cards,
        me: personalScoreDTO(scores.get(ctx.userId) ?? null),
        people,
        tonightTopEar,
      }),
    );
  },

  // ─── drop a song ───────────────────────────────────────────────────────────
  "PUT /current/submission": async (req, route) => {
    const ctx = await requireDefaultMembership(await requireProfile(await requireUser(req, route)));
    return submitTrack(req, ctx);
  },
  "PUT /:group_id/current/submission": async (req, route, params) => {
    const ctx = await requireMembership(
      await requireProfile(await requireUser(req, route)),
      params.group_id,
    );
    return submitTrack(req, ctx);
  },

  // ─── the guess sheet ───────────────────────────────────────────────────────
  // A whole-sheet upsert: the client sends the sheet as it currently stands and the server
  // diffs. docs/04 §4 lists seven validations and they are implemented in that order, so the
  // error a client gets for a request that breaks two rules is predictable.
  //
  // Everything is addressed by `card_no`. The client has never seen a submission id (ADR-003)
  // and the server resolves numbers against the round's own `card_order`, which means an
  // out-of-range number is caught by arithmetic rather than by a lookup that might succeed
  // against some other round's row.
  "PUT /current/guesses": async (req, route) => {
    const ctx = await requireDefaultMembership(await requireProfile(await requireUser(req, route)));
    return saveGuesses(req, ctx);
  },
  "PUT /:group_id/current/guesses": async (req, route, params) => {
    const ctx = await requireMembership(
      await requireProfile(await requireUser(req, route)),
      params.group_id,
    );
    return saveGuesses(req, ctx);
  },
});
