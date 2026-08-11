// rounds/index.ts — the blind window. docs/04 §4, docs/02 §2–3, docs/14 §3.
// tasks/E04-01, E04-02.
//
//   GET /current             today's round, shaped by phase
//   PUT /current/submission  drop or replace a song
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
  requireMembership,
  requirePhase,
  requireProfile,
  requireUser,
} from "../_shared/auth.ts";
import { dbFailure } from "../_shared/db.ts";
import {
  type CannotGuessReason,
  type CardDTO,
  cardDTO,
  type GuessDTO,
  guessSheetDTO,
  type MemberDTO,
  memberDTO,
  revealedRoundDTO,
  roundDTO,
  submissionDTO,
  type SubmissionDTO,
} from "../_shared/dto.ts";
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
}
const ROUND_COLUMNS = "id, local_date, state, opens_at, reveals_at, scores_at, card_order";

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
 * `ensure_rounds()` is called on a miss rather than 404ing, because the one moment a round can
 * legitimately be absent is the first minute of a brand-new group — the scheduler runs each
 * minute (docs/03 §4) and the API is not going to make the founding member wait for it.
 */
async function currentRound(ctx: MemberCtx): Promise<RoundRow> {
  const { data: group, error: groupError } = await ctx.db
    .from("groups")
    .select("timezone")
    .eq("id", ctx.groupId)
    .maybeSingle();
  if (groupError) throw dbFailure("rounds.group", groupError);
  if (!group) throw new ApiError("NOT_FOUND");

  const today = localDate(group.timezone, serverNow());

  const load = async (): Promise<RoundRow | null> => {
    const { data, error } = await ctx.db
      .from("rounds")
      .select(ROUND_COLUMNS)
      .eq("group_id", ctx.groupId)
      .eq("local_date", today)
      .maybeSingle();
    if (error) throw dbFailure("rounds.current", error);
    return data;
  };

  const existing = await load();
  if (existing) return existing;

  const { error: ensureError } = await ctx.db.rpc("ensure_rounds");
  if (ensureError) throw dbFailure("rounds.ensure_rounds", ensureError);

  const created = await load();
  if (!created) throw new ApiError("NOT_FOUND");
  return created;
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
async function cardsInOrder(ctx: MemberCtx, round: RoundRow): Promise<{ cards: CardDTO[]; rows: Map<string, CardRow>; order: string[] }> {
  const order = round.card_order ?? [];
  const { data, error } = await ctx.db
    .from("submissions")
    .select("id, user_id, track_meta")
    .eq("round_id", round.id);
  if (error) throw dbFailure("rounds.cards", error);

  const rows = new Map<string, CardRow>((data as CardRow[]).map((row) => [row.id, row]));
  const cards = order
    .map((submissionId, index) => {
      const row = rows.get(submissionId);
      return row ? cardDTO(index + 1, row.track_meta) : null;
    })
    .filter((card): card is CardDTO => card !== null);

  return { cards, rows, order };
}

/**
 * The name pool: exactly this round's submitters, the caller included (docs/02 §3).
 *
 * Display names come from `profiles` rather than from the roster, so someone who has since
 * left the group still appears under the name they had — the round happened, and a hole in the
 * pool would make it unsolvable for everyone else (docs/02 §3, "historical rounds keep their
 * attribution").
 */
async function namePool(ctx: MemberCtx, submitterIds: string[]): Promise<MemberDTO[]> {
  if (submitterIds.length === 0) return [];
  const { data, error } = await ctx.db
    .from("profiles")
    .select("id, display_name")
    .in("id", submitterIds)
    .order("display_name", { ascending: true })
    .order("id", { ascending: true });
  if (error) throw dbFailure("rounds.namePool", error);
  return data.map((p) => memberDTO({ user_id: p.id, display_name: p.display_name }));
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
    .map((g) => ({ card_no: order.indexOf(g.submission_id) + 1, guessed_user_id: g.guessed_user_id }))
    .filter((g) => g.card_no > 0)
    .sort((a, b) => a.card_no - b.card_no);
}

/**
 * Why the caller may not guess, or `null` if they may. docs/02 §3, docs/04 §4.
 *
 * **`joined_late` is checked first, which is the opposite of the order docs/04 §4 numbers.**
 * See the open question in `tasks/E05`. The short version: joining after `reveals_at` implies
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
  if (new Date(ctx.joinedAt).getTime() >= new Date(round.reveals_at).getTime()) return "joined_late";
  if (!mySubmissionId) return "not_a_submitter";
  return null;
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
    const ctx = await requireMembership(await requireProfile(await requireUser(req, route)));
    const round = await currentRound(ctx);
    const mine = await mySubmission(ctx, round.id);
    const base = roundDTO(round, mine);
    if (round.state !== "revealed") return ok(base);

    const { cards, rows, order } = await cardsInOrder(ctx, round);
    const mySubmissionId = order.find((id) => rows.get(id)?.user_id === ctx.userId) ?? null;

    return ok(
      revealedRoundDTO(base, {
        myCardNo: mySubmissionId === null ? null : order.indexOf(mySubmissionId) + 1,
        cannotGuessReason: cannotGuessReason(ctx, round, mySubmissionId),
        cards,
        namePool: await namePool(ctx, order.map((id) => rows.get(id)?.user_id).filter((id): id is string => !!id)),
        myGuesses: await myGuesses(ctx, round, order),
      }),
    );
  },

  // ─── drop a song ───────────────────────────────────────────────────────────
  "PUT /current/submission": async (req, route) => {
    const ctx = await requireMembership(await requireProfile(await requireUser(req, route)));
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

    const round = await currentRound(ctx);
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
    // **A duplicate track is never rejected.** If somebody else already dropped this song the
    // write succeeds exactly as if nobody had: the rejection itself would be the leak (docs/02
    // §3), and the response is byte-identical either way because nothing in it is derived from
    // another row.
    const { data, error } = await ctx.db
      .rpc("upsert_submission", {
        p_round_id: round.id,
        p_user_id: ctx.userId,
        p_track_key: track.track_key,
        p_track_meta: track,
      })
      .single();
    if (error) throw dbFailure("rounds.submit", error);

    return ok(submissionDTO(data as { track_meta: unknown; updated_at: string }));
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
    const ctx = await requireMembership(await requireProfile(await requireUser(req, route)));
    await enforceRateLimit(
      ctx.db,
      `guess:u:${ctx.userId}`,
      GUESS_LIMIT_PER_MINUTE,
      ONE_MINUTE_IN_SECONDS,
    );

    const body = await parseBody(req, { assignments: assignmentList() });
    const round = await currentRound(ctx);

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
    //    and the open question in tasks/E05.
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
    return ok(guessSheetDTO(saved, Math.max(order.length - 1, 0)));
  },
});
