# E46 — Reactions

Three slices, from an owner request: *"add some sort of reaction — a heart, a dislike — to songs
at either the reveal or the answers."*

The spec is **`docs/19-REACTIONS.md`**, which also carries the owner amendment that makes this
buildable at all: `docs/16-OUT-OF-SCOPE.md` §1 and `tasks/ICEBOX.md` both banned reactions
outright, and the ICEBOX's objection — *"high cost if reactions were ever visible before
10:00 PM"* — is answered rather than waived. Read `docs/19` before reading the slices; every
bound below comes from it.

**The whole design in one line.** A reaction behaves exactly like a guess: you place it blind at
the reveal, and the room resolves at 22:00. No count exists, at any URL, before `scored`.

**What this epic does not need.** No push-worker change and no new notification kind — a push
about a reaction is two `CLAUDE.md` §2.6 violations in one line. No scoring change: reactions
touch nothing in `guess_results`, standings, profiles, insights or the share card. No change to
the `open`-phase payload, which is the assertion AC-1's untouched goldens make for us.

> **Settled — the quick pass still skips your own card.** *(Owner, 2026-09-17.)* This was drafted
> the other way and the owner reversed it before any code was written. `E41-01`'s decision stands
> unamended: the run is the cards you have work on, and a stop whose only content is an optional
> mark is a tap charged to every member every night. Your own drop is markable at the answers
> instead (`docs/19` §4, §8.3), where the control already exists for every other card. So nothing
> in `QuickPassSequence` changes in this epic.

> **Open question — may a non-submitter react?**
> Interpretation taken: **yes**, for any member with `joined_at < reveals_at`. `docs/02` §3.3
> restricts *guessing* because guessing is scored; a reaction is scored by nothing. It leaks
> nothing either way — counts are sealed, and published counts carry no denominator.
>
> **Answered by `E46-02`, and not the way this was written.** The server permits it and the
> store has no submitter guard, but the reveal's only placement surface is the quick pass, and
> `QuickPassPresentation` refuses the cover outright when `can_guess` is false (`E41`). So the
> clause about *"a reason to open the app at 20:00"* does not ship: a non-submitter's reveal is
> unchanged, and their marks land at the answers instead, which they do reach.
>
> **This is left for the owner rather than patched.** A marking-only cover is a different screen
> from the one `E41` built — no name grid, different copy, a different reason to exist — and
> bolting a bar onto the blocked flight would make the one row `docs/19` §8.2 calls read-only into
> a control for one class of member. `docs/19` §4 carries the correction. If the owner wants the
> reveal-phase surface, it is its own slice.

---

### E46-01 — The reaction model and the route

**Status:** done · **Deps:** — · **Parallel:** no
**Reads:** `docs/19` §3, §4, §6, §7, §10, `docs/03` §2 (`guesses`), `docs/04` §4, §7, §8,
`server/supabase/migrations/0002_core_tables.sql:104`,
`server/supabase/functions/rounds/index.ts`, `server/supabase/functions/_shared/`
**Touches:** `server/supabase/migrations/`, `server/supabase/functions/rounds/`,
`server/supabase/tests/`, `docs/03`, `docs/04`, `docs/15` (AC-12)
**Verify:** `cd server && npm test`; `npm run audit:leak`; `node server/scripts/lint.mjs`
**Proves:** AC-12, and AC-1 by not moving

- [x] `reaction_kind` enum and `reactions` table per `docs/19` §6 — shaped like `guesses`,
      `profiles` reference without cascade, unique index on `(round_id, reactor_id, submission_id)`,
      **no** not-self constraint.
- [x] RLS enabled and deny-by-default; `revoke all` from `public`/`anon`/`authenticated`.
- [x] `PUT /rounds/{group_id}/current/reactions` and the oldest-circle alias, with all six guards
      from `docs/19` §7 and the 60/minute limit.
- [x] The route returns the caller's own marks **and nothing else**, in `revealed` and in
      `scored`. It performs no aggregate read and no scan of the round's reactions.
- [x] A past round refuses the write with `WRONG_PHASE` and still serves its counts.
- [x] `GET /rounds/{group_id}/current` carries `my_reactions` in `revealed` and the key is
      **absent** — not null — in every other phase.
- [x] `GET /rounds/{round_id}/results` carries `cards[].reactions` — all three keys, zeros
      included, never `null` — and `cards[].my_reaction`.
- [x] Counts are computed `group by kind` on read. No counter column anywhere.
- [x] New reviewed goldens for the route and for the `revealed` payload; the `open` and `voided`
      goldens are **unchanged** and that is asserted, not assumed.
- [x] `docs/03`, `docs/04` §4/§7/§8 and `docs/15` (AC-12) updated in the same commit.

> **Reviewer finding, fixed before closing.** The past-round guard was claimed by AC-12 and by
> the checklist above and was asserted nowhere: every scenario in `reactions.test.ts` used a
> round that was still the circle's current one. `tick_rounds_at` cannot produce a stale round
> — the handlers read the real clock, so a test cannot move a circle past local midnight — so
> the test that closes it uses `seed.sql`'s §4.4 night (2026-08-08, `scored`, nobody's current
> round) and asserts both halves of the property: the write resolves *tonight* and is refused
> against tonight's phase, and the past night still serves its counts. The route taking no round
> id at all is the structural half of the same guarantee, and the test says so.

