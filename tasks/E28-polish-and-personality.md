# E28 — Polish, and giving the quiet screens a face

Owner-driven pass over the beta build. Eight slices: five are bugs and layout failures found by
using the app, three are design work on the screens that shipped correct and boring.

Three owner amendments are recorded here, because they change rules other files state:

- **A1 · The thin-history gates come off for the test stage.** `docs/08` §10.1's "five scored
  rounds" and `GroupStore.thinHistoryThreshold`'s leaderboard swap both hide numbers that testers
  need to see. Every stat shows from the first round; zero rounds shows `—` and *No rounds*.
  One constant, one marker, restored before public beta (`E28-06`).
- **A2 · Hold to peek plays the song.** `docs/08` §4 describes a silent visual peek on the
  title/artist strip. It becomes a hold anywhere on the card, with a fade in, and the 30-second
  preview plays for exactly as long as the finger is down (`E28-04`).
  > **Note for the owner:** audio carries further than a screen does. A peek held in a room with
  > other people in it is audible to them, and `.playback` ignores the silent switch. This is a
  > deliberate choice, not an oversight — say so if it ever comes back as a bug report.
- **A3 · The Record leaves the header menu.** It keeps its `Route`; only the entry point moves,
  to the foot of the Group screen (`E28-06`). `docs/08` §8's "always reachable" still holds.

---

### E28-01 — The keyboard stops shoving Start a group off the screen

**Status:** done
**Deps:** —
**Reads:** docs/08 §1.4, docs/07 §4
**Touches:** `ios/BlindDrop/Features/Onboarding/StartGroupSheet.swift`,
`ios/BlindDrop/Features/Round/RoundScreen.swift`,
`ios/BlindDropTests/Snapshot/StartGroupSnapshotTests.swift`
**Verify:** `./ios/scripts/lint.sh`; `-only-testing:BlindDropSnapshotTests/StartGroupSnapshotTests`.
Simulator: open the switcher → **Start a group**, focus the name field, confirm the title stays
put and **Create group** sits above the keyboard; type a long name; dismiss by dragging; rotate
the reveal-hour menu open with the keyboard up.
**Proves:** —

`StartGroupForm` is one full-height `VStack` with a `Spacer` above the button, so SwiftUI's
keyboard avoidance lifts the entire column: the title leaves the screen at the top and the button
is still clipped at the bottom. Restructure it as the three parts it actually is.

- [x] Header (title + close) pinned outside the scroll region — it never moves.
- [x] Name, timezone and reveal hour in a `ScrollView` with
      `.scrollDismissesKeyboard(.interactively)`; the flexible gap goes, so the fields sit closer
      together when the keyboard is up and scroll rather than shift when they do not fit.
- [x] **Create group** in a `.safeAreaInset(edge: .bottom)` over a `Palette.paper` backing, so it
      rides above the keyboard at every Dynamic Type size.
- [x] `.presentationBackground(Palette.paper)` on the sheet, so no system background shows at the
      edges when the inset resolves.
- [x] The failure line stays with the field it belongs to, not floating above the pinned button.

---

### E28-02 — Searching for a replacement, without the grey box or the ghost rows

**Status:** done
**Deps:** —
**Reads:** docs/08 §3.1, §4
**Touches:** `ios/BlindDrop/Features/Submit/SearchSheet.swift`,
`ios/BlindDrop/Features/Submit/SongSearch.swift`,
`ios/BlindDrop/Features/Round/RoundScreen.swift`
**Verify:** `./ios/scripts/lint.sh`; `-only-testing:BlindDropSnapshotTests/SubmitSnapshotTests`;
`./ios/scripts/verify-fixture.sh BlindDropUnitTests/FixtureRoundTests "Round"`. Simulator: from a
sealed round tap **Replace song**, search a term with many results, scroll to the bottom with the
keyboard up and down, and **tap the region that used to be the gap** — nothing must be selectable
where nothing is drawn.
**Proves:** AC-10

Two defects, one cause. `SearchSheet` paints `Palette.paper` on a padded, keyboard-avoided frame
while the sheet itself and its `NavigationStack` are taller than that frame — so the strip below
it is the system's background (the grey box), and the results `ScrollView` keeps drawing rows into
it outside where the layout believes it ends. Those are the rows that flash in the gap and that
answer a tap.

