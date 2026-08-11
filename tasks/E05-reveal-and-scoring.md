# E05 — Reveal, guesses, and scoring

---

### E05-01 — `GET /rounds/current`: revealed

**Status:** done · **Deps:** E03-04, E04-02 · **Reads:** `docs/04` §4, `docs/02` §3, `docs/01` ADR-003
**Touches:** `functions/rounds/index.ts`, `functions/_shared/dto.ts`
**Verify:** `npm run test:functions -- reveal`

Cards addressed by `card_no` only. `submission_id` never crosses the wire before `scored`.

- [x] `cards` includes **every** card, the caller's own included — the numbering must not
      have a hole (`docs/08` §6)
- [x] `my_card_no` tells the client which one to exclude from the sheet
- [x] `name_pool` is exactly this round's submitters, caller included; the client removes
      itself
- [x] `can_guess` + `cannot_guess_reason` (`not_a_submitter` | `joined_late` | null)
- [x] `my_guesses` is the caller's own sheet only
- [x] **No endpoint returns another user's guesses in this phase.** Assert this by enumerating
      routes, not by inspection
- [x] Test: all 8 members receive an identical `[card_no → track_key]` sequence (AC-5)
- [x] Test: no `submission_id` appears anywhere in the `revealed` payload

> **Open question:** `docs/04` §4 numbers the guess validations so that `NOT_A_SUBMITTER`
> (rule 2) is checked before `JOINED_LATE` (rule 3). Implemented in that order, `JOINED_LATE`
> is unreachable: joining after `reveals_at` implies having no submission, because a round
> stops accepting submissions the moment it leaves `open`. The only caller who could ever see
> it is someone who submitted, left the group, and rejoined the same evening.
>
> A reason code that cannot be returned is a reason code that does not exist, and it has copy
> in `docs/11` — *"You joined after the reveal. You're in from tomorrow."* — that is both true
> and considerably kinder than telling a member who arrived at 20:30 that they "didn't drop a
> song tonight".
>
> **Interpretation taken:** `joined_late` is checked first, in both the read path
> (`cannot_guess_reason`) and the write path (the error code), from one shared helper so the
> two can never disagree. Neither ordering discloses anything — both facts are the caller's
> own — so the blind window does not decide this one; reachability and copy do. Owner's call
> to confirm, and to renumber `docs/04` §4 if they agree.

---

### E05-02 — `PUT /rounds/current/guesses`

**Status:** done · **Deps:** E05-01 · **Reads:** `docs/04` §4, `docs/02` §3
**Touches:** `functions/rounds/index.ts`
**Verify:** `npm run test:functions -- guess`

Whole-sheet upsert with a server-side diff. The seven validations in `docs/04` §4 are the
spec; implement them in that order so the error codes are predictable.

- [x] `WRONG_PHASE` outside `revealed`
- [x] `NOT_A_SUBMITTER` (403) when the caller has no submission
- [x] `JOINED_LATE` (403) when `joined_at >= reveals_at`
- [x] `card_no` validated in `1..N` and not the caller's own
- [x] `guessed_user_id` validated against the name pool and not the caller
- [x] Duplicate `guessed_user_id` across two cards is **allowed** — players double-assign
      while thinking
- [x] Omitted `card_no` entries are untouched; explicit `null` clears
- [x] Editable until `scores_at`
- [x] Response returns `assigned_count` / `assignable_count`
- [x] Rate limit 60/min

---

### E05-03 — Scoring views

**Status:** done · **Deps:** E01-04 · **Reads:** `docs/02` §4, `docs/03` §5
**Touches:** `migrations/0005_scoring.sql`
**Verify:** `npm run test:db -- scoring`

Four views: `round_submitter_counts`, `guess_results`, `round_scores`, `standings`. Derived,
never stored (ADR-004).

- [x] `guess_results.is_correct` implements the duplicate rule in `docs/02` §4.3 — correct iff
      the guessed person submitted **that `track_key`** this round
