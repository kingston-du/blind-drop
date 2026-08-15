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

### E17-01 — The phase flash on foreground

**Status:** todo · **Deps:** — · **Reads:** `docs/13` §5, `CLAUDE.md` §2.2
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

- [ ] `RoundContext.OpenState { unknown, beforeOpen, open }` and `openState(now:)`
- [ ] `deadline(now:)` returns `nil` rather than a guess when the clock has no anchor
- [ ] `RoundScreen` holds the last non-`.unknown` value in `@State` and renders from it
- [ ] `RoundStoreTests` — every time-dependent branch has an *unknown* answer, and a context
      can never exist with an unanchored clock (every response anchors before `state.apply`)

---

### E17-02 — One share variant

**Status:** todo · **Deps:** — · **Reads:** `docs/10` §1, §4, `CLAUDE.md` §6
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

- [ ] `ShareSheet` renders one `.squareTall` preview, caption, and **Share tonight**
- [ ] Preview widened; `.presentationDetents` re-checked on an SE
- [ ] `results.share.square` / `results.share.story` retired for `results.share.caption`
- [ ] `Variant.pickerLabel` deleted
- [ ] `docs/10` §1 and §4 no longer claim the sheet offers both

---

### E17-03 — The answer card's links become an overflow menu

**Status:** todo · **Deps:** — · **Reads:** `docs/08` §7.1, `docs/12` §2
**Touches:** `BlindDrop/DesignSystem/Components/FlightCard.swift`,
`BlindDrop/DesignSystem/Components/TrackLinks.swift`
**Verify:** `./ios/scripts/lint.sh`; `xcodebuild test -only-testing:BlindDropSnapshotTests/ResultsSnapshotTests -only-testing:BlindDropUnitTests/A11yReachabilityTests`

Two 44pt link rows under every answer card cost ~90pt each in a list of up to twelve. The Record
already solved this with `TrackUtilityMenu`; the answer card takes the same ellipsis, top-right.

`CardCornerLinks` stays — `SealedScreen` still draws it in the sealed cover's corner, which is
genuinely dead space and the case the component was written for.

- [ ] Links-only overflow menu, factored from `TrackUtilityMenu`
- [ ] `answerCard`'s existing centre-aligned row wrapped in a top-aligned `HStack` with the
      menu — no overlay, so it cannot overlap at accessibility sizes
- [ ] `cornerLinks` removed from `answerCard`
- [ ] Menu `accessibilityHidden`; `body`'s existing `if isAnswer` actions remain the one path

---

### E17-04 — The chrome sits where a header sits

**Status:** todo · **Deps:** E17-01 · **Reads:** `docs/07` §4, `docs/12` §5
**Touches:** `BlindDrop/DesignSystem/Space.swift`, `BlindDrop/Features/Round/RoundScreen.swift`,
`BlindDrop/Features/Submit/SongSearch.swift`, `BlindDrop/Features/Submit/SubmitScreen.swift`,
`BlindDrop/Features/Submit/VoidedScreen.swift`,
`BlindDrop/Features/Onboarding/SignInScreen.swift`,
`BlindDrop/Features/Onboarding/CreateGroupScreen.swift`
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

- [ ] `Layout.chromeTop`, and the chrome in a top `safeAreaInset`
- [ ] Heading and field still rise with the keyboard; header does not move
- [ ] Tapping the background dismisses the keyboard — on the background layer only, or it
      swallows taps on the track rows
- [ ] `SubmitScreen.closed`, `VoidedScreen` hold their optical centre
- [ ] `SignInScreen`'s title block sits lower, optically centred
- [ ] Verified on a 15 Pro and an SE, in the simulator, not only in goldens

---

### E17-05 — How to play is the legend

**Status:** todo · **Deps:** — · **Reads:** `docs/07` §2, `CLAUDE.md` §2.5
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

- [ ] Step numerals accented; a left hairline down the numeral column so four rows read as a
      sequence
- [ ] Scoring and Good-to-know cards untouched
- [ ] `CLAUDE.md` §2.5 amended, naming this page as the second exception
- [ ] `PaletteContrastTests` covers the numeral tiers as drawn

---

### E17-06 — The call sheet collapses

**Status:** todo · **Deps:** — · **Reads:** `docs/08` §6, `docs/09` §1, `docs/12` §5
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

- [ ] `CallSheetDetent`, one interruptible spring in `Motion.CallSheet`
- [ ] Live drag with rubber-band past open, committed on projected velocity
- [ ] Overlay + constant peek inset; flight never relayouts
- [ ] Focused card scrolled clear of the open sheet
- [ ] `updateVisibleCards` bounds reduced by the sheet
- [ ] Row tap expands and collapses; grabber labelled and actionable
- [ ] Blocked and error states hold it open

---

### E17-07 — Two haptics for the reveal

**Status:** todo · **Deps:** E17-06 · **Reads:** `docs/09` §2, §3, §6, `CLAUDE.md` §2.7
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

- [ ] `Haptic.nameLands` — `.impact(.light)`, intensity 0.5
- [ ] Fired from `assign(_:to:)`; `.stampLands` from `lockIn()`
- [ ] `RevealStore` takes a `HapticEngine`; `RevealHost` passes `env.haptics`
- [ ] `docs/09` §1's table and §6's count assertions updated
- [ ] Counts asserted: one assignment fires one, a lock-in fires one, a rejected assignment
      fires none

---

### E17-08 — The answers land harder

**Status:** todo · **Deps:** E17-03 · **Reads:** `docs/09` §4, §5, `docs/08` §7.1
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

- [ ] A third event kind — the bar, 80ms after its own mark
- [ ] `ProportionBar` animates its fill from zero on arrival
- [ ] `Motion.Resolve.rise` 4 → 8, still geometry-neutral
- [ ] Reduced motion still lands everything at once, filled, no stagger (`docs/09` §5)
- [ ] The card's height is unchanged at every point in the sequence

---

### E17-09 — The group's name on every phase

**Status:** todo · **Deps:** E17-01 · **Reads:** `docs/08` §2, §6, §7
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

- [ ] `headerName` returns the group's name on all four phases
- [ ] Reveal and results still draw their own headlines; nothing is said twice
- [ ] `docs/08` §6 and §7 drawings updated to show the header row
- [ ] Checked at `accessibility5` — the name truncates before the date wraps, which is the
      priority `RoundHeader`'s three-row layout already encodes