- [x] `.presentationBackground(Palette.paper)` and `.presentationDetents([.large])` on the sheet,
      so the sheet has one background and one height that the keyboard does not renegotiate.
- [x] The vertical padding comes off the container and onto the header and the scroll content;
      the results `ScrollView` runs to the sheet's bottom edge, with rows visible behind the
      keyboard exactly as `SubmitScreen` already shows them.
- [x] Bottom `contentMargins` rather than a trailing `padding` on the `LazyVStack`, so the last
      row can be scrolled clear of the keyboard.
- [x] Confirm the fix on the first-drop path too (`SubmitScreen`), which shares `SongSearch`.

---

### E28-03 — The call sheet answers a flick

**Status:** done
**Deps:** —
**Reads:** docs/08 §6, docs/09 §1
**Touches:** `ios/BlindDrop/Features/Reveal/GuessSheet.swift`,
`ios/BlindDropTests/Unit/CallSheetDetentTests.swift`
**Verify:** `-only-testing:BlindDropUnitTests/CallSheetDetentTests`; `./ios/scripts/lint.sh`.
Simulator: on a revealed round, flick the header down and up ten times each — every flick must
commit and stay committed; a deliberate slow drag released short must still spring back; a plain
tap must still toggle.
**Proves:** —

The owner's diagnosis is right and the code confirms it: `peekHeader`'s background carries
`.gesture(dragGesture)` **and** `.onTapGesture` on the same view. A quick flick satisfies both —
the drag commits the new detent, the tap immediately toggles it back — which is why a flick
appears to do nothing and only a long, slow drag works.

- [x] Compose them exclusively (`dragGesture.exclusively(before:)`) so one gesture resolves per
      touch. The VoiceOver `accessibilityAction` path is unaffected and stays.
- [x] `CallSheetDetent.resolved` takes velocity: commit on `|velocity| > 250 pt/s` in the right
      direction whatever the distance, otherwise fall back to the predicted-distance threshold,
      lowered from `0.25` to `0.2` of the collapse distance.
- [x] `minimumDistance` raised from `Space.xs` to `Space.sm`, so a tap cannot begin as a drag.
- [x] `CallSheetDetentTests` gains the flick cases in both directions, the slow non-committing
      drag, and the exact-velocity edge.

---

### E28-04 — Hold to peek, actually held, and heard

**Status:** done
**Deps:** —
**Reads:** docs/08 §4, docs/09 §2 §5, docs/12 §5 §7
**Touches:** `ios/BlindDrop/DesignSystem/Components/SealedCard.swift`,
`ios/BlindDrop/Features/Submit/SealedScreen.swift`,
`ios/BlindDrop/Features/Round/RoundScreen.swift`,
`ios/BlindDrop/DesignSystem/Motion/MotionTokens.swift`, `docs/08-SCREEN-SPECS.md`
**Verify:** `-only-testing:BlindDropSnapshotTests/SubmitSnapshotTests`;
`-only-testing:BlindDropUnitTests/PreviewPlayerTests`; `./ios/scripts/lint.sh`. Simulator: hold
the artwork, hold the strip, hold and drag off, hold and background the app, hold with a track
that has no preview URL. Screenshot held and released.

Implements amendment **A2**. Today the gesture is attached only to `peekableMetadata` — the
strip under the artwork — which is why the top of the card does nothing, and the cover's opacity
flips with no animation in either direction, which is why it snaps. Nothing plays.

- [x] The gesture moves to the whole card: artwork and strip are one target. The service
      ellipsis stays an overlay above it and keeps its own hit area.
- [x] **Opening animates, closing does not.** A new `Motion.Peek` token — ~180ms ease-out on the
      cover's opacity plus a small artwork scale — and the title/artist cross-fades into the
      strip's place instead of swapping. `reseal()` keeps its `disablesAnimations` transaction
      untouched: `docs/08` §4's "immediately, with no animation" is the half of this rule that
      exists for a reason.
- [x] Under reduced motion the open is a plain crossfade with no scale (`docs/09` §5).
- [x] `SealedScreen` takes the shared `PreviewPlayer` from `RoundScreen`. Hold start plays the
      caller's own preview; every path that calls `reseal()` — release, drag-out, backgrounding,
      navigation, `onDisappear` — stops it. A track with no `preview_url` peeks silently.
