# E05 — Reveal, guesses, and scoring

---

### E05-01 — `GET /rounds/current`: revealed

**Status:** todo · **Deps:** E03-04, E04-02 · **Reads:** `docs/04` §4, `docs/02` §3, `docs/01` ADR-003
**Touches:** `functions/rounds/index.ts`, `functions/_shared/dto.ts`
**Verify:** `npm run test:functions -- reveal`

Cards addressed by `card_no` only. `submission_id` never crosses the wire before `scored`.

- [ ] `cards` includes **every** card, the caller's own included — the numbering must not
      have a hole (`docs/08` §6)
- [ ] `my_card_no` tells the client which one to exclude from the sheet
- [ ] `name_pool` is exactly this round's submitters, caller included; the client removes
      itself
- [ ] `can_guess` + `cannot_guess_reason` (`not_a_submitter` | `joined_late` | null)
- [ ] `my_guesses` is the caller's own sheet only
- [ ] **No endpoint returns another user's guesses in this phase.** Assert this by enumerating
      routes, not by inspection
- [ ] Test: all 8 members receive an identical `[card_no → track_key]` sequence (AC-5)
- [ ] Test: no `submission_id` appears anywhere in the `revealed` payload

---

### E05-02 — `PUT /rounds/current/guesses`

**Status:** todo · **Deps:** E05-01 · **Reads:** `docs/04` §4, `docs/02` §3
**Touches:** `functions/rounds/index.ts`
**Verify:** `npm run test:functions -- guess`

Whole-sheet upsert with a server-side diff. The seven validations in `docs/04` §4 are the
spec; implement them in that order so the error codes are predictable.

- [ ] `WRONG_PHASE` outside `revealed`
- [ ] `NOT_A_SUBMITTER` (403) when the caller has no submission
- [ ] `JOINED_LATE` (403) when `joined_at >= reveals_at`
- [ ] `card_no` validated in `1..N` and not the caller's own
- [ ] `guessed_user_id` validated against the name pool and not the caller
- [ ] Duplicate `guessed_user_id` across two cards is **allowed** — players double-assign
      while thinking
- [ ] Omitted `card_no` entries are untouched; explicit `null` clears
- [ ] Editable until `scores_at`
- [ ] Response returns `assigned_count` / `assignable_count`
- [ ] Rate limit 60/min

---

### E05-03 — Scoring views

**Status:** todo · **Deps:** E01-04 · **Reads:** `docs/02` §4, `docs/03` §5
**Touches:** `migrations/0005_scoring.sql`
**Verify:** `npm run test:db -- scoring`

Four views: `round_submitter_counts`, `guess_results`, `round_scores`, `standings`. Derived,
never stored (ADR-004).

- [ ] `guess_results.is_correct` implements the duplicate rule in `docs/02` §4.3 — correct iff
      the guessed person submitted **that `track_key`** this round
- [ ] `readability` denominator is `S − 1` regardless of who guessed
- [ ] `ear` is `null` when the user made zero guesses, **not zero**
- [ ] `standings.ear_all_time` pools correct/possible, excluding zero-guess rounds from both
      sums
- [ ] `standings.readability_all_time` is a **mean of per-round rates**, not a pooled ratio —
      the asymmetry is deliberate (`docs/02` §4.2)
- [ ] Voided rounds contribute to nothing
- [ ] Test: `explain` shows the duplicate join uses `submissions_round_trackkey`

---

### E05-04 — `GET /rounds/{id}/results`

**Status:** todo · **Deps:** E05-03 · **Reads:** `docs/04` §4
**Touches:** `functions/rounds/index.ts`
**Verify:** `npm run test:functions -- results`

- [ ] Requires `scored`, requires membership, `round_id` validated against the caller's group
- [ ] Works for any past round (The Record links into it)
- [ ] Rates are decimals `0..1`; the client formats
- [ ] `null` means *not applicable*, never *zero* — for `ear` (no guesses) and `readability`
      (no submission)
- [ ] `people` includes every submitter
- [ ] Test: a `revealed` round returns `WRONG_PHASE`, and the error body carries no card data

---

### E05-05 — `GET /groups/current/standings`

**Status:** todo · **Deps:** E05-03 · **Reads:** `docs/04` §4, `docs/02` §4.5
**Touches:** `functions/groups/index.ts`
**Verify:** `npm run test:functions -- standings`

- [ ] `best_ear` **is** ranked; ties share a rank and the next rank skips
- [ ] `readability` has **no `rank` field**, sorted descending only for stability
- [ ] `band` computed from the `docs/02` §4.5 table
- [ ] Test: the `readability` array contains no key named `rank` — a client that receives one
      will render it
- [ ] Perf: under 150ms with 12 members × 200 rounds of seeded data. Above that, follow the
      ADR-004 escape hatch (a materialised view refreshed at score time) — **do not**
      denormalise into `submissions`

---

### E05-06 — Hand-checked scoring test

**Status:** todo · **Deps:** E05-03 · **Reads:** `docs/02` §4.4, `docs/15` AC-8
**Touches:** `tests/db/scoring.sql`, `tests/db/standings.sql`
**Verify:** `npm run test:db -- scoring standings`

The §4.4 table, asserted row by row. **Do not change the numbers without changing the doc.**

- [ ] Every per-user readability and ear matches §4.4
- [ ] Eli: `ear is null`, and Eli still has a readability of 1/7
- [ ] Ivy: absent from both
- [ ] Ben: 3 blanks count as wrong, denominator still 7
- [ ] Ana and Ben's duplicate: a guess of "Ana" on Ben's card is correct, and it counts toward
      both the guesser's ear and Ben's readability
- [ ] All-time over three rounds of sizes 8, 5, 3 — verifies pooled ear vs mean readability
      produce different numbers, so a regression that conflates them fails
