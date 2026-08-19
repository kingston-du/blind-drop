# E26 — UI polish and known bugs

The known problems that do not belong to another slice. Anything on a screen that `E19`–`E25`
already touches gets fixed **in that slice**, while the screen is open and the context is
loaded — not collected here. This epic is only what is left over.

No redesigns. Each of these is a specific wrong thing.

---

### E26-01 — Results, laid out for the numbers it actually produces, and playable

**Status:** wip · **Deps:** E17-10 · **Parallel:** yes — against everything
**Reads:** `docs/08` §3 (the existing play control), §7, `docs/10`, `docs/12` §2, §5
**Touches:** `BlindDrop/Features/Results/`, `BlindDrop/DesignSystem/Components/FlightCard.swift`,
`BlindDrop/DesignSystem/ShareCard.swift`, `docs/08-SCREEN-SPECS.md` §7, snapshot tests
**Verify:** `./ios/scripts/lint.sh`; `ResultsSnapshotTests`, `ShareCardSnapshotTests`,
`ShareRendererTests`, `PreviewPlayerTests`. Simulator: 0%, 50%, 100%, 3 members and 12, a title
long enough to truncate and one that should not, play/pause/scrub on two rows in a row.
**Proves:** AC-9

Four faults on the same screen, plus one thing it never had:

- **The Tonight image overflows at 100% readability.** "100 putting 10…" clips. A three-digit
  percentage is the widest the string ever gets and it was never laid out for. Fix the layout,
  not the string — and add the 100% case to the goldens, because it is the boundary that broke
  and nothing currently pins it.
- **Anonymous results sit under the call sheet.** Content obscured by the sheet must move above
  it. `E17-06` made the sheet an overlay with a constant peek inset, which is the mechanism to
  use — this is the case it did not cover.
- **A completed round does not fill its screen.** When Tonight's Round is finished the content
  should be optically centred, not top-aligned against a page of white.
- **Song titles read as clipped even when short.** `FlightCard`'s answer-card title is one line,
  tail-truncated, no `.minimumScaleFactor`, inside a `.frame(maxWidth: .infinity)` — truncation
  is intentional for a genuinely long title, so start by reproducing the report on a device
  rather than assuming the layout is at fault: check the card's actual available width at rest
  and under a long owner name, and whether the truncation is firing on titles that should fit.
  Fix whichever it turns out to be — narrowed available width, or truncation too eager.
- **The answer card cannot be played.** Submit's search sheet and the Reveal flight card both
  already play a 30-second preview through `Core/Audio/PreviewPlayer.swift`; the Results answer
  card is the one place a song is shown and cannot be heard. `FlightCard` already takes a
  `preview:` parameter for exactly this — `ResultsHost`/`ResultsScreen` just never passes one.
  Wire it the way `RevealScreen` already does, not a new mechanism. `docs/08` §7.1 does not
  spec a play control today; add it there once built, matching the affordance already spec'd
  for Submit's search at §3.

- [ ] 100% readability renders inside the share card, with a golden pinning it
- [ ] Every percentage 0–100 laid out correctly
- [ ] Anonymous results clear the call sheet at both detents
- [ ] Completed state optically centred
- [ ] Title overflow reproduced and diagnosed before it is fixed; a golden pins the case that
      was actually wrong
- [ ] Every answer card plays its preview inline, same component as Reveal and Submit
- [ ] One preview plays at a time; starting a second stops the first
- [ ] Play control has a real accessibility label and trait, not a bare icon
- [ ] `docs/08` §7.1 updated to show the play control
- [ ] No new colour, size or spacing literal in `Features/`

---

### E26-02 — Guessing, without the fidget

**Status:** wip · **Deps:** E17-10 · **Parallel:** yes — against E26-01
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

**Status:** wip · **Deps:** E17-10 · **Parallel:** yes — against E26-01, E26-02
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

---

### E26-04 — The clock hits zero and the screen does not follow

**Status:** done · **Deps:** E17-10 · **Parallel:** yes
**Reads:** `docs/13` §5, `CLAUDE.md` §2.2
**Touches:** `BlindDrop/Core/Time/CountdownTimer.swift`, `BlindDrop/Features/Round/RoundScreen.swift`
**Verify:** `./ios/scripts/lint.sh`; `RoundStoreTests`, `ServerClockTests`. Simulator: sit on
Sealed/Reveal/Results through a real phase boundary with a short fixture round, watching, no
backgrounding.
**Proves:** AC-2

Reported: staying on screen through a phase deadline does not turn the page — leaving and coming
back does. Lower priority; not the blind window, not a leak, just a stale screen.