- [x] The service ellipsis moves 8pt up and right (`Layout.cardInset`, dropping the extra
      `Space.sm` on both axes) so it stops crowding the seal.
- [x] `docs/08` §4's Sealed section rewritten to match, in the same commit.

---

### E28-05 — Answers with room for the song

**Status:** done
**Deps:** —
**Reads:** docs/08 §7.1, docs/07 §5, docs/12 §1
**Touches:** `ios/BlindDrop/DesignSystem/Components/FlightCard.swift`,
`ios/BlindDrop/Features/Results/ResultsScreen.swift`,
`ios/BlindDropTests/Snapshot/ResultsSnapshotTests.swift`
**Verify:** `-only-testing:BlindDropSnapshotTests/ResultsSnapshotTests -only-testing:BlindDropUnitTests/ResultsTests`;
`./ios/scripts/lint.sh`. Simulator: a scored round with long titles (*matrix (blue crush mix)*,
*Cellophane*), scrolled top to bottom, with a preview played from a card. Screenshot the arrival.
**Proves:** AC-9

Two things. The screen arrives with its title in the middle of the page because
`ResultsScreen`'s `minHeight` frame is `.center`-aligned and the content grows as the personal
stats and standings land under it. And the answer card gives its title the width left over after
a two-digit number, 76pt of artwork **and** a 44pt ellipsis, so an ordinary title truncates at
full size — `E26-01` measured this and left it as a known limit; this is the reflow it named.

- [x] The scroll content anchors `.top`. The jump goes; a short page is top-aligned, which is
      what every other screen in the app does.
- [x] **The answer card gets a header row.** The number moves to its own line at the top with the
      service ellipsis opposite it. Below that, artwork and the title/artist column get the card's
      full width — roughly 96pt more on an iPhone 17. Title `lineLimit(2)`, artist `lineLimit(1)`,
      and `minimumScaleFactor` returns to 1: the shrink was compensation for a column that is no
      longer narrow.
- [x] The preview control comes off the artist's line onto its own, left-aligned under the text
      column, where it is a control rather than a competitor for the artist's width.
- [x] `HOW THE ROOM DID` takes its count onto the label row, right-aligned, so the
      `ProportionBar` runs the full card width.
- [x] The `isStacked` fork for the **answer** card goes: the new arrangement is already the
      stacked one, so there is one layout at every type size and one golden per device instead
      of two. The reveal's `flightRow` is untouched — different density, different problem.
- [x] `E26-01`'s open question in `tasks/E26-ui-polish.md` is answered and closed.

---

### E28-06 — Every stat, shown; every screen, quieter

**Status:** done
**Deps:** —
**Parallel:** vs E28-01…05
**Reads:** docs/08 §9, §10.1, §11, docs/11
**Touches:** `ios/BlindDrop/Features/Profile/MemberProfileScreen.swift`,
`ios/BlindDrop/Features/Profile/MemberProfileStore.swift`,
`ios/BlindDrop/Features/Settings/GroupScreen.swift`,
`ios/BlindDrop/Features/Settings/GroupStore.swift`,
`ios/BlindDrop/Features/Insights/InsightsStore.swift`,
`ios/BlindDrop/Features/Round/RoundScreen.swift`,
`ios/BlindDrop/Resources/Localizable.strings`, `docs/11-COPY-DECK.md`,
`docs/08-SCREEN-SPECS.md`
**Verify:** `-only-testing:BlindDropUnitTests/ProfileTests -only-testing:BlindDropUnitTests/GroupStoreTests`;
`-only-testing:BlindDropSnapshotTests/MemberProfileSnapshotTests -only-testing:BlindDropSnapshotTests/GroupScreenSnapshotTests`;
`./ios/scripts/lint.sh`. Simulator: Group → a profile → back, **watching for the skeleton**;
open Group with an unchanged name and confirm **Save name** is disabled until a keystroke; find
The Record at the foot of the Group screen.
**Proves:** —

Implements amendments **A1** and **A3**, plus the copy trim and the re-entry flash.