- [x] `readability` denominator is `S − 1` regardless of who guessed
- [x] `ear` is `null` when the user made zero guesses, **not zero**
- [x] `standings.ear_all_time` pools correct/possible, excluding zero-guess rounds from both
      sums
- [x] `standings.readability_all_time` is a **mean of per-round rates**, not a pooled ratio —
      the asymmetry is deliberate (`docs/02` §4.2)
- [x] Voided rounds contribute to nothing
- [x] Test: `explain` shows the duplicate join uses `submissions_round_trackkey`
      — **discharged in `E05-05`, and in an amended form. Read the open question there.**

> **Deferred, as written, and then found to be wrong.** `tests/db/scoring.sql` asserts that
> `submissions_round_trackkey` exists and is on `(round_id, track_key)` — the join predicate —
> but not that a plan uses it. On the nine-row §4.4 fixture the planner will correctly choose a
> sequential scan, so an `explain` assertion there would be asserting the fixture's size and
> would have to be defeated with `enable_seqscan = off`, at which point it proves only that the
> index *can* be used, which `has_index` already told us.
>
> The assertion is worth making against data that can justify a plan, so it moved to `E05-05`'s
> performance fixture. What it found there is that the premise of this checklist item does not
> hold: at a realistic table size the planner prefers `submissions_one_per_user_per_round`, and
> it is right to. `tests/db/standings_perf.sql` asserts the property that is actually true and
> actually stable instead.

---

### E05-04 — `GET /rounds/{id}/results`

**Status:** done · **Deps:** E05-03 · **Reads:** `docs/04` §4
**Touches:** `functions/rounds/index.ts`, `functions/_shared/dto.ts`, `functions/_shared/http.ts`
**Verify:** `npm run test:functions -- results`

- [x] Requires `scored`, requires membership, `round_id` validated against the caller's group
- [x] Works for any past round (The Record links into it)
- [x] Rates are decimals `0..1`; the client formats
- [x] `null` means *not applicable*, never *zero* — for `ear` (no guesses) and `readability`
      (no submission)
- [x] `people` includes every submitter
- [x] Test: a `revealed` round returns `WRONG_PHASE`, and the error body carries no card data

The route is asserted against the `docs/02` §4.4 matrix in `seed.sql` rather than against a
round the test built for itself — the numbers a human checked by hand are the ones worth
putting on the wire, and a test that recomputed the arithmetic would agree with a handler that
had the same bug. That round is dated three days before the fixture's "today", so
*works for any past round* comes for free rather than needing a contrived second round.

> **Note, on the first path parameter in the API.** `serveFunction` grew `:param` segments for
> this route. Two decisions inside it are load-bearing. Literal routes are matched first and by
> object lookup, so declaration order cannot change which handler answers `GET /current`. And
> the rate-limit bucket is keyed on the *pattern*, not the concrete path — a bucket keyed on the
> latter would hand every round id its own 120/min allowance, which is to say no limit at all
> (`docs/04` §8).
>
> A malformed uuid answers `NOT_FOUND` rather than `INVALID_INPUT`. An unparseable uuid reaching
> Postgres is a `22P02` and therefore a 500, and a route that answers 500 for garbage and 404
> for a real id belonging to another group has just told the caller which is which.

---

### E05-05 — `GET /groups/current/standings`

**Status:** done · **Deps:** E05-03 · **Reads:** `docs/04` §4, `docs/02` §4.5
**Touches:** `functions/groups/index.ts`, `functions/_shared/dto.ts`, `tests/db/standings_perf.sql`
**Verify:** `npm run test:functions -- standings` · `npm run test:db -- standings_perf`

- [x] `best_ear` **is** ranked; ties share a rank and the next rank skips
- [x] `readability` has **no `rank` field**, sorted descending only for stability
- [x] `band` computed from the `docs/02` §4.5 table
- [x] Test: the `readability` array contains no key named `rank` — a client that receives one
      will render it
