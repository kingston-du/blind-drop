# E32 — Two small, independent fixes

From `docs/17-NEXT-FEATURES.md` §6 and §8. Unrelated to each other; grouped here only because
each is too small to be its own epic.

---

### E32-01 — The call sheet commits instead of springing back

**Status:** wip
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
- [ ] Retune `CallSheetDetent.resolved`'s distance/velocity thresholds so a purposeful partial drag
      commits, while `abs(value.translation.height) < Space.sm`-style tiny movement still resolves
      as a tap (`toggleDetent()`).
- [ ] `CallSheetDetentTests` gains cases for whatever specific inputs were snapping back before the
      fix.

---

### E32-02 — The menu doesn't peek through the pop transition

**Status:** wip
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
- [ ] Try the cheapest structural fix (most likely: the `Menu` shouldn't still be attached/rendering
      during the pop) and stop there.
