# E39 — An unfilled guess sheet is filled, not excused

Four slices. Closes the abstention loophole in `docs/02-DOMAIN-RULES.md` §4.1.

**The hole.** §4.1's exception — "if `u` made **zero** guesses, `ear` for that round is undefined
(`0/0`) and the round is dropped from `u`'s ear average" — is unbounded, so a member protects a
high all-time Ear by only guessing on nights they feel sure. It costs them nothing and it costs
everyone else something: §4.1's readability denominator is `S − 1` regardless of who looked, so the
abstainer's silence still counts as a miss against every other submitter's readability. They keep
their number and spend the room's.

**The fix.** At `revealed → scored`, the server fills every unguessed card with a randomly chosen
name. There is no longer such a thing as an unfilled sheet, so there is nothing to excuse. A member
who genuinely could not make it is not punished — they are scored at chance, which is the honest
reading of a sheet nobody filled in. A member who is dodging finds that dodging now regresses their
Ear toward chance instead of preserving its peak. Same mechanism, two fair outcomes, no penalty
anywhere.

> **Owner amendment — rewrites `docs/02-DOMAIN-RULES.md` §4.1 and §4.2.** §4.1's zero-guess
> exception and its "Unassigned cards score as wrong" line both go; §4.2's "rounds where the user
> made zero guesses are excluded from both sums" goes with them. `server/supabase/migrations/0005_scoring.sql`
> opens with a header comment arguing at length that `ear` **must** be NULL and never 0 for a
> non-guesser — that argument is now half-obsolete and the replacement migration must say why,
> rather than leaving two files disagreeing about the same rule. This is not a silent rewrite: the
> epic is not done while any of those still assert the old rule.

> **Open question — does an auto-assigned guess count toward the card owner's readability?**
> Interpretation taken, pending the owner: **no.** Ear counts auto rows in full; readability's
> numerator counts human rows only, denominator unchanged at `S − 1`. Reasons: §4.1 defines
> readability as "how much of the room read you", and a coin flip did not read you; without the
> exclusion a dodger's random hits would *inflate* a real person's character stat, and §4.1's own
> "a room that didn't look is a room that didn't read you" would quietly become false. The cost is
> that `guesses` rows are no longer uniform — every readability surface needs a `not is_auto`
> filter, and forgetting one is a silent scoring bug. E39-01 puts the filter in the view, once, so
> no consumer can forget. Flip this and E39-01/02 both change.

---

### E39-01 — Fill the sheet at scoring time, and stop excusing it

**Status:** todo
**Deps:** —
**Parallel:** no
**Reads:** `docs/02-DOMAIN-RULES.md` §4, `docs/03-DATA-MODEL.md` §5,
`server/supabase/migrations/0002_core_tables.sql` (`guesses`),
`server/supabase/migrations/0005_scoring.sql`,
`server/supabase/migrations/20260826120100_conditional_reminders.sql` (`tick_rounds`, score loop),
`server/supabase/migrations/20260815090500_demo_lifecycle.sql` (`tick_demo_group`, score branch)
**Touches:** `docs/02-DOMAIN-RULES.md`, `CLAUDE.md` §2.8 note if needed, a new
`server/supabase/migrations/NNNN_auto_assigned_guesses.sql`,
`server/supabase/tests/db/scoring.sql`, `server/supabase/tests/db/standings.sql`,
`server/supabase/tests/db/lifecycle.sql`, `server/supabase/tests/db/demo_mode.sql`
**Verify:** `cd server && npm run test:db && npm run audit:leak`
**Proves:** AC-4 (scoring), AC-1 (no new open-phase surface)

- [ ] `guesses` gains `is_auto boolean not null default false`. Real guess writes never set it;
      the fill is the only producer. A partial index or plain column is fine — the column is read
      in exactly one view.