- [x] Perf: under 150ms with 12 members × 200 rounds of seeded data. Above that, follow the
      ADR-004 escape hatch (a materialised view refreshed at score time) — **do not**
      denormalise into `submissions`

Measured at **35–41ms**, best of three, against a `submissions` table carrying fifteen other
groups' history as well. Comfortably inside the budget, so ADR-004 stands as written and no
materialised view is needed.

The handler sorts and ranks and does no arithmetic: the pooled-ear / mean-readability asymmetry
stays in SQL, because a second implementation of it in TypeScript is the kind of thing that goes
subtly wrong and produces a number that is plausible, stable, and not the one the game is
scored on.

> **Open question:** `docs/04` §4 does not say whether standings cover the *active roster* or
> everyone who ever played in the group. Both readings are defensible and neither touches the
> blind window — a departed member's name is already in The Record and in every past round's
> results, so nothing is disclosed either way.
>
> **Interpretation taken:** the active roster. A leaderboard is about the room as it is, and
> someone who left sitting at rank 2 in perpetuity is a scoreline nobody can respond to. Their
> rounds still happened and still count toward everyone else's readability — only their own row
> goes. Owner's call to confirm.
>
> A member with no all-time ear at all — every round they played, they assigned nothing — is
> absent from `best_ear` rather than ranked last. `docs/02` §4.1 draws that line for a single
> round and it seems to hold all the way up: never guessing is not guessing badly, and the
> leaderboard is the one surface where a dash in last place reads as a score. They still appear
> in `readability`, which does not depend on whether they looked.

> **Open question, and this one contradicts a comment in `0005`.** The `explain` assertion
> `E05-03` deferred to here does not hold as it was written. `0005`'s comment and `E05-03`'s
> checklist both name `submissions_round_trackkey` as "exactly this join" for the duplicate-track
> existence test in `guess_results`. Against the 12 × 200 fixture plus fifteen neighbouring
> groups, the planner prefers `submissions_one_per_user_per_round` — and that is the better plan.
> The predicate is three equalities (`round_id`, `user_id`, `track_key`); the *unique* index on
> `(round_id, user_id)` finds at most one row and then checks the track, where `(round_id,
> track_key)` may match several and then filters by user. Which one wins moves with the
> statistics, and both are correct.
>
> **Interpretation taken:** `tests/db/standings_perf.sql` asserts the invariant that is stable
> and that a regression would actually break — the check is a keyed lookup inside one round
> through a `round_id`-leading index, never a scan — rather than naming a plan the planner is
> entitled to improve on. `submissions_round_trackkey` is not redundant: it is the right index
> for asking "who else dropped this track", which is the direction the duplicate rule reads in.
> `0005` is a merged migration and its comment was left alone; it is the comment that is
> imprecise, not the index. Owner's call whether to correct it in a later migration's note.

---

### E05-06 — Hand-checked scoring test

**Status:** done · **Deps:** E05-03 · **Reads:** `docs/02` §4.4, `docs/15` AC-8
**Touches:** `tests/db/scoring.sql`, `tests/db/standings.sql`
**Verify:** `npm run test:db -- scoring standings`

The §4.4 table, asserted row by row. **Do not change the numbers without changing the doc.**

- [x] Every per-user readability and ear matches §4.4
- [x] Eli: `ear is null`, and Eli still has a readability of 1/7
- [x] Ivy: absent from both
- [x] Ben: 3 blanks count as wrong, denominator still 7
- [x] Ana and Ben's duplicate: a guess of "Ana" on Ben's card is correct, and it counts toward
      both the guesser's ear and Ben's readability
- [x] All-time over three rounds of sizes 8, 5, 3 — verifies pooled ear vs mean readability
      produce different numbers, so a regression that conflates them fails