---

### E46-02 — Placing a mark at the reveal

**Status:** done · **Deps:** E46-01 · **Parallel:** no
**Reads:** `docs/19` §5, §8.1, §8.2, `docs/07` §2/§4/§5, `docs/08` §6/§6.1, `docs/09` §1,
`docs/11` (reveal and quick pass blocks), `docs/12` §1/§2,
`ios/BlindDrop/Features/Reveal/QuickPass/`, `ios/BlindDrop/Features/Reveal/RevealStore.swift`,
`ios/BlindDrop/DesignSystem/Components/{PillButton,FlightCard}.swift`,
`ios/BlindDrop/Core/Networking/DTO/RoundDTO.swift`, `ios/fixtures/`
**Touches:** the above, plus `Localizable.strings` and `docs/11`
**Verify:** `./ios/scripts/lint.sh`; iOS unit + snapshot (`-only-testing:BlindDropUnitTests
-only-testing:BlindDropSnapshotTests`); `./ios/scripts/verify-fixture.sh
BlindDropUnitTests/FixtureRoundTests "Round"`; simulator pass per `CLAUDE.md` §8 F on iPhone 17
**Proves:** AC-12

- [x] `ReactionKind` and the `my_reactions` decode land here, once, for both client slices.
- [x] `ReactionBar` in `DesignSystem/Components/` — three marks with a per-symbol optical size
      table, outlined by default, the selected one filled with the screen's accent. No hardcoded
      colour, size or spacing; `PhaseAccent` is passed in, never read.
- [x] `interesting` draws `ellipsis.circle.fill` and is checked against the ⋯ overflow glyph the
      app already uses, on a screenshot. The custom ascending-dots fallback (`docs/19` §5) is
      taken if it reads as a menu.
- [x] The bar sits under the name grid in the quick pass. Tapping fires `.impact(.light)`,
      never advances the card, and tapping your own mark clears it.
- [x] `QuickPassSequence` is **unchanged** — your own card is still skipped, numeral and all.
      Asserted by the existing `E41` tests still passing untouched.
- [x] Each `FlightCard` row shows your own mark in `inkDim`, read-only, with no count. Your own
      row carries none, because nothing in this phase can place one there.
- [x] `RevealStore` writes optimistically and reconciles; a failed write reverts the mark rather
      than leaving a lie on screen.
- [x] No count is rendered, computed or decoded anywhere in this phase.
- [x] Copy added to `docs/11` and `Localizable.strings` in the same commit: the three words plus
      the VoiceOver labels.
- [x] Snapshots at SE and 15 Pro Max × `large`/`accessibility5`, marked and unmarked — plus
      `.xxxLarge`, which the standard matrix steps over and which is where the artwork's reserve
      for the bar goes wrong if anybody simplifies it. **No non-submitter golden**, because the
      screen carrying the bar is one a non-submitter cannot reach — see the open question above.
- [x] Simulator: place, change, clear, background and foreground, and your own card arriving
      unmarked and unstopped. Look
      at the screenshots — the three marks either read as a family or they get the custom
      `Shape` fallback `docs/19` §5 names.

---

### E46-03 — Counts at the answers

**Status:** wip · **Deps:** E46-02 · **Parallel:** no
**Reads:** `docs/19` §7, §8.3, §8.4, `docs/08` §7.1, `docs/11` (results block),
`ios/BlindDrop/Features/Results/{ResultsScreen,ResultsStore,PastResultsScreen}.swift`,
`ios/BlindDrop/Core/Networking/DTO/ResultsDTO.swift`, `ios/fixtures/`
**Touches:** the above, plus `Localizable.strings`, `docs/08` §7.1, `docs/11`
**Verify:** `./ios/scripts/lint.sh`; iOS unit + snapshot; `./ios/scripts/verify-fixture.sh`;
simulator pass on iPhone 17
**Proves:** AC-12

- [ ] Each results card carries mark-and-count for all three kinds, in `monoS`, under the
      *"4 of 7 got it"* line; zeros dimmed to `inkFaint`.
- [ ] A card with no reactions draws no row, not three zeros.
- [ ] Your own mark is filled and tappable while this is tonight's round; read-only on any past
      round reached through The Record.
- [ ] **Your own card carries the reaction row too** — this screen is the only place the marks
      reach it (`docs/19` §4), and the row is not styled or labelled differently for it.
- [ ] A round from before this shipped renders exactly as it did before — three zeros draw no
      row, no empty state, no explanation.
- [ ] The counts arrive inside the existing progressive resolve, not as a second animation.
- [ ] Nothing about reactions reaches the share card, standings, the profile or insights —
      asserted by a test, not by inspection.
- [ ] Snapshots at SE and 15 Pro Max × `large`/`accessibility5`, including a pre-feature round.
- [ ] Simulator: tonight's answers, a Record night from before the feature, a Record night after.
