# E17 — Polish pass

Nine corrections to things that shipped working but not right: two real bugs, three layout
mistakes, two interactions that were flat, and two rules the owner has amended.

Three product-defining rules change here, and each is called out in the task that changes it.
None of them is an agent's call — they are recorded because the owner made them:

| Rule | Was | Now |
|---|---|---|
| `CLAUDE.md` §2.5 | Never both accents on one screen except the reveal transition | …and except **How to play**, which is the legend (E17-05) |
| `docs/09` §1 | Two haptic notes, and no third | Three. `.nameLands` joins them (E17-07) |
| `docs/10` §1 | The share sheet offers both variants | It offers square-tall. `story` stays in the model, retired from the UI (E17-02) |

---

## State of play — read this before touching E17

**All nine are implemented in the working tree and none of them was ever verified.** The code
landed uncommitted; the board said `todo`; the tests were not run. They were run on 2026-08-17
and this is what is actually true:

| | |
|---|---|
| `./ios/scripts/lint.sh` | clean |
| Unit | **1 failure** of 388 — `SealAnimationTests.bothGeneratorsAreWarmedFirst` |
| Snapshot | **45 issues** of 58 — SubmitSnapshots 20, RevealSnapshots 14, ResultsSnapshots 9, ShareCardSnapshots 2 |

The unit failure is a genuine defect, not a stale expectation: E17-07 added `Haptic.nameLands`
to the enum without adding it to the warm-up path, so the assertion that every case is
pre-warmed fails. A cold generator is exactly the timing problem `SystemHaptics` was written to
avoid, so this is the bug the test was put there to catch, working.

The snapshot mismatches were inspected rather than assumed. They are **stale goldens, not
regressions** — the GuessSheet diff, for instance, is the grabber becoming a real control with
the spacing E17-06 asked for. Only HowTo's goldens were re-recorded; the other four suites' were
not. They still need looking at one by one before anything is re-recorded.

Two spec gaps: `docs/08-SCREEN-SPECS.md` is untouched, which E17-09's last checklist item
requires, and `CreateGroupScreen.swift` is untouched despite being in E17-04's **Touches**.

`E17-10` closes all of it. Nothing in E17 is `done` until it passes.

### What E17-10 actually found (2026-08-17)

The assumption above — *"stale goldens, not regressions"* — held for about half of them. Five
real defects were behind the other half, and three of the nine slices were not doing what their
own checklists claim:

| | |
|---|---|
| `Haptic.nameLands` never warmed | The known one. `.stampLands` was cold on the reveal too, which nothing had noticed: `lockIn()` fires it and only the *seal* ever warmed it. |
| The sealed card lost its corner links | `SealedScreen` was switched to `TrackUtilityMenu`, against `E17-03`'s own *"`CardCornerLinks` stays"*. It left the component with **zero callers** and, because `ImageRenderer` cannot draw a `Menu`, put a red-slashed placeholder where the Apple Music link belongs in all eight Sealed goldens. Reverted. |
| `GuessSheetHeightKey` never arrived | Preferences do not cross out of a `.background` branch, so the host read the key's *default* for both numbers from the day `E17-06` landed. `full − peek` came out zero, which silently disabled both things it feeds: the flight's landing strip and `updateVisibleCards`' sheet subtraction. Now a `CallSheetMetrics` closure. |
| The call sheet's tap target was two words wide | The heading row's `Spacer` is not hittable, so only the label itself toggled the detent — the same dead-`Spacer` hit region `E17-02` found on the share sheet, in a second place. |
| The search screen's background tap never dismissed the keyboard | `E17-04` claims it does. It does in the idle state; in the browsing state `rows` is a greedy `ScrollView` that eats the tap, which is every search that has returned anything. |

Two further layout faults, neither of them stale-golden material: the reveal's countdown badge
starved *"Tonight's drop"* to a single wrapped letter at `accessibility5`, and the collapsed
call sheet showed the top of the name row through a sheet that is meant to be shut.

