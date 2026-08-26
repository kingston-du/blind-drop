# E33 — Finish the record chip

One slice, from `docs/17-NEXT-FEATURES.md` §7. This is a **finish-and-commit** task, not a design
task — the work already exists, uncommitted, in the working tree.

---

### E33-01 — Finish, verify, and commit the in-flight record chip

**Status:** done
**Deps:** —
**Parallel:** yes
**Reads:** `docs/17-NEXT-FEATURES.md` §7, `tasks/E28-polish-and-personality.md` (amendment **A3**,
which this continues)
**Touches:** `ios/BlindDrop/Features/Settings/GroupScreen.swift`,
`ios/BlindDrop/DesignSystem/Palette.swift`, `ios/BlindDrop/DesignSystem/Components/StatFigure.swift`,
`ios/BlindDropTests/Snapshot/GroupScreenSnapshotTests.swift`,
`ios/BlindDropTests/Snapshot/GroupSnapshotTests.swift`, `ios/BlindDropTests/Unit/PaletteContrastTests.swift`
**Verify:** `-only-testing:BlindDropSnapshotTests/GroupScreenSnapshotTests -only-testing:BlindDropSnapshotTests/GroupSnapshotTests -only-testing:BlindDropUnitTests/PaletteContrastTests`;
`./ios/scripts/lint.sh`. Simulator: open the Group screen and confirm the record entry sits above
the member list and reads as a control (bordered pill, icon, chevron) rather than a plain link.
**Proves:** AC-2 gates

The uncommitted diff already in the working tree — the record entry moved above the group list and
restyled as a bordered pill (`GroupScreen.swift`), `Palette.swift`'s new `inkSubtle` and
`ultramarineWashLight` tokens, and `StatFigure.swift`'s generic `SheetMeta<Trailing>` slot — **is**
the answer to "move the record up, make it look nicer," confirmed by the owner. No new design.

- [x] Read the existing diff in full before touching anything.
- [x] Finish anything the diff leaves incomplete against this checklist.
- [x] Re-record any snapshot goldens it needs — look at each before recording, don't rubber-stamp
      (`CLAUDE.md` §5).
- [x] Commit as its own slice.

**Note.** The uncommitted diff also reached `InsightsScreen.swift` and `MemberProfileScreen.swift`
beyond this task's original `Touches` list — reviewed and kept, because they share the same
`inkSubtle`/`isAccented` accent language `Palette.swift` and `StatFigure.swift` introduce here and
were clearly authored as one pass; splitting them apart would have been artificial. Re-recording
also surfaced that `GroupSnapshotTests.twelveMembersWithATie`'s accessibility5 case now renders
past ImageIO's simulator PNG encode ceiling — the per-row readability bar added real height, and
the existing pixel cap was tuned tight enough to the old layout that it no longer left headroom.
Retuned the cap (7,000,000 → 4,500,000px); see `GroupSnapshotTests.swift`.