- [x] **No thresholds.** `MemberProfileContent.minimumSamples` and `GroupStore.thinHistoryThreshold`
      stop hiding numbers. Zero rounds renders `ScoringFormat.unavailable` with *No rounds*; one
      round renders the real percentage. Both constants survive in one place behind a
      `// Restore before public beta` marker.
- [x] **The copy trim**, in the deck and the strings file together:
      `profile.samples` → `"%lld rounds"`; `profile.pairwise.detail` → `"%lld of %lld rounds"`;
      `profile.drops.detail` deleted (Drops carries no line); `profile.samples.minimum` and
      `profile.pairwise.minimum` deleted; `profile.subtitle.own`/`.member` deleted and the header
      line with them; `group.name.help` deleted; `group.revealhour.help` →
      *"A change applies to the next round, never the current one."*
- [x] **No skeleton on the way back.** `GroupStore`, `MemberProfileStore` and `InsightsStore` stop
      clearing to `.loading` when they already hold a value — they refresh in place, exactly as
      `GroupStore` already does for standings — and `GroupScreen` renders content whenever
      `store.group != nil` rather than on `isLoading`. A failed refresh keeps the old value
      through `LoadState.stale`, which is what that case is for.
- [x] **Save name is disabled on arrival.** The `nameDirty` flag is set by the `onChange` that
      `onAppear`'s own assignment fires, so it is `true` before anybody types. Compare
      `nameField` against `group.name` instead of tracking a flag.
- [x] **Group screen order:** leaderboard, then the name field, then reveal hour, then timezone,
      then The Record, then Leave.
- [x] **The Record's entry point moves** from the header menu to a row at the foot of the Group
      screen. `Route.record` and `RoutingTests`' four-case assertion are unchanged.
- [x] **The menu's Insights glyph** stops being `eye`. `point.3.connected.trianglepath.dotted` —
      three linked points, which is what the screen is actually about.

---

### E28-07 — Insights that rank, and rank fairly

**Status:** done
**Deps:** E28-06
**Parallel:** no
**Reads:** docs/04 §3, docs/08 §10.1, docs/11, tasks/E25-insights.md
**Touches:** `server/supabase/functions/_shared/insights.ts`,
`server/supabase/functions/groups/index.ts`, `server/supabase/functions/_shared/dto.ts`,
`ios/BlindDrop/Core/Networking/DTO/InsightsDTO.swift`,
`ios/BlindDrop/Features/Insights/InsightsScreen.swift`,
`ios/BlindDrop/Features/Insights/InsightsStore.swift`,
`ios/BlindDrop/Resources/Localizable.strings`, `docs/11-COPY-DECK.md`,
`server/supabase/tests/`, `ios/BlindDropTests/Unit/InsightsTests.swift`,
`ios/BlindDropTests/Snapshot/InsightsSnapshotTests.swift`
**Verify:** `cd server && npm run test:functions && npm run audit:leak`;
`-only-testing:BlindDropUnitTests/InsightsTests -only-testing:BlindDropSnapshotTests/InsightsSnapshotTests`.
Simulator: Insights on a circle with mixed volumes — confirm 8 of 12 outranks 3 of 4 and 7 of 12
still does; tap a card into its leaderboard; tap a name into a profile; confirm Mistaken identity
shows without waiting.
**Proves:** —

Four changes, one screen.

**The ranking is volume-aware.** A rate alone puts 3 of 4 above 8 of 12, which is not what anyone
means by *reads them best*. Order every rate by its **Wilson score lower bound** at 95%, which is
a confidence interval rather than an invented weighting and answers the owner's three cases
exactly: 8/12 → 0.391, 7/12 → 0.320, 3/4 → 0.301, 6/12 → 0.246. So 8 of 12 always beats 3 of 4,
7 of 12 still beats it, and 6 of 12 does not. *Hardest to read* uses the **upper** bound by the
same argument, so one unlucky round with one person does not top the list. Ties break on the
larger denominator, everywhere, per the owner.

- [x] `wilsonLowerBound` / `wilsonUpperBound` in `_shared/insights.ts`, with a pgTAP-free Deno
      test pinning the four worked cases above and the degenerate `possible == 0`.
- [x] `compareReadDescending`, `compareReadAscending` and `comparePair` reorder on it; the
      denominator tie-break moves directly behind the score in all three.