`CLAUDE.md` §5's re-record recipe was also wrong — the variable trailed `xcodebuild`, where it
is parsed as a build setting and does nothing. `SnapshotRenderer.isRecording` documents both
spellings and has all along.

### What review found in the fix (2026-08-17)

The `reviewer` agent read the finished diff against `CallSheetMetrics`, `bodyOpacity`, and the
occlusion padding specifically — the newest and least-exercised code in the slice, since the
drag itself was never driven on device (above). Three of five findings were real and are fixed;
two were judged and left alone:

| | |
|---|---|
| The drag's non-committing release wasn't animated | `dragGesture.onEnded` set `dragOffset = 0` bare. The body's `.animation(_:value: detent)` only covers a *committed* drag — one that changes `detent` — so a drag released short of the threshold snapped back in one frame instead of springing. Both branches now wrap the reset in `withAnimation(Motion.CallSheet.spring)`. Confirmed on device: a partial drag below threshold now returns smoothly. |
| A repeated identical save failure never reopened the sheet | `lockIn()` collapses the sheet optimistically before the save resolves; `GuessSheet` reopens it on `saveErrorKey`'s `onChange`. `onChange` only fires on a *value change* — `didEdit()` already clears the key first for that reason, `lockIn()` did not. Retry after one offline failure, fail again the same way, and the key read identically before and after: no transition, no reopen, and a locked-then-failed sheet sitting at peek with an ordinary progress line, nothing telling the user the retry also failed. `lockIn()` now clears `saveErrorKey` first, matching `didEdit()`. |
| `updateVisibleCards`'s bounds went stale when the sheet opened without a scroll | The recompute lived entirely inside `.onPreferenceChange(RevealCardFrames.self)`, which fires on a card *frame* changing — scroll-driven. Opening the sheet by tapping the peek header with no card focused scrolls nothing, so the bounds `unseal.updateVisibleCards` was checking against did not shrink to exclude the now-covered area during that window. Only reachable while the staggered unseal is still running (a repeat visit reveals everything immediately, `UnsealAnimation.run`), but real: a card could release behind a sheet nobody could see it through. Extracted to one `updateVisibleCards(viewportSize:)`, called from both the frame preference and a new `.onChange(of: occludedByOpenSheet)`, so the two triggers can't disagree. |
| A new scheduled-refresh path in `RoundScreen` (E17-01's `deadline(now:) → Date?` refactor) | Judged: legitimate consequence of the `nil`-on-unanchored-clock change, not scope creep. Left as is. |
| The snapshot-only render path narrows what the `TrackUtilityMenu` goldens prove | Judged: an accepted, already-documented trade — `ImageRenderer` cannot draw a `Menu` at all, and `A11yReachabilityTests` covers the link-destination logic the goldens no longer can. Left as is. |

Full unit (389) and snapshot (58) suites re-run green after the three fixes.

---

### E17-01 — The phase flash on foreground

**Status:** done · **Deps:** — · **Reads:** `docs/13` §5, `CLAUDE.md` §2.2
**Touches:** `BlindDrop/Features/Round/RoundStore.swift`,
`BlindDrop/Features/Round/RoundScreen.swift`, `BlindDrop/Features/Submit/SubmitScreen.swift`
**Verify:** `./ios/scripts/lint.sh`; `xcodebuild test -only-testing:BlindDropUnitTests/RoundStoreTests`

Every return to the foreground rendered one wrong screen for the length of a round trip.
`RootView` invalidates the clock on `.active`; `RoundContext.isBeforeOpen(now:)` answered `nil`
with `false`, which is *"the round is open"*, which is the search screen — keyboard and all —
over a round that was actually done. `deadline(now:)` made the same guess and pointed the
countdown at `revealsAt` instead of `opensAt`, and the header badge drew a countdown pill the
dark hours do not have.

The fix is the one `CountdownTimer.refresh()` already uses and documents: **hold the last
confirmed answer across the gap rather than inventing one.** A number the app knew to be right
400ms ago is not the guess `docs/13` §5 rule 3 forbids; a number it has never confirmed is.

- [x] `RoundContext.OpenState { unknown, beforeOpen, open }` and `openState(now:)`
- [x] `deadline(now:)` returns `nil` rather than a guess when the clock has no anchor
- [x] `RoundScreen` holds the last non-`.unknown` value in `@State` and renders from it
- [x] `RoundStoreTests` — every time-dependent branch has an *unknown* answer, and a context
      can never exist with an unanchored clock (every response anchors before `state.apply`)

---

### E17-02 — One share variant

**Status:** done · **Deps:** — · **Reads:** `docs/10` §1, §4, `CLAUDE.md` §6
**Touches:** `BlindDrop/Features/Results/Share/ShareSheet.swift`,
`BlindDrop/DesignSystem/ShareCard.swift`, `BlindDrop/Resources/Localizable.strings`,
`docs/10-SHARE-CARD-SPEC.md`, `docs/11-COPY-DECK.md`
**Verify:** `./ios/scripts/lint.sh`; `xcodebuild test -only-testing:BlindDropUnitTests/ShareRendererTests -only-testing:BlindDropSnapshotTests/ShareCardSnapshotTests`

The picker's thumbnails were not tappable. `preview()` ends in `.allowsHitTesting(false)` and
the thumbnails are `.buttonStyle(.plain)` with no `contentShape`, so a plain button's hit region
— the union of its label's *hittable* subviews — contained only the caption. The taller story
caption sits ~60pt lower, at the edge of the `.medium` detent, which is why one of the two
appeared to work.

Removed rather than repaired. One variant needs no picker, and the space it frees goes into a
preview large enough to read: the sheet stops asking a question and starts showing the card.

`Variant.story` **stays** — it is spec'd in `docs/10` §3, snapshot-tested, and carries
`ShareRendererTests`' orphaned-file case. Only the UI retires it.

- [x] `ShareSheet` renders one `.squareTall` preview, caption, and **Share tonight**
- [x] Preview widened; `.presentationDetents` re-checked on an SE
- [x] `results.share.square` / `results.share.story` retired for `results.share.caption`
- [x] `Variant.pickerLabel` deleted
- [x] `docs/10` §1 and §4 no longer claim the sheet offers both

---

### E17-03 — The answer card's links become an overflow menu

**Status:** done · **Deps:** — · **Reads:** `docs/08` §7.1, `docs/12` §2
**Touches:** `BlindDrop/DesignSystem/Components/FlightCard.swift`,
`BlindDrop/DesignSystem/Components/TrackLinks.swift`
**Verify:** `./ios/scripts/lint.sh`; `xcodebuild test -only-testing:BlindDropSnapshotTests/ResultsSnapshotTests -only-testing:BlindDropUnitTests/A11yReachabilityTests`

Two 44pt link rows under every answer card cost ~90pt each in a list of up to twelve. The Record
already solved this with `TrackUtilityMenu`; the answer card takes the same ellipsis, top-right.

`CardCornerLinks` stays — `SealedScreen` still draws it in the sealed cover's corner, which is
genuinely dead space and the case the component was written for.

- [x] Links-only overflow menu, factored from `TrackUtilityMenu` — and `CardCornerLinks`
      **restored to `SealedScreen`**, which this slice's own text promised and its code undid.
      See E17-10.
- [x] `answerCard`'s existing centre-aligned row wrapped in a top-aligned `HStack` with the
      menu — no overlay, so it cannot overlap at accessibility sizes
- [x] `cornerLinks` removed from `answerCard`
- [x] Menu `accessibilityHidden`; `body`'s existing `if isAnswer` actions remain the one path

---

### E17-04 — The chrome sits where a header sits

**Status:** done · **Deps:** E17-01 · **Reads:** `docs/07` §4, `docs/12` §5
**Touches:** `BlindDrop/DesignSystem/Space.swift`, `BlindDrop/Features/Round/RoundScreen.swift`,
`BlindDrop/Features/Submit/SongSearch.swift`, `BlindDrop/Features/Submit/SubmitScreen.swift`,
`BlindDrop/Features/Submit/VoidedScreen.swift`,
`BlindDrop/Features/Onboarding/SignInScreen.swift`,
`BlindDrop/Features/Onboarding/CreateGroupScreen.swift` — **listed in error; see E17-10**
**Verify:** `./ios/scripts/lint.sh`; `xcodebuild test -only-testing:BlindDropUnitTests/RoundInsetTests -only-testing:BlindDropSnapshotTests/SubmitSnapshotTests`

Every chrome header sat 32pt below the safe area where a system nav bar sits at 8. The 32 was
insurance: `SongSearch` documents the fight — bottom padding on a pinned element made SwiftUI's
avoidance lift the whole screen and drive the header under the status bar.

Insurance is the wrong instrument. **Layer instead.** The phase content keeps keyboard
avoidance — that is what collapses `SongSearch`'s spacers and floats the heading and field up as
the keyboard arrives, which is the interaction, not a side effect — and the chrome moves into a
top `safeAreaInset`, anchored to the top edge where a bottom inset cannot reach it.

Content already centred by `Spacer`s must not drift up with the header. The 24pt reclaimed at
the top is returned to those phases; `SignInScreen` returns it by growing the capped spacer
under its `[?]`, which is the number that already exists for exactly this purpose.

- [x] `Layout.chromeTop`, and the chrome in a top `safeAreaInset`
- [x] Heading and field still rise with the keyboard; header does not move — the header is
      anchored, confirmed with the software keyboard up. The *rise* could not be provoked: the
      fixture returns one result, and one result never fills the column enough to push anything.
      `E26-03` owns the crowded case, which is the one that matters.
- [x] Tapping the background dismisses the keyboard — on the background layer only, or it
      swallows taps on the track rows

      > **It did not, and this is the slice that found out.** The dismissal lives on the column's
      > `.background`, which covers the idle state and nothing else: with results on screen the
      > empty half of the page is inside `rows`, a `ScrollView`, and a scroll view swallows a tap
      > on its own empty area rather than passing it back. `rows` now carries a
      > `simultaneousGesture` of its own — simultaneous so a tap on a track still chooses it, and
      > drops the keyboard on the way to the confirm screen, which is what that tap wanted anyway.
      > Both halves driven by hand afterwards: tap the gap, keyboard goes; tap the row, confirm.
- [x] `SubmitScreen.closed`, `VoidedScreen` hold their optical centre
- [x] `SignInScreen`'s title block sits lower, optically centred
- [x] Verified on a 15 Pro and an SE, in the simulator, not only in goldens — iPhone 17 for the
      full pass, and a 3rd-generation SE created for the 375-point one. The SE could be launched
      and screenshotted but not driven (device access was not granted for it), so its states were
      reached by pointing the fixture at each phase rather than by tapping through.

---

### E17-05 — How to play is the legend

**Status:** done · **Deps:** — · **Reads:** `docs/07` §2, `CLAUDE.md` §2.5
**Touches:** `BlindDrop/Features/HowTo/HowToSheet.swift`, `CLAUDE.md`,
`docs/07-DESIGN-SYSTEM.md`
**Verify:** `./ios/scripts/lint.sh`; `xcodebuild test -only-testing:BlindDropSnapshotTests/HowToSnapshotTests -only-testing:BlindDropUnitTests/PaletteContrastTests`

**`CLAUDE.md` §2.5 is amended by the owner.** The page had no accent because it is true on every
phase, and either colour on it would have been decorative. The amendment says the opposite is
true of this one page: its four steps *are* the four phases, so colouring them is not decoration,
it is the legend the rest of the app reads against.

Step 1 — *Drop a song* — is the sealed state and takes `amber`. Steps 2, 3 and 4 — the reveal,
the guess, the results — are the open state and take `ultramarine`. Nothing else on the page
changes colour: the scoring card stays neutral, because `Ear` and `Readability` are unranked by
design (`docs/16`) and an accent on either starts implying a better end.

- [x] Step numerals accented; a left hairline down the numeral column so four rows read as a
      sequence
- [x] Scoring and Good-to-know cards untouched
- [x] `CLAUDE.md` §2.5 amended, naming this page as the second exception
- [x] `PaletteContrastTests` covers the numeral tiers as drawn

---

### E17-06 — The call sheet collapses

**Status:** done · **Deps:** — · **Reads:** `docs/08` §6, `docs/09` §1, `docs/12` §5
**Touches:** `BlindDrop/Features/Reveal/RevealScreen.swift`,
`BlindDrop/Features/Reveal/GuessSheet.swift`, `BlindDrop/DesignSystem/Motion/MotionTokens.swift`
**Verify:** `./ios/scripts/lint.sh`; `xcodebuild test -only-testing:BlindDropSnapshotTests/RevealSnapshotTests -only-testing:BlindDropUnitTests/RevealTests -only-testing:BlindDropUnitTests/A11yReachabilityTests`

The pool held a fixed strip of the screen whether or not anybody was using it. Two heights: a
**peek** that is a status line, and **open**, which is the workspace. Names are hidden in peek
deliberately — a pool visible while collapsed gives nobody a reason to raise it, and the
interaction becomes decorative.

| Trigger | Result |
|---|---|
| Arrive at the reveal | Peek |
| Tap a card | Open, and that card scrolled clear of the sheet |
| Drag down, or tap the heading row | Peek; the focused card is released |
| **Lock in guesses** | Peek, after the button's own state lands |
| **Change a guess** | Open, focused on the first assignable card |
| `blockedReason` | Open and not collapsible — the line explaining why *is* the content |
| `saveErrorKey` | Forced open — an error behind a collapsed sheet is an error nobody reads |

Locked, the peek row's trailing slot carries **Change a guess** instead of the count: the flight
already shows every name, so the count is spent and editing is the only move left.

Two failures to design around rather than discover:

1. **Overlay, not stack.** In today's `VStack { flight; sheet }` an animating sheet height
   resizes the flight's viewport every frame — twelve cards re-laid-out at 60fps, and the scroll
   position jumps. The sheet becomes an overlay; the flight takes a bottom `safeAreaInset` of the
   **peek** height, a constant, never the live one.
2. **`updateVisibleCards` must subtract the sheet.** It drives the unseal off viewport bounds;
   under an overlay, cards hidden behind an open sheet would unseal where nobody can see them.

`docs/12` §5 — *no gesture is the only way to do anything* — makes the tap-the-row affordance
required and the drag the addition. The grabber stops being decorative and becomes a labelled
control; `GuessSheet`'s comment calling it "not a control" is now wrong and goes.

- [x] `CallSheetDetent`, one interruptible spring in `Motion.CallSheet`
- [x] Live drag with rubber-band past open, committed on projected velocity — partially
      exercised. A non-committing drag (below threshold) is confirmed on device, and review
      caught a real bug in it in the process: `dragOffset = 0` on release was unanimated, so a
      drag that didn't cross the threshold snapped back in one frame instead of springing. Fixed
      by wrapping both `onEnded` branches in `withAnimation(Motion.CallSheet.spring)`; confirmed
      the spring-back on device afterwards. The *committing* drag — crossing the threshold on
      projected velocity — is still not directly exercised; `setDetent` is the same call the row
      tap makes, driven by hand, so the risk is narrow, but `E26-02` should still drive the
      gesture itself before that slice closes.
- [x] Overlay + constant peek inset; flight never relayouts
- [x] Focused card scrolled clear of the open sheet
- [x] `updateVisibleCards` bounds reduced by the sheet
- [x] Row tap expands and collapses; grabber labelled and actionable
- [x] Blocked and error states hold it open

---

### E17-07 — Two haptics for the reveal

**Status:** done · **Deps:** E17-06 · **Reads:** `docs/09` §2, §3, §6, `CLAUDE.md` §2.7
**Touches:** `BlindDrop/DesignSystem/Haptics.swift`,
`BlindDrop/Features/Reveal/RevealStore.swift`, `BlindDrop/Features/Round/RoundScreen.swift`,
`docs/09-MOTION-SPEC.md`
**Verify:** `xcodebuild test -only-testing:BlindDropUnitTests/RevealStoreTests -only-testing:BlindDropUnitTests/SealAnimationTests`

**`docs/09` §1's closed vocabulary is amended by the owner** — from two notes to three.
`Haptics.swift` says there is no third note and gives the reason, which stands: a tap that
buzzes because buzzing is available is how an app ends up feeling like a slot machine. The
amendment adds one note, at one moment, for one reason.

**Not on chip selection — on assignment.** Selecting a chip picks something up; nothing has
happened yet, and firing on both makes the sheet buzzy, which is the failure the rule guards.
The assignment is the commit, and both interaction directions already funnel through
`assign(_:to:)` — which is also, not coincidentally, where the app already decided this moment
was worth announcing to VoiceOver.

Locking in reuses `.stampLands`. It is the same committed beat as the seal and needs no new note.

- [x] `Haptic.nameLands` — `.impact(.light)`, intensity 0.5
- [x] Fired from `assign(_:to:)`; `.stampLands` from `lockIn()`
- [x] `RevealStore` takes a `HapticEngine`; `RevealHost` passes `env.haptics`
- [x] `docs/09` §1's table and §6's count assertions updated
- [x] Counts asserted: one assignment fires one, a lock-in fires one, a rejected assignment
      fires none

---

### E17-08 — The answers land harder

**Status:** done · **Deps:** E17-03 · **Reads:** `docs/09` §4, §5, `docs/08` §7.1
**Touches:** `BlindDrop/DesignSystem/Motion/ResolveAnimation.swift`,
`BlindDrop/DesignSystem/Motion/MotionTokens.swift`,
`BlindDrop/DesignSystem/Components/FlightCard.swift`
**Verify:** `xcodebuild test -only-testing:BlindDropUnitTests/MotionTokenTests -only-testing:BlindDropSnapshotTests/ResultsSnapshotTests`

The ask was cards arriving one at a time. They already do — `ResolveAnimation` lands each owner
120ms after the last, top to bottom. What is static is the card; what arrives is the answer
inside it, and the arrival is under-sold rather than absent.

**No second sequence.** Two staggers at different offsets read as jitter, `docs/09` §4's
skip-on-scroll rule exists because waiting is the enemy, and `ResolvedAnswer` is built on a
constraint that a card entrance would break: everything moves by opacity and offset so *"a card
is exactly as tall while its name is arriving as after it has"*. A card that slides or scales in
changes height mid-sequence and the list jumps under a scrolling thumb.

So the same timeline, spent better. The room bar is the win: it currently fades in beside the
name, and a bar that **fills** is worth more than a bar that appears.

- [x] A third event kind — the bar, 80ms after its own mark
- [x] `ProportionBar` animates its fill from zero on arrival
- [x] `Motion.Resolve.rise` 4 → 8, still geometry-neutral
- [x] Reduced motion still lands everything at once, filled, no stagger (`docs/09` §5)
- [x] The card's height is unchanged at every point in the sequence

---

### E17-09 — The group's name on every phase

**Status:** done · **Deps:** E17-01 · **Reads:** `docs/08` §2, §6, §7
**Touches:** `BlindDrop/Features/Round/RoundScreen.swift`, `docs/08-SCREEN-SPECS.md`
**Verify:** `xcodebuild test -only-testing:BlindDropUnitTests/RoundInsetTests`

`headerName(_:)` returns `nil` on `revealed` and `scored` — *"the phases that draw their own
title"* — and `docs/08` §6 and §7's drawings agree, so this shipped as specified. It is still
wrong on screen: `dateHeadline` is passed on **every** phase, so what renders is an empty
leading slot beside `[?]` and `[≡]` with *"Monday 10 August"* under it. The row is spent and
says nothing.

The screen titles and the header title are different registers. *"Tonight's drop"* says what
this screen **is**; *"The Cove"* says whose it is. They do not compete, the row already exists
and already carries the date, so the name costs no height — and with no tab bar and no
navigation title (`docs/13` §9), this header is the app's only statement of which group you are
looking at.

Done with E17-04 by one agent: both change the same header block in the same file, and
splitting them would mean two passes over `RoundHeader` for one visual result.

- [x] `headerName` returns the group's name on all four phases
- [x] Reveal and results still draw their own headlines; nothing is said twice
- [x] `docs/08` §6 and §7 drawings updated to show the header row
- [x] Checked at `accessibility5` — the name truncates before the date wraps, which is the
      priority `RoundHeader`'s three-row layout already encodes

---

### E17-10 — Close the polish pass

**Status:** done · **Deps:** — · **Parallel:** no — it is the verification of all of them

> `Deps` is empty deliberately. `E17-01`…`09` are `wip`, and this slice does not wait for them
> to be `done` — it is what *makes* them done. Their code already exists in the tree; nothing is
> in flight.
**Reads:** this file's *State of play*, `CLAUDE.md` §5, §8
**Touches:** `BlindDrop/DesignSystem/Haptics.swift`,
`BlindDrop/Features/Onboarding/CreateGroupScreen.swift`, `docs/08-SCREEN-SPECS.md`,
`ios/BlindDropTests/__Snapshots__/**`
**Verify:** `./ios/scripts/lint.sh`; the full unit + snapshot run, green; a simulator pass over
Submit, Sealed, Voided, Reveal and Results on a 15 Pro and an SE
**Proves:** AC-2, AC-11

Nine slices' worth of code exists and nothing has confirmed any of it. This is the slice that
makes E17 true rather than merely written. It adds no features.

Order matters: fix the defect, *then* look at the goldens, *then* re-record. Re-recording first
would bake the missing haptic's consequences into the expectations.

- [x] `Haptic.nameLands` warmed wherever the other two are; `bothGeneratorsAreWarmedFirst`
      passes for the right reason, not by relaxing the assertion

      > Resolved by **strengthening** it rather than by either of the two options the line
      > offered. `SealAnimation` now warms exactly the two notes it fires and its test asserts
      > exactly those — warming a `.light` generator at the top of the *seal*, for a note only
      > the reveal can play, would be a lie in the code and wasted Taptic time. The property the
      > all-cases assertion was really carrying, *no note can fire cold*, is asserted whole by a
      > new `everyNoteIsWarmedBySomebody`, which unions what the seal, the unseal and
      > `RevealStore.prepareHaptics()` warm and compares it to `Haptic.allCases`. A fourth case
      > added without a warm-up still fails, which is the only thing the original was for.
- [x] Every one of the 45 snapshot diffs opened and judged — `__Failures__/<Suite>/*.diff.png`.
      Anything that is a regression is fixed in the view, not accepted into the golden
- [x] Goldens re-recorded only after that, with `TEST_RUNNER_RECORD_SNAPSHOTS=1`
- [x] E17-04's simulator check actually performed: 15 Pro and SE, chrome anchored, heading and
      field rising with the keyboard, background tap dismissing it, track rows still tappable
- [x] E17-09's `docs/08` §6 and §7 drawings updated to show the header row
- [x] `CreateGroupScreen` given the same `Layout.chromeTop` treatment as its siblings, or E17-04's
      **Touches** corrected to say why it does not need it

      > **Touches corrected.** `CreateGroupScreen` has no chrome. `Layout.chromeTop` is *"top
      > breathing room for screen chrome inside the safe area"*, and this screen has no `[?]`, no
      > `[≡]` and no header row — it opens on its own `displayM` title, like `DisplayNameScreen`
      > beside it. There is nothing for the token to apply to, so the entry was a mistake in the
      > plan rather than work left undone.
- [x] Full run green; the diff read once more for anything accidental
- [x] E17-01…09 ticked and set `done` in both places, with this work in its own commit
