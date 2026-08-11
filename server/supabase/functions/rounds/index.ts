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

import { ApiError, ok, optional, parseBody, serveFunction, str } from "../_shared/http.ts";
import {
  enforceRateLimit,
  type MemberCtx,
  requireMembership,
  requirePhase,
  requireProfile,
  requireUser,
} from "../_shared/auth.ts";
import { dbFailure } from "../_shared/db.ts";
import { roundDTO, submissionDTO, type SubmissionDTO } from "../_shared/dto.ts";
import { localDate, type RoundState, serverNow } from "../_shared/time.ts";
import { storefrontFor } from "../_shared/music/appleMusic.ts";
import { resolveTrack } from "../_shared/music/resolve.ts";
import { linkTrack } from "../_shared/music/trackLinks.ts";

// docs/04 §8. Twenty a minute is far above anyone changing their mind and far below anything
// that costs us an Apple lookup per second.
const SUBMIT_LIMIT_PER_MINUTE = 20;
const ONE_MINUTE_IN_SECONDS = 60;

interface RoundRow {
  id: string;
  local_date: string;
  state: RoundState;
  opens_at: string;
  reveals_at: string;
  scores_at: string;
}
const ROUND_COLUMNS = "id, local_date, state, opens_at, reveals_at, scores_at";

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
  // `revealed` and `scored` land in E05-01. Until then they return the same base shape, which
  // is a true subset of what they will return and leaks nothing.
  "GET /current": async (req, route) => {
    const ctx = await requireMembership(await requireProfile(await requireUser(req, route)));
    const round = await currentRound(ctx);
    return ok(roundDTO(round, await mySubmission(ctx, round.id)));
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
});
