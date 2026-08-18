# E26 — UI polish and known bugs

The known problems that do not belong to another slice. Anything on a screen that `E19`–`E25`
already touches gets fixed **in that slice**, while the screen is open and the context is
loaded — not collected here. This epic is only what is left over.

No redesigns. Each of these is a specific wrong thing.

---

### E26-01 — Results, laid out for the numbers it actually produces

**Status:** todo · **Deps:** E17-10 · **Parallel:** yes — against everything
**Reads:** `docs/08` §7, `docs/10`, `docs/12` §5
**Touches:** `BlindDrop/Features/Results/`, `BlindDrop/DesignSystem/ShareCard.swift`,
snapshot tests
**Verify:** `./ios/scripts/lint.sh`; `ResultsSnapshotTests`, `ShareCardSnapshotTests`,
`ShareRendererTests`. Simulator: 0%, 50%, 100%, 3 members and 12, SE and `accessibility5`.
**Proves:** AC-9

Three faults on the same screen:

- **The Tonight image overflows at 100% readability.** "100 putting 10…" clips. A three-digit
  percentage is the widest the string ever gets and it was never laid out for. Fix the layout,
  not the string — and add the 100% case to the goldens, because it is the boundary that broke
  and nothing currently pins it.
- **Anonymous results sit under the call sheet.** Content obscured by the sheet must move above
  it. `E17-06` made the sheet an overlay with a constant peek inset, which is the mechanism to
  use — this is the case it did not cover.
- **A completed round does not fill its screen.** When Tonight's Round is finished the content
  should be optically centred, not top-aligned against a page of white.

- [ ] 100% readability renders inside the share card, with a golden pinning it
- [ ] Every percentage 0–100 laid out on SE at `accessibility5`
- [ ] Anonymous results clear the call sheet at both detents
- [ ] Completed state optically centred
- [ ] No new colour, size or spacing literal in `Features/`

---

### E26-02 — Guessing, without the fidget

**Status:** todo · **Deps:** E17-10 · **Parallel:** yes — against E26-01
**Reads:** `docs/08` §6, `docs/12` §2, §5
**Touches:** `BlindDrop/Features/Reveal/GuessSheet.swift`, snapshot tests
**Verify:** `./ios/scripts/lint.sh`; `RevealSnapshotTests`, `A11yReachabilityTests`. Simulator:
3, 7 and 12 members, at `large` and `accessibility5`, on an SE.

Name pills are as wide as the names in them, so the sheet is a ragged field of different-sized
targets and picking one is fiddlier than it should be.

Equal widths are the obvious answer and not automatically the right one: twelve equal pills sized
to *"Christopher"* waste the row, and at `accessibility5` a fixed width either truncates a name
or overflows. So the question is a consistent, comfortable target — a minimum width and even
tracking may serve better than strict equality. Decide it against the real member counts on a
real screen, and keep the 44pt minimum whatever the answer.

> **Mostly landed in `E17-10`.** The owner asked for the pill work while that slice had
> `GuessSheet` open, and splitting it would have meant two passes over one file for one visual
> result. What was decided: a **scaled minimum width** (`Layout.nameChipMinimumWidth`, 72pt at
> `.large`), not strict equality — every name up to about six characters comes out identical, and
> longer ones grow past the floor rather than truncate. It is applied in the row only; the
> accessibility-size grid's two flexible columns already equalise width, and a floor there scaled
> to over 200 points and made the columns overlap. Four whole pills plus the edge of a fifth on an
> SE, which is what keeps the row from looking finished when it is not.
>
> Three other things went with it, all on the same screen and all defects rather than polish: the
> collapsed sheet no longer shows the top of the name row, the header row is one tap target
> instead of two words, and the flight can now be scrolled clear of an open sheet — the last card
> of a round was unreachable. See `E17-10`.

- [x] Pills read as one set of targets rather than a ragged row
- [x] 44pt minimum held at every size
- [x] Long names still legible; nothing truncates that a person needs to read
- [ ] 3, 7 and 12 members on an SE at `accessibility5` — 7 driven on a real SE, 11 pinned in the
      `accessibility5` goldens. A 3-member pool is not covered by either and is the case where a
      minimum width is most likely to look odd: three short pills in a row that could hold five.
- [x] Goldens updated after looking at them
- [ ] The drag `E17-10` could only partly exercise: a non-committing release now springs back
      correctly (that was a real bug review caught and fixed), but the *committing* drag —
      crossing the threshold on projected velocity, mid-gesture rubber-band past open — is still
      not directly driven on device

---

### E26-03 — Searching for a song with a keyboard in the way

**Status:** todo · **Deps:** E17-10 · **Parallel:** yes — against E26-01, E26-02
**Reads:** `docs/08` §3, `docs/12` §5
**Touches:** `BlindDrop/Features/Submit/SongSearch.swift`, snapshot tests
**Verify:** `./ios/scripts/lint.sh`; `SubmitSnapshotTests`. Simulator: type, scroll results with
the keyboard up, dismiss, pick a track — SE and 15 Pro.

The live results appear under the keyboard. It is usable and it is not good: the thing the user
is looking for is behind the thing they are typing with.

`E17-04` already did the hard part by layering the chrome into a top `safeAreaInset` while
content keeps keyboard avoidance, and `SongSearch` documents the earlier fight at length — read
that comment before changing anything, it explains a failure that will otherwise be rediscovered.

Options worth weighing on screen rather than in the abstract: give the results room by
compressing what sits above them, let the list scroll under a dismissible keyboard with the first
results guaranteed visible, or dismiss on scroll. The first result being visible while typing is
the outcome; the mechanism is whichever achieves it without reopening the layout fight.

- [ ] The first results are visible while typing, on an SE
- [ ] Scrolling the results behaves predictably with the keyboard up
- [ ] Dismissal remains discoverable and the background tap keeps working
- [ ] Track rows still tappable — the regression `E17-04` warned about
- [ ] The heading and field still rise with the keyboard; the chrome still does not move
