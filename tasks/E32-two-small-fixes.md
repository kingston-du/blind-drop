# E32 — Two small, independent fixes

From `docs/17-NEXT-FEATURES.md` §6 and §8. Unrelated to each other; grouped here only because
each is too small to be its own epic.

---

### E32-01 — The call sheet commits instead of springing back

**Status:** blocked
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

- [ ] Reproduce the snap-back at a few specific speeds/distances before changing any constant, so
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

**Verification status (blocked — see the note at the foot of this file).** `./ios/scripts/lint.sh`
is clean, and the retuned decision was proven by compiling the exact `resolved` body plus the same
19 assertions as a macro-free standalone program (all pass). `xcodebuild test
-only-testing:BlindDropUnitTests/CallSheetDetentTests` and the simulator drag pass could not run:
the build itself fails before any test, on an `@Observable` macro-expansion failure that predates
and is independent of this change.

---

### E32-02 — The menu doesn't peek through the pop transition

**Status:** blocked
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

- [ ] Confirm the repro once.
- [x] Try the cheapest structural fix (most likely: the `Menu` shouldn't still be attached/rendering
      during the pop) and stop there.

**Fix applied (the cheap one, per the owner note).** The hamburger `Menu`'s label is pinned to an
explicit `44×44` frame instead of a *minimum* frame. `Menu` renders its label through a UIKit
platform node (the `FullLoopUITests` accessibility sweep already documents the "two coincident
accessibility nodes" this bridge produces), and a label sized by a `min` is one SwiftUI is free to
re-measure during the navigation pop; a fixed, already-measured box is one the transition can only
move, never re-lay out. Zero visual change at rest — the glyph was already centred in a 44pt
minimum box.

**Verification status (blocked — see the note at the foot of this file).** `./ios/scripts/lint.sh`
is clean. The simulator pop pass (Group / Insights / Settings → back, watching for the hamburger
flashing in from the left) could not run: the app cannot be built against the current toolchain
(`@Observable` macro expansion fails). The fix is therefore applied-but-unverified against the live
transition; it is the documented cheapest structural attempt and, per the owner note, this slice
stops there.

---

## Why these are blocked, not done

`xcodebuild test` cannot build the app in this environment: every `@Observable` macro expansion
fails with

```
external macro implementation type 'ObservationMacros.ObservableMacro' could not be found for
macro 'Observable()'; '…/Platforms/iPhoneOS.platform/Developer/usr/bin/swift-plugin-server'
produced malformed response
```

The failure is in files this slice never touched (`Core/Circles/CircleStore.swift`,
`Core/Auth/SessionStore.swift`, …), so it is environmental, not a regression from E32. It is the
known Xcode/macOS `swift-plugin-server` "malformed response" defect (Swift Forums 85558). Attempted
without success: retry; clearing the project derived-data caches; a full clean rebuild;
`-in-process-plugin-server-path`; `SWIFT_ENABLE_EXPLICIT_MODULES=NO`; killing the Xcode build
daemons. `swiftc` itself works — a macro-free standalone compile of the E32-01 logic runs and
passes — so the break is scoped to the out-of-process macro plugin server, which needs a toolchain
repair (reinstall/update Xcode, or a reboot) rather than a repo change. Both slices' code is
committed and ready to verify the moment the toolchain can build again.
