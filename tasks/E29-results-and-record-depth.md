# E29 — Results and Record, deepened

Three slices from `docs/17-NEXT-FEATURES.md` §1–§3: the results screen tells you who guessed your
own song and how tonight ranked, past nights on the Record can be listened to again, and the
Apple Music/Spotify open links you already get on Results and the Record show up everywhere a card
does.

`E29-01` and `E29-02` both touch `ResultsScreen.swift`; keep them out of the same worktree if run
as a batch. `E29-03` touches neither.

---

### E29-01 — Who guessed you, and how tonight stacked up

**Status:** done
**Deps:** —
**Parallel:** vs E29-03
**Reads:** `docs/17-NEXT-FEATURES.md` §1, `docs/04-API-CONTRACT.md`, `docs/08-SCREEN-SPECS.md` §7,
`docs/16-OUT-OF-SCOPE.md` §5
**Touches:** `server/supabase/functions/rounds/index.ts`, `server/supabase/functions/_shared/dto.ts`,
`server/scripts/audit-leak.mjs`, `server/supabase/tests/functions/results.test.ts`,
`ios/BlindDrop/Core/Networking/DTO/ResultsDTO.swift`, `ios/BlindDrop/Features/Results/ResultsScreen.swift`,
`ios/BlindDrop/Features/Results/ResultsStore.swift`, `ios/BlindDropTests/Unit/ResultsTests.swift`,
`ios/BlindDropTests/Snapshot/ResultsSnapshotTests.swift`, `docs/08-SCREEN-SPECS.md`
**Verify:** `cd server && npm run test:functions && npm run audit:leak`;
`-only-testing:BlindDropUnitTests/ResultsTests -only-testing:BlindDropSnapshotTests/ResultsSnapshotTests`;
`./ios/scripts/lint.sh`. Simulator: a scored round, confirm a "who guessed you" list appears under
the caller's own card and nowhere else; confirm a "tonight" top-3 module appears near (not merged
into) the all-time standings. Also load the same round while `revealed` (before scoring) and
confirm neither new element exists yet.
**Proves:** AC-1, AC-8

Two additions to `GET /rounds/{id}/results`, once `scored`:

- [x] `cards[].guesses: [{guesser_id, guesser_name, guessed_user_id, guessed_name, is_correct}]`
      — every guesser and their pick for the card the caller owns, sourced from `guess_results`
      (`0005_scoring.sql`) filtered to that card, `null` on every other card. No green/red for
      correctness (`docs/16` §5) — reuses the neutral ultramarine/inkDim word-mark `FlightCard`
      already uses for a `.resolved` card. **Field names deviate from this checklist's own
      sketch** (`guesser_name`/`picked_name`/`correct`) in favour of this codebase's established
      DTO convention (`guesser_id`/`guesser_name`, `guessed_user_id`/`guessed_name`,
      `is_correct`) — matches `MyGuessDTO`'s existing shape instead of inventing a second one.
      There is no separate `my_card` object anywhere in the DTO layer; `guesses` is a field on
      the existing per-card `ResultCardDTO`, populated only for the card the caller owns.
- [x] `tonight_top_ear: [{rank, user_id, display_name, ear}]` — top 3 by Ear for this round only,
      sourced from `round_scores`, competition-ranked the same way `standings` does (ties share a
      rank, the next rank skips). A tie sitting across the rank-3 boundary is kept whole rather
      than truncated. Never rank readability (`docs/16` §5).
- [x] Leak safety: the whole endpoint is already gated to `scored` (`requirePhase`), so `guesses`
      and `tonight_top_ear` cannot appear on an `open`- or `revealed`-phase response by
      construction — there is no route that returns partial `results` data early to guard
      against. `audit:leak`'s golden (`round_results.json`) gains both keys, reviewed before
      regenerating; a dedicated `results.test.ts` test asserts `guesses` is `null` on every card
      but the caller's own, from more than one caller's point of view.
- [x] iOS: a "who guessed you" disclosure under the caller's own answer card in `ResultsScreen`
      (`GuessedYouDisclosure`, gated on that card's own resolve sequence finishing), and a
      `TonightTopEarView` module beside — not merged into — `StandingsView`.

---

### E29-02 — Preview playback on past results

**Status:** todo
**Deps:** —
**Parallel:** vs E29-03
**Reads:** `docs/17-NEXT-FEATURES.md` §2, `docs/16-OUT-OF-SCOPE.md` §3
**Touches:** `ios/BlindDrop/Features/Record/RecordScreen.swift`,
`ios/BlindDrop/Features/Results/ResultsScreen.swift` (only if its `player` parameter needs
adjusting), `ios/BlindDropTests/Unit/RecordTests.swift`,
`ios/BlindDropTests/Unit/PreviewPlayerTests.swift`, `ios/BlindDropTests/Snapshot/RecordSnapshotTests.swift`
**Verify:** `-only-testing:BlindDropUnitTests/RecordTests -only-testing:BlindDropUnitTests/PreviewPlayerTests -only-testing:BlindDropSnapshotTests/RecordSnapshotTests`;
`./ios/scripts/lint.sh`. Simulator: open the Record, tap into a past scored round, play a card's
preview, play a second card while the first is still going (confirm it stops the first — never
queued), background the app mid-preview, navigate away mid-preview — confirm playback stops in
both cases.
**Proves:** —

`ResultsScreen` already accepts a `player` argument on the live results path.
`RecordResultsScreen` currently builds `ResultsScreen(state: store.viewState(resolve: nil))` with
no `player`, so it defaults to `nil` and past rounds get no preview playback at all.

- [ ] Confirm `player`'s exact type and behavior on the live path first.
- [ ] Wire a real instance through `RecordResultsScreen` so past-round cards get the same
      tap-to-preview behavior as live results.
- [ ] Confirm the existing constraints still hold on this path: preview only, 30 seconds, from the
      catalog, never autoplaying, never queued, never backgrounded (`docs/16` §3).
- [ ] No server change is expected — if one turns out to be needed, say why before adding it.

---

### E29-03 — Song links, consistent across every card state

**Status:** todo
**Deps:** —
**Parallel:** vs E29-01, E29-02
**Reads:** `docs/17-NEXT-FEATURES.md` §3, `docs/06-MUSIC-INTEGRATION.md`
**Touches:** `ios/BlindDrop/DesignSystem/Components/TrackLinks.swift`, the revealed-phase
flight-card view (confirm the exact file first — likely under `ios/BlindDrop/Features/Reveal/`,
distinct from `GuessSheet.swift`'s call sheet), `ios/BlindDropTests/Unit/SongLinkTests.swift`
**Verify:** `-only-testing:BlindDropUnitTests/SongLinkTests`; `./ios/scripts/lint.sh`. Simulator:
during the revealed/guessing phase (before scoring), open a card's link menu and confirm Apple
Music/Spotify open exactly as they do on Results and the Record.
**Proves:** —

This slice starts with a gap check, not an assumption: `TrackUtilityMenu` already exists on the
sealed/submitted card, results answer cards, and Record rows. Confirm first whether it's missing
from the revealed-phase guessing cards — if it's already there, close this slice as a verified
no-op rather than inventing work. If it's missing, add it there for consistency.

**Non-goals:** no Spotify playback (`docs/16` §3 — previews are Apple Music only, Spotify is
identity/export). No change to track-link resolution timing unless a measurement (extend the
existing `E27-01` coverage query, don't duplicate it) shows it's actually lagging past when it's
useful.
