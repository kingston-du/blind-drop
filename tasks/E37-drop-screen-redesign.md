# E37 — The drop screen, cleared

One slice, from an owner request. Three changes to the one screen everybody opens first, landed
together because they interact: the header stopped costing a third row, the paste-a-link
fallback came out, and the room it freed went to the cue.

---

### E37-01 — Header reflow, cue card, paste-fallback removal

**Status:** done
**Deps:** —
**Parallel:** yes
**Reads:** `docs/08` §2, §3.1, `docs/11` (search, cues), `docs/18` §2
**Touches:** `Features/Submit/{SubmitScreen,SongSearch,SearchSheet,SubmitStore}.swift`,
`Features/Round/RoundScreen.swift` (`RoundHeader`, the shared `CueBanner` withhold),
`DesignSystem/Components/{CueBanner,CountdownView}.swift` (new `CueCard`; the countdown
badge's `.fixedSize()` overflow at `accessibility5`), `Localizable.strings`, `docs/06` §7,
`docs/08` §2/§3.1, `docs/11`, `docs/18` §2
**Verify:** `./ios/scripts/lint.sh`; `-only-testing:BlindDropUnitTests/SubmitStoreTests
-only-testing:BlindDropSnapshotTests/SubmitSnapshotTests
-only-testing:BlindDropSnapshotTests/CueSnapshotTests`. Simulator: the drop screen cued and
uncued, before and while searching, at `accessibility5` on iPhone 17.
**Proves:** —

**The header drops from three rows to two.** The badge used to force a row of its own —
*"Seals in 04:12:33"* is wide enough that a name sharing its row absorbed the whole truncation
cost, and giving it a full row of its own cost a third row of chrome above a screen whose
keyboard is already up. Now the date and the badge share one row, trailing edge to trailing
edge, and only stack when `ViewThatFits` measures that they do not fit — the same reflow
`CueBanner` and `FlightCard` already make, so a long date in a wider locale gets the same
protection nobody had to predict.

**The paste-a-link fallback is gone**, from both `SongSearch` hosts (`SubmitScreen` and
`SearchSheet`). It was a second full-width field standing permanently under the first one on a
screen whose whole job is one field — read as two equal choices rather than as one choice and an
escape hatch. `SubmitStore.pasted`/`resolve()` and `POST /tracks/resolve` are kept and still
tested; nothing presents them. This is a real, named cost, not a free simplification — an
upstream search outage now has no fallback at all (`search.error` says so plainly), and an
obscure or misspelled title that a link used to get through now either gets found or gets
dropped as something else. The obscure-title cost is the one worth revisiting first if this is
reopened, most likely as something `search.empty` surfaces rather than furniture under every
successful search.

**The room both changes freed went to the cue.** On the one phase that has something to brief —
`open`, nothing dropped yet — the drop screen now draws its own `CueCard` between the subhead and
the field, and `RoundScreen` withholds the shared `CueBanner` for that phase so the fact is not
said twice. `CueCard`'s micro-label is `amberText`, a real, narrow exception to `docs/18` §2's
"neutral ink on every surface" — argued and recorded there, not silently taken. Every other
phase, Sealed included, keeps the neutral banner unchanged.

Two more corrections landed in the same pass because they were found while touching this screen:
`CountdownView`'s badge used a bare `.fixedSize()`, which pinned both axes and let *"SEALS IN 4
HOURS"* in tracked mono caps at `accessibility5` run off both edges of the screen; it now caps
only the vertical axis. And `InviteCode.swift`'s doc comment illustrating the URL-paste-mangling
case claimed a 12-character result where `.prefix(6)` actually yields six — corrected in passing
while that file was open for the `E34-01` domain swap, not part of this slice's own scope.

- [x] `RoundHeader`: date and badge share one row, `ViewThatFits`-measured, stacking only when
      they do not fit
- [x] Paste-a-link removed from `SongSearch` (both hosts); `search.paste`/`search.paste.placeholder`
      retired from the copy deck; `search.error` rewritten with no fallback to point at
- [x] `CueCard` on the drop screen's `open`/nothing-dropped state and its dark-hours state;
      `RoundScreen` withholds `CueBanner` for exactly that phase
- [x] `docs/18` §2 carries the owner amendment for `CueCard`'s accent, scoped to that one
      rendering and that one phase
- [x] `CountdownView` badge wraps instead of overflowing at `accessibility5`
- [x] Snapshot goldens re-recorded for `Submit`, `Cue`, and the `Reveal`/`Group` header suites
      affected by the two-row `RoundHeader`; reviewed, not just re-recorded blind

> **Verified (2026-08-31, closed out during a repo cleanup pass).** `./ios/scripts/lint.sh`
> clean. `-only-testing:BlindDropUnitTests/SubmitStoreTests
> -only-testing:BlindDropSnapshotTests/SubmitSnapshotTests
> -only-testing:BlindDropSnapshotTests/CueSnapshotTests
> -only-testing:BlindDropSnapshotTests/RevealSnapshotTests
> -only-testing:BlindDropSnapshotTests/GroupSnapshotTests` — see the commit that closes this
> slice for the exact counts. This work was found complete but uncommitted in the working tree,
> with its own doc amendments already written (`docs/06`, `docs/08`, `docs/11`, `docs/18`) and
> its own re-recorded goldens already sitting alongside the code; this epic file and board row
> did not exist yet, and two source comments cited a `E36-02` that was never created (`E36` is
> the unrelated share-card epic). Written up and closed here rather than left as an orphaned
> diff — the two comments now read `E37-01`. No code changed from what was found; this slice's
> job was verification and paperwork, not authorship.
> **Simulator pass not performed** in this environment — no interactive session was available;
> the re-recorded goldens are the actual rendered pixels reviewed in place of it.