- [x] **Mutual reads gets ranks and a left edge.** The centred names go; each row is a mono rank
      numeral (`1 2 3`), the pair, and *"x of n reads"* beneath — no period, and the word
      *shared* leaves the deck entirely (`insights.detail` → `"%lld of %lld reads"`).
- [x] **Your reads loses the chevron and gains a leaderboard.** The card centres on the
      percentage and the name; tapping the card opens a ranked list of the whole circle for that
      stat — second, third, last, with each row's denominator visible, which is the honest answer
      to small-sample bias. Tapping the **name** still opens their profile. Both reachable as
      distinct VoiceOver actions on one element.
- [x] The server sends the full ordered lists (`your_reads`, `reads_you`) rather than a single
      best; the three headline cards are the first element of each. No new endpoint, no raw
      guesses on the wire, and `audit:leak` re-run because the payload grew.
- [x] **Mistaken identity shows now.** `confusionMinimumRounds` stops gating the surface, behind
      the same `// Restore before public beta` marker as `E28-06`'s thresholds. Empty stays
      *"No repeated mix-ups yet."*
- [x] `insights.subtitle` → *"Your group dynamics"*.

---

### E28-08 — The printed sheet: Group, Profile and Insights get a face

**Status:** done
**Deps:** E28-06, E28-07
**Parallel:** no
**Reads:** docs/07 §1–§5, docs/08 §9 §10.1, docs/12 §1 §2, docs/16 §1
**Touches:** `ios/BlindDrop/DesignSystem/Components/` (new `MonogramMark`, `StatFigure`,
`SheetMeta`), `ios/BlindDrop/Features/Settings/GroupScreen.swift`,
`ios/BlindDrop/Features/Profile/MemberProfileScreen.swift`,
`ios/BlindDrop/Features/Insights/InsightsScreen.swift`, snapshots
**Verify:** `-only-testing:BlindDropSnapshotTests -only-testing:BlindDropUnitTests/PaletteContrastTests -only-testing:BlindDropUnitTests/A11yReachabilityTests`;
`./ios/scripts/lint.sh`. Simulator: all three screens, scrolled, with real artwork loaded.
Screenshot each before and after and put them side by side.
**Proves:** AC-2 gates

The three screens are correct and dull. **The constraint is the design.** `CLAUDE.md` §2.5 rules
out making them interesting with colour, §2.7 rules out making them interesting with rewards, and
`docs/07` §2 rules out shadows. What is left is what the app is already good at and only spends
on the game screens: **enormous tabular numerals, mono micro-labels, hairline rules, proportion
bars, and album art.** These screens should read like the flight sheet the results screen reads
like — printed apparatus, not a settings list.

- [x] **`StatFigure`.** Every rate on Profile and Insights becomes a `numberL` figure with its
      mono label above and a hairline `ProportionBar` beneath. The bar is neutral (`track` /
      `inkDim`), carries no accent, and turns three walls of text into three things to scan. This
      is the single biggest change and the rest is detail.
- [x] **`MonogramMark`.** `SealStamp`'s circled-initial geometry in `inkQuiet`/`inkDim` — *not*
      the amber stamp, which means *sealed* and cannot be borrowed for an avatar without breaking
      §2.5. On the unranked roster row, the profile header, and the Insights leaderboard rows.
      **Not** on the ranked leaderboard row (`StandingsView.StandingRowContent`) — added there
      first, then measured and reverted: on `GroupScreen`'s admin view that row already shares
      its width with a fixed-size numbers block, a rank numeral, *and* a trailing action menu,
      and the mark's 36pt pushed the name itself to zero width on an SE. A snapshot golden caught
      it before it shipped (see `Group-three-ranked-SE-large`); the ranked row keeps its new
      zero-padded numeral but stays markless everywhere the numbers already fill the row.
- [x] **Album art earns its place — on the profile, not the roster row.** The profile header gains
      a strip of the member's last five covers, from data the profile fetch already carries
      (`MemberProfileDTO.recentTracks`). The roster-row thumbnail is **not** done: it needs a new
      server field on `GroupDTO.members`/`StandingsDTO`, and Group is reachable during `open` —
      adding per-member track data there needs a real look at `CLAUDE.md` §2.1 before it ships,
      not a design-pass addition. Descoped rather than rushed; a follow-up slice if wanted.
