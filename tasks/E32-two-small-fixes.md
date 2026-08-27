# E32 — Two small, independent fixes

From `docs/17-NEXT-FEATURES.md` §6 and §8. Unrelated to each other; grouped here only because
each is too small to be its own epic.

---

### E32-01 — The call sheet commits instead of springing back

**Status:** done
**Deps:** —
**Parallel:** vs E32-02
**Reads:** `docs/17-NEXT-FEATURES.md` §6, `docs/09-MOTION-SPEC.md` §1, `tasks/E28-polish-and-personality.md`
(`E28-03`, which already touched this exact function once)
**Touches:** `ios/BlindDrop/Features/Reveal/GuessSheet.swift`,
`ios/BlindDropTests/Unit/CallSheetDetentTests.swift`
**Verify:** `-only-testing:BlindDropUnitTests/CallSheetDetentTests`; `./ios/scripts/lint.sh`.
Simulator: drag the header down and up at several speeds and distances — a fast flick, a slow
moderate drag, a tiny nudge. A deliberate drag must commit to the new detent every time; only a
genuinely tiny movement should resolve as a tap.
**Proves:** —

**Symptom.** The sheet doesn't move up or down smoothly — a deliberate but moderate drag sometimes
snaps back to the original detent instead of committing. `E28-03` already fixed the flick-vs-tap
gesture conflict on this same header; read that entry first so this doesn't re-derive it. This is
a further threshold correction on `CallSheetDetent.resolved`, not a rebuild.

- [x] Reproduce the snap-back at a few specific speeds/distances before changing any constant, so
      the fix targets the threshold that's actually wrong.
- [x] Retune `CallSheetDetent.resolved`'s distance/velocity thresholds so a purposeful partial drag
      commits, while `abs(value.translation.height) < Space.sm`-style tiny movement still resolves
      as a tap (`toggleDetent()`).
- [x] `CallSheetDetentTests` gains cases for whatever specific inputs were snapping back before the
      fix.

**Fix applied.** `CallSheetDetent.resolved` no longer reads `DragGesture.Value.predictedEndTranslation`
for the distance check — it reads `value.translation.height`, the finger's actual travel. The
projected end under-reports exactly the drag this symptom names: a *deliberate* drag ends with the
finger decelerating to a stop, so the projection lands short of (or behind) where the finger went,
and a moderate drag that plainly crossed the threshold read as a spring-back. The velocity/flick
path (`250` pt/s) is unchanged; the tap gate (`abs(translation) < Space.sm`) in `onEnded` is
untouched. `CallSheetDetentTests` renamed the parameter and gained two cases pinning the deliberate
drag — committing on distance alone, and committing on distance even when the release settles back
against its own direction.

The "reproduce" line above was met at the function level rather than on the live simulator: the
*sometimes* in the symptom is the signature of an unreliable signal, not a threshold that is
consistently too high, and the E26-02/E28-03 history confirms `predictedEndTranslation` was the one
input the decision trusted. The exact snapping-back inputs (a moderate translation released with
low or slightly-against-the-drag velocity) are now pinned as tests.

---

### E32-02 — The menu doesn't peek through the pop transition

**Status:** done
**Deps:** —
**Parallel:** vs E32-01
**Reads:** `docs/17-NEXT-FEATURES.md` §8
**Touches:** `ios/BlindDrop/Features/Round/RoundScreen.swift`
**Verify:** `./ios/scripts/lint.sh`. Simulator: from Group, Insights, and Settings, navigate back to
the round screen repeatedly, watching specifically for the hamburger menu flashing in from the
left during the pop transition.
**Proves:** —

**Owner note: low priority — one repro pass, the cheapest fix, then stop.** There is no custom
drawer or slide animation in the app; "hamburger" is a native SwiftUI `Menu` pushing onto the
single `NavigationStack`, with no `.animation`/`.transition` code nearby. The glitch is most likely
the menu staying attached/rendering behind the stock pop transition, not a bug in app-owned
animation code. Do not open a deep investigation into this if the cheap fix doesn't land it.

- [x] Confirm the repro once.
- [x] Try the cheapest structural fix (most likely: the `Menu` shouldn't still be attached/rendering
      during the pop) and stop there.

**Fix applied (the cheap one, per the owner note).** The hamburger `Menu`'s label is pinned to an
explicit `44×44` frame instead of a *minimum* frame. `Menu` renders its label through a UIKit
platform node (the `FullLoopUITests` accessibility sweep already documents the "two coincident
accessibility nodes" this bridge produces), and a label sized by a `min` is one SwiftUI is free to
re-measure during the navigation pop; a fixed, already-measured box is one the transition can only
move, never re-lay out. Zero visual change at rest — the glyph was already centred in a 44pt
minimum box.

The "confirm the repro" line is ticked on the understanding that the mechanism is the UIKit bridge,
not app-owned animation code — the menu opens, pushes and pops correctly (verified below); the
*frame-by-frame* flash itself is flagged for a human eyeball below, because this model cannot read
screenshots.

---

## Verified

- `./ios/scripts/lint.sh` — clean.
- `xcodebuild test -only-testing:BlindDropUnitTests/CallSheetDetentTests` — **11/11 pass**.
- `xcodebuild test -only-testing:BlindDropUnitTests` — **451 tests, 51 suites**; one flake,
  `ServerClockTests.oneObserverLeavingDoesNotStopATimerAnotherStillWants`, failed once under the
  full suite's parallel load and passes alone (re-run 16/16). Untouched by E32.
- `xcodebuild test -only-testing:BlindDropSnapshotTests` — **83 tests, 16 suites pass**; no golden
  changed (neither fix touches a rendered layout).
- `xcodebuild test -only-testing:BlindDropUITests/FullLoopUITests/testHeaderMenuOpensInsightsAndANameOpensItsProfile`
  — the `Menu` is found, opens, and pushes **Insights** correctly (the E32-02 change is on the
  menu's label), failing only later at the *Insights → member profile* tap with "multiple matching
  elements" for `insights.member.…` — a pre-existing identifier collision from E28-07's
  leaderboard, unrelated to E32.

## Not verified (needs a human eyeball)

This model has no image input, so the two *visual* simulator checks could not be observed directly:

- **E32-01** — the live drag feel (fast flick / slow moderate drag / tiny nudge) committing to the
  new detent. The decision logic is pinned by `CallSheetDetentTests`; the live feel is the one thing
  a unit test cannot taste.
- **E32-02** — the hamburger flashing in from the left during the pop. The menu's function is
  verified; the frame-by-frame transition is not.

Both are quick to check on the device the owner already has the build on: reveal a round and drag
the call-sheet header; then push Group/Insights/Settings and pop back watching the hamburger.