- [ ] New `public.fill_unguessed_cards(p_round_id uuid) returns int`, `security definer`,
      `search_path = ''`. For each submitter, for each card they did not guess and do not own,
      insert a row naming a uniformly random member of the eligible pool.
      - Pool = this round's submitters minus the guesser. Size `S − 1`, which is also the number of
        cards to fill, so the pool is never empty for a valid round (`S ≥ 3`).
      - **Independent draws, repeats allowed** — not a permutation. The sheet already permits
        naming one person twice (there is no unique index on `(round_id, guesser_id, guessed_user_id)`,
        and `RevealStore`'s consumed chips stay tappable), so the fill should not be stricter than a
        human. Expected correct is `1` card either way.
      - `guesses_not_self` (0002) and `guesses_validate()` must both still pass — the fill inserts
        through the same triggers as a real write, deliberately.
      - **Deterministic**, seeded `hashtext(round_id::text || guesser_id::text)`, same house style
        as the Fisher-Yates in `tick_rounds`. A retried subtransaction must produce the same sheet,
        and pgTAP must be able to assert exact output rather than a distribution.
      - `on conflict (round_id, guesser_id, submission_id) do nothing` — idempotent against
        `guesses_one_per_card`, so a second call is a no-op.
- [ ] **Every unassigned card, not only fully-blank sheets.** Filling only zero-guess sheets leaves
      the loophole open one notch down: a blank card scores 0 while a random card scores `1/(S−1)`
      in expectation, so "guess the one card I'm sure of and leave the rest" would score about the
      same as abstaining does today. Filling all unassigned cards removes the edge case and deletes
      §4.1's "Unassigned cards score as wrong" line at the same time.
- [ ] Called from **both** score paths, inside the existing per-round subtransaction and **before**
      the `state = 'scored'` update: `tick_rounds()`'s score loop
      (`20260826120100_conditional_reminders.sql`) and `tick_demo_group()`'s score branch
      (`20260815090500_demo_lifecycle.sql`). Ordering matters — `PUT /rounds/{id}/guesses` refuses
      writes once the round is `scored` (`requirePhase(round, ["revealed"])`), so filling first and
      flipping second means no window where a member's real guess races the fill.
- [ ] `round_scores` rewritten: `ear` counts all rows and is **non-NULL for every submitter**;
      `read_by` filters `where not gr.is_auto` (see the open question). `standings`' two
      `filter (where rs.ear is not null)` clauses stay — they are now load-bearing only for
      historical rounds (below), not for new ones.
- [ ] **Forward-only. No backfill.** Rounds already `scored` keep their NULL ears. Inventing guesses
      in past rounds would rewrite everyone's history from rows nobody can check. This is why `ear`
      stays nullable in the view and the DTO: after this ships, a NULL ear means either a
      pre-E39 round or a non-submitter, and never "sat tonight out".
- [ ] pgTAP: a three-submitter round where one member guesses nothing scores a real Ear, not NULL;
      the same round twice produces byte-identical fills; a partial sheet keeps its human guesses and
      gains the rest; an auto row that happens to be correct moves the guesser's Ear and **not** the
      card owner's readability; `fill_unguessed_cards` on an already-filled round inserts zero rows;
      a voided round is never filled.

---

### E39-02 — Shape it honestly through the API

**Status:** todo
**Deps:** E39-01
**Parallel:** no
**Reads:** `docs/04-API-CONTRACT.md` §4, `server/supabase/functions/rounds/index.ts` (`results`),
this epic's open question
**Touches:** `docs/04-API-CONTRACT.md`, `server/supabase/functions/rounds/index.ts`,
`server/supabase/tests/functions/rounds.test.ts`, `server/scripts/audit-leak.mjs`
**Verify:** `cd server && npm run test:functions && npm run audit:leak`
**Proves:** AC-1, AC-4

Three surfaces read `guesses` and each wants a different answer. Getting this wrong makes the app
tell a lie about a named person, which is worse than the loophole.

- [ ] `MyGuessDTO` gains `is_auto`. The caller's own auto rows **are** returned — a results screen
      showing blank cards next to a non-zero Ear is incoherent, and the member is entitled to see
      what was filled in on their behalf.
- [ ] `CardGuessDTO` (the "who guessed you" list on the caller's own card) **excludes** auto rows.
      That list is the readability surface, and it is the one place the app would otherwise print
      "Ana guessed Ben" about a guess Ana never made.
- [ ] `correctGuessCount` ("%lld of %lld got it") **excludes** auto rows, for the same reason —
      it is readability's numerator. `eligibleGuesserCount` is unchanged at `S − 1`.
- [ ] `people[].ear` and `me.ear` are now non-null for every submitter in a post-E39 round. Nothing
      to change in the shaping; note it in `docs/04` §4 so the nullability is not read as dead code.
- [ ] `tonight_top_ear`'s `.filter(ear !== null)` becomes a no-op for new rounds. Leave it — it is
      still correct for historical rounds. A member who guessed nothing can now place in tonight's
      top 3 on luck; that is acceptable and honest, and it is rare enough not to warrant a rule.
- [ ] `audit:leak` gains a check that no `is_auto` row can exist for a round not in `scored` — the
      fill is a post-reveal write and must never become a source of open-phase signal.

---

### E39-03 — Say so on the results screen

**Status:** todo
**Deps:** E39-02
**Parallel:** no
**Reads:** `docs/08-SCREEN-SPECS.md` (results), `docs/11-COPY-DECK.md` (results block),
`ios/BlindDrop/Features/Results/`, `ios/BlindDrop/Core/Networking/DTO/ResultsDTO.swift`
**Touches:** `ResultsDTO.swift`, `ios/BlindDrop/Features/Results/*`,
`ios/BlindDrop/Resources/Localizable.strings`, `docs/11-COPY-DECK.md`, snapshot goldens
**Verify:** `./ios/scripts/lint.sh`, then unit + snapshot per `CLAUDE.md` §5. Simulator pass on
iPhone 17: a scored round where you guessed nothing, and one where you guessed two of five.
**Proves:** AC-4

- [ ] An auto-filled card in the caller's own results is labelled where `results.card.yousaid`
      currently sits. New copy key, added to `docs/11-COPY-DECK.md` in the same commit
      (`CLAUDE.md` §6). Tone per §6 — states what happened, does not scold. Something in the register
      of "Filled in for you" / "You didn't say"; the deck owns the final wording.
- [ ] `results.ear.none` ("You sat this one out.") is retired for submitters — it can no longer be
      true of one. Keep the key for pre-E39 rounds in The Record, or retire it and render those as
      "—"; pick one and write the reason into the deck entry rather than leaving it dangling.
- [ ] Auto rows are amber-adjacent at most and carry no accent of their own — `CLAUDE.md` §2.5 is
      not relaxed for this. A neutral label, not a badge.
- [ ] VoiceOver: the auto label is part of the card's second sentence, same shape as
      `Copy.A11y.result(...)` already uses.
- [ ] Snapshot goldens re-recorded **only after looking at the failures** (`CLAUDE.md` §5).

---

### E39-04 — Tell people before it happens, not after

**Status:** todo
**Deps:** E39-01
**Parallel:** no
**Reads:** `docs/11-COPY-DECK.md` (How to play, push copy), `ios/BlindDrop/Features/HowTo/HowToSheet.swift`,
`ios/BlindDrop/Features/Reveal/RevealScreen.swift`, `docs/05-JOBS-AND-NOTIFICATIONS.md`
**Touches:** `docs/11-COPY-DECK.md`, `HowToSheet.swift`, `RevealScreen.swift`,
`ios/BlindDrop/Resources/Localizable.strings`, `server/supabase/functions/push-worker/worker.ts`
if the `guess_reminder` body changes, snapshot goldens
**Verify:** `./ios/scripts/lint.sh`, snapshot suite, simulator pass on the reveal screen with a
partly-filled sheet.
**Proves:** AC-4

A rule that silently fills your sheet after the fact is a trap; the same rule announced in advance
is a deadline. Three places, all copy-only:

- [ ] **How to play** — the guess step names the consequence in one clause. No new step, no colour
      change: `CLAUDE.md` §2.5's carve-out for this page covers the four phases and nothing more.
- [ ] **The guess sheet** — one line near the confirm control, visible while there is still time to
      act, saying unfilled cards get filled at `scores_at`. Not an error state, not red.
- [ ] **`guess_reminder`** (E31, `scores_at − 30m`) — the body may now name the consequence. It is
      still addressed to the recipient about their own status only, and still must never mention
      another member's status or a count (`CLAUDE.md` §2.6).