- [x] **Ranks in the game's own hand.** The group leaderboard's rank column becomes the flight
      card's zero-padded `numberM` (`01 02 03`) in a measured fixed column, matching
      `FlightCard.numberColumnWidth` rather than approximating it.
- [x] **`SheetMeta`.** One mono line under each screen's title — `12 MEMBERS · 144 ROUNDS` — over
      a rule. It replaces the deleted subtitles with a fact instead of a sentence.
- [x] **Fewer boxes.** Insights' cards-inside-cards flatten to one ruled panel per section, the
      shape `StandingsView.table` already uses. This is the clutter the owner named.
- [x] **Skeletons shaped like their screens.** `RoundSkeleton` is the round's shape and promises
      the wrong thing on these three. Each gets its own: the group's row stack, the profile's
      three figures and list, the insights panel set. With `E28-06`'s in-place refresh, a
      skeleton is now only ever seen once per screen per launch.
- [x] `PaletteContrastTests` and `A11yReachabilityTests` re-run: nothing here introduces a colour,
      and nothing here may cost a VoiceOver stop.

> **Open question (for the owner, not blocking) — resolved conservatively, revisit if wanted.**
> The artwork strip is the first time a non-game screen carries arbitrary colour. It shipped on
> the profile header only, not the roster row: the roster row's version would need a new server
> field (per-member recent-track data on `GroupDTO.members`/`StandingsDTO`), and Group is
> reachable during `open` — extending that payload needs a real look against `CLAUDE.md` §2.1
> before it ships, not a design-pass addition. The profile's strip is already-fetched data
> (`recentTracks`), so it needed no new server surface and no leak-audit re-review.

---

## Verified (this pass)

- `xcodebuild build` — succeeds.
- `BlindDropUnitTests` — 442 tests, 442 pass.
- `BlindDropSnapshotTests` — 81 tests in 16 suites, all pass after re-recording the 9 suites this
  pass actually changed (Group, GroupScreen, Results, Insights, Profile, Components, Submit,
  Onboarding — split as `GroupSnapshotTests`/`GroupScreenSnapshotTests` are two suites). Every
  golden was looked at before recording, not rubber-stamped — that pass is what caught the
  `MonogramMark` regression on the ranked leaderboard row, fixed before anything was committed.
  `CircleSwitcherSnapshotTests`, untouched by this epic, failed once (12 mismatches) and passed
  clean on every other run; treated as environment flake, not investigated further.
- Live on iPhone 17 (simulator, fixture server, `-fixtureSession`): sealed round with hold-to-peek
  (opens, resolves cleanly, no lingering state); header menu (Record absent, Insights' new glyph);
  Group (meta line, ranked names correct post-fix, disabled Save name, reordered sections, Record
  link); Insights ("Your reads" tap → leaderboard → name tap → profile, full navigation chain);
  Profile (monogram, artwork strip, flattened stat panels). Not driven live: `StartGroupSheet`'s
  keyboard behaviour, the call sheet flick, and `SearchSheet`'s replace-song flow — verified by
  code review and snapshot goldens only, not by an on-device gesture.
- `server/` TypeScript changes (Wilson scoring, `your_reads`/`reads_you`, confusion gate removal)
  — the local Supabase stack turned out to already be running, so this ran for real: `npm run
  test:db` (684 pgTAP assertions, all green, untouched by this epic), `npm run test:functions`
  (267 passed / 4 failed — see below), `npm run audit:leak` (green; the insights payload grew and
  the leak audit still passed). Two failures this pass caused, both fixed in the same commit as
  the code: a stale `standings.test.ts` assertion still expecting `confusion.pairs: []` after the
  gate came off (now pins the 3 pairs the fixture actually produces), and a bad new assertion of
  a strict `>` between two Wilson bounds that are legitimately equal in that fixture (now
  `assertEquals`). The remaining **4 failures, all in `circle_switcher.test.ts`, are pre-existing
  and unrelated** — confirmed via `git diff` that this epic never touched that file or the
  `circleCallerState` function they fail in, and reproduced independently: a time-of-day-dependent
  bug where the server's "today" for a circle's round lookup does not account for the reveal
  hour once it has passed, which `ensure_rounds()` already does. Filed as its own follow-up
  rather than folded in here.