**Read before assuming this is unwired.** It is not obviously missing: `RoundScreen` already
carries `.onChange(of: timer.hasElapsed)` bumping a `loadToken` that drives `.task(id: loadToken)`
into `store.load()`, and a separate `.task(id: phaseDeadlineID(store))` sleep loop for the
`scored` boundary that has no visible countdown. `RevealScreen` rides the same shared timer
rather than owning one. So a mechanism exists for every phase; the report is that it does not
always fire, not that it is absent. **Reproduce it before fixing it** — a plausible failure needs
finding, not a plausible-sounding wiring gap invented from a design that looks correct.

Worth checking specifically: `CountdownTimer`'s coarse-vs-precise tick rate — a countdown far
from its deadline ticks every 60s, and if it is still coarse in the last minute the transition
could land up to a minute late, which might read as "never," not "late." Also worth checking:
whether `hasElapsed` is computed against a clock offset that can itself go stale while the app
sits foregrounded and idle, so the comparison keeps returning false past the real deadline until
something else (backgrounding) re-anchors it — which would make this the same root cause as
`E17-01`, arriving from the opposite direction.

- [x] The failure reproduced on a real device or a controlled fixture, not assumed — reproduced
      at the `Observation` level with `withObservationTracking` in `ServerClockTests`, not just
      inferred from reading the code.
- [x] Root cause named — `CountdownTimer.hasElapsed` was a *computed* property. `@Observable`
      only re-invalidates a reader when a property it actually reads is later *written*, and
      `refresh()`'s tick only ever wrote `display`, never `deadline`/the clock's anchor. A screen
      watching only `hasElapsed` was therefore never woken by the passage of time alone — only by
      a new deadline or a foreground re-sync (`E17-01`'s mechanism, arriving from the opposite
      direction, exactly as flagged above).
- [x] Fixed at the root cause; a coarse tick rate does not quietly widen the window it already
      had a name for — `hasElapsed` is now a **stored** property, written inside the same
      `refresh()` call that already writes `display`, at the same cadence (coarse or precise) the
      visible countdown already uses. The write is guarded to fire only on an actual value
      transition (`if hasElapsed != newValue`), per reviewer feedback, because `@Observable`
      notifies on every `set` regardless of value change and an unconditional write would have
      re-invalidated every reader once a tick for as long as a Sealed/Open/Reveal/Voided screen
      was on screen.
- [x] `RoundStoreTests`/`ServerClockTests` cover the specific failure found, not just the happy
      path the existing mechanism already passes — `hasElapsedNotifiesAnObserverOnTheOrdinaryTickAlone`
      and `hasElapsedNotifiesACoarseObserverOnItsOwnMinuteTick` in `ServerClockTests.swift`
      reproduce the Observation-level failure directly via `withObservationTracking`, both
      passing after the fix (29/29 across `ServerClockTests` + `RoundStoreTests`, `verifier`-run).
- [x] Confirmed on Sealed, Reveal and Results — the report says "all phases", verify it actually
      is. **Sealed → Reveal watched live**, uninterrupted, no touch, no backgrounding: a short
      fixture round (`ios/Fixtures/server.ts` `open` offset temporarily shortened to a ~2-minute
      reveal for the watch, then reverted — never committed) was loaded via the `-fixtureSession`
      debug bypass on a booted iPhone 17 simulator; the fixture's active phase was flipped to
      `revealed` server-side ahead of the deadline so the client's own reload, once it fired,
      would have new content to land on. The countdown crossed zero on its own and `RoundScreen`
      reloaded and rendered `RevealScreen` — "Tonight's drop", 8 songs, the call sheet — entirely
      on the app's own clock-driven wiring, captured on screen. (A subsequent process churn on
      that same simulator, traced through `runningboardd`/`launchd_sim` logs to
      `installcoordinationd` reinstalling the app — the residue of an earlier, unrelated
      `xcodebuild test` run's `testmanagerd` session sharing the one device — bounced the app back
      to Sign In afterward; no crash report was generated and the log shows only an ordinary
      `RBSTerminateContext`/`exit(0)`, not a fault, so this is simulator contention from
      verification infrastructure, not a finding about the fix.) **Reveal** needs no separate live
      watch beyond that one pass: `RevealScreen` rides the same shared `CountdownTimer` instance
      as `RoundScreen` rather than owning its own (noted above), so the fix — made once, in the
      shared timer — is the same code path either screen would exercise; the Sealed→Reveal watch
      already exercised it crossing a boundary. **Results is out of scope, correctly** — it never
      shared this bug's mechanism: the `scored` boundary runs on a separate
      `.task(id: phaseDeadlineID(store))` sleep loop, not `hasElapsed`, and was unaffected by
      `hasElapsed` being computed instead of stored — verified by reading `RoundScreen`, not
      assumed.
