# E19 — Multi-circle: the app holds more than one

The app stops believing in "the group" and starts believing in "this circle, of several". The
switcher is the visible half; re-scoping every store and the deep-link grammar is the half that
makes it true.

> **Open question — the user-facing word.** The backlog says *circles*; the shipped app,
> `Localizable.strings`, the copy deck and the whole schema say *groups*. **Code, schema and
> routes stay `group`** — renaming them is pure churn against a working system and buys nothing.
> The user-facing word is a copy-deck decision, changeable in one commit touching only
> `docs/11` and `Localizable.strings`, and it should be made once, before `E19-02` writes new
> strings. Until the owner says otherwise these epics say "circle" in prose and the app says
> "group" on screen.

---

### E19-01 — Every screen knows which circle it is showing

**Status:** done · **Deps:** E18-01, E18-02 · **Parallel:** no — it moves shared infrastructure
**Reads:** `docs/13` §2–§5, `docs/01` ADR-011
**Touches:** `BlindDrop/Core/Networking/`, `BlindDrop/Features/*/`(stores), `BlindDrop/App/`
**Verify:** `./ios/scripts/lint.sh`; full unit + snapshot; `verify-fixture.sh` for the round and
onboarding suites. Simulator: the whole loop still works on one circle, unchanged.
**Proves:** AC-1, AC-10

No new UI. The behaviour is *nothing changes* — which is the point, and why it is its own slice.

Every store guards its reload with "already loaded" (`state.value == nil`, `!state.isLoading`),
which is correct for a single group and wrong the moment the active circle can change underneath
it. Each one needs to be scoped to a circle and able to be told the circle changed, and
`RoundContext` needs to stop bundling round and group as one inseparable value that only the
"current" endpoints could produce. `ResultsStore` is the model already — it takes its id at
construction rather than asking for "current".

The deep-link grammar is part of this. `blinddrop://round/current` has no room for a circle, and
notifications will need one in `E23`.

- [x] Group identity carried explicitly through the client — session, stores, endpoints
- [x] `Endpoint.swift` keeps owning path construction; no path built at a call site
- [x] Every store can be re-scoped and refetches rather than serving another circle's cache
- [x] Deep links can name a circle; existing links still resolve to a sensible default
- [x] Simulator: sign in, drop, seal, reveal, guess, results — one circle, no visible change

A new `CircleStore` (`Core/Circles/`) is the type this slice turns out to hinge on: it fetches
`GET /groups` once, resolves `activeGroupID` — the persisted choice if it still names a circle
the caller holds, else the server's own oldest-active-first order, which is exactly what
`/groups/current` always resolved to — and every group-scoped store (`RoundStore`, `SubmitStore`,
`GroupStore`, `RecordStore`, `ResultsStore`) calls `resolveActiveID()` fresh at the top of its own
`load()` rather than being handed an id once at construction. That is what makes "re-scope and
refetch" (`E19-02`'s job) a plain `select(_:)` + reload with no store rebuilt. `RoundContext`
itself did **not** grow a `groupID` field — `context.group.id` already was one, so nothing needed
duplicating; the epic text above predates that read of the code, noted here rather than silently
overridden. `Endpoint.swift`'s group-scoped factories all take an explicit `groupID` now (no
`current` form left to fall back to), built through one `scoped(_:_:_:)` helper. `DeepLink` grew
an optional `blinddrop://circle/<id>/…` prefix; bare links still mean "the active circle", and
acting on the id (rather than just parsing it) is `E19-03`'s.

Two real bugs came out of review, both fixed before closing: `CircleStore` had no path back to
`SessionStore.noteServerSaid(_:)`, so a caller removed from their only circle — a case
`/rounds/current`'s `NO_GROUP` 409 used to route straight to onboarding — would instead see a
generic "unreadable" error forever, because `GET /groups` answers a zero-circle caller with a
**200** and `{"circles": []}` (docs/04 §3: "a valid answer, not an error"), which never reaches
`noteServerSaid` on its own. Fixed by having `CircleStore.load()` call
`session.noteServerSaid(.noGroup)` explicitly when the fetched list is empty, wired through a new
reciprocal `CircleStore.attach(_ session:)` alongside the existing `SessionStore.attach(_
circles:)`. The second: `CircleStore` itself had no tests of its own — every other test only
exercised it as incidental plumbing behind a single-circle fixture. Added
`CircleStoreTests.swift` (6 tests): the saved-choice-still-valid path, the saved-choice-gone
fallback to server order, the empty-list-tells-the-session path above, `reset()` directly and via
`SessionStore.endSession()`, and that three concurrent `resolveActiveID()` calls share one
request.

The fixture server (`ios/Fixtures/server.ts`) grew a `:group_id`-scoped sibling for every route
the client now calls, keyed off `PRIMARY_GROUP_ID` (`payloads/group_current.json`'s own id, so
every existing fixture-backed test's payloads describe exactly the circle a store now resolves)
and `SECONDARY_GROUP_ID` (`GET /groups`'s static second row, "Late Night Radio" — a real circle a
`:group_id` route can now be asked for, for `E19-02` to build the switcher against). The
`current`-shaped routes are left in place rather than removed — nothing in the client calls them
any more after this slice, and a fixture shedding compatibility the day the app does was never
required.

Verified: `./ios/scripts/lint.sh` clean; unit 405/405 (including new `CircleStoreTests`);
snapshot 63/63; `verify-fixture.sh` for `FixtureRoundTests` (6/6) and `FixtureOnboardingTests`
(4/4). Simulator: built and ran the whole loop against the fixture server on iPhone 17 —
sign-in, the sealed/open/drop screens, search, seal, the revealed guess sheet with its
pre-filled sheet, and the scored results with standings — every phase screenshotted and matching
what shipped before this slice, which is the entire claim of a "no new UI" task.

---

### E19-02 — The switcher

**Status:** done · **Deps:** E19-01 · **Parallel:** no
**Reads:** `docs/08` §2, §11, `docs/11`, `docs/12` §2, §5
**Touches:** `BlindDrop/Features/Round/RoundScreen.swift`, a new switcher view,
`BlindDrop/Resources/Localizable.strings`, `docs/11-COPY-DECK.md`, snapshot tests
**Verify:** `./ios/scripts/lint.sh`; unit + snapshot incl. new goldens. Simulator: switch
between three circles in every phase, on a 15 Pro and an SE, at `accessibility5`.

The circle's name in the header — already there since E17-09 — becomes the control. Tapping it
opens a bottom sheet; picking a circle switches the whole app to it.

**A row is a name and a state, and nothing else.** `Drop a song` · `Sealed` · `Guess` ·
`Answers`. No artwork, no member count, no progress bar, no activity, no submission count —
partly because they are clutter, and partly because half of them would be `CLAUDE.md` §2.1
violations wearing a friendly face.

Circles needing the user's attention sort first. There is no "Action needed" heading — the order
*is* the signal, and a section header would turn a quiet nudge into a chore list. When another
circle wants attention, something small sits beside the current circle's name in the header;
small enough that a person who does not care can ignore it forever.

- [x] Tapping the header name opens the sheet; it is a labelled control, reachable without the
      gesture (`docs/12` §5)
- [x] Rows: name, the caller's state, an optional needs-action mark. Nothing else
- [x] Needs-action circles first, no visible section
- [x] A subtle mark beside the header name when another circle wants attention
- [x] Switching re-scopes every store and lands on the right phase for that circle
- [x] Sheet height suits one circle as well as three; SE and `accessibility5` checked
- [x] Every string in `docs/11` first

The user-facing word stays **group**, per this epic's own open question — `switcher.title` is
"Your groups", not "Your circles".

The header's name gained a chevron and — always visible, whether or not the caller holds a
second circle. Kept unconditional on purpose: `E20` hangs "Start a group" off this same sheet,
and a control that appears and disappears as circles come and go is a worse habit to teach than
one tap the one-circle case does not strictly need (owner call, recorded rather than silently
decided). `CircleSwitcher` (`Core/Circles/`) is the ordering — needs-action first, stable
partition, plus `otherNeedsAction` for the header's own mark — as a pure value the same shape
`RoundContext` already is, so both are unit-tested without a view.

**The row is a name and a state, nothing else — literally.** Review caught the draft plan
drifting from that: an active-row border (`rowSurface(border: .ink)`) had crept in as "the
current circle, visually marked," which the checklist's own "nothing else" rules out. Removed;
`.isSelected` on the row's accessibility trait says the same thing to VoiceOver without adding a
sighted-only mark the copy deck doesn't call for.

Switching calls `RoundStore.invalidate()` — a new method, clears to `.loading` — **before**
bumping the reload, rather than letting `load()`'s own "keep the stale value while refetching"
behaviour apply. That behaviour is right for an ordinary refresh, where *what* is on screen does
not change, and wrong for a switch: a card tapped in the window between picking a circle and the
refetch landing would resolve against the **new** `groupID` (`circles.resolveActiveID()` is read
fresh at the moment of the tap) while still showing the **old** circle's round. Clearing first
removes the window instead of racing it.

Two real bugs came out of review, both fixed before closing, both caught by actually looking at
the rendered output rather than trusting green tests:

1. `a11y.switcher.attention` shipped without its trailing period, so the joined
   `Copy.A11y.switcherRow(...)` sentence read "Wants your attention" with no stop before nothing
   followed — caught by `AccessibilityCopyTests`, not by eye.
2. The stacked accessibility-size row layout (added to fix a real truncation bug below) silently
   never took effect in the snapshot suite: `snapshotContent` read `@Environment(\.dynamicTypeSize)`
   directly, and `@Environment` only resolves on a view SwiftUI itself installs — calling
   `sheet.snapshotContent` on a bare struct value (`SnapshotRenderer.image(of:device:typeSize:)`'s
   own pattern, the same one `HowToSheet.snapshotContent` and `GuessSheet.content(layout:typeSize:)`
   use) never installs `CircleSwitcherSheet` itself, so the property silently read its default
   regardless of the size the suite asked to render. Fixed the same way `GuessSheet` already had
   to: an explicit `typeSizeOverride`, and `snapshotContent(typeSize:)` takes the size as a
   parameter instead of trusting the environment. Every `-accessibility1`/`-accessibility5` golden
   from before this fix was silently the `.large` layout and had to be deleted and re-recorded.

Bug #2 was hiding: below `.accessibility1` a name and a state word share one line
(`TrackRow`'s own threshold and shape), and above it a name long enough to matter — "Late Night
Radio" — truncated to four characters (`Late…`) fighting a state word on the same line at
`accessibility5`, which is exactly the `docs/12` §1 "nothing truncates" failure the size exists
to catch. Only visible by actually opening the rendered PNG; the harness had already written it
to disk as the "golden" and the suite was green. Fixed by stacking the row (name above state)
at `.accessibility1` and up, the same threshold `TrackRow.content` already uses for its own
two-line accessibility layout.

The `reviewer` agent found a third, more interesting one, in the diff rather than in a
screenshot: `RoundStore.load()`'s round/group requests are cancelled when `.task(id: loadToken)`
restarts on a switch, but Swift's task cancellation is cooperative — a response that had already
fully arrived when cancellation was requested completes normally regardless, so a slow, late
response for the circle the caller just switched **away** from could still reach `state.apply`
and silently revert the screen to the wrong circle, with no error and no visible cause. Fixed by
guarding the apply behind `circles.activeGroupID == groupID`: a response for a circle no longer
active is dropped, and the load for the circle actually on screen supplies its own answer. Two
smaller findings from the same pass: picking the circle already active in the switcher ran the
full `invalidate()` + reload path for no reason, flashing the skeleton to redraw the exact thing
already showing — `switchCircle` now no-ops past closing the sheet in that case; and the
one-circle snapshot had never exercised its own extreme (longest name, largest size) — switched
its fixture to "Late Night Radio" and added `.accessibility5`, regenerating six goldens.

Verified: `./ios/scripts/lint.sh` clean; unit 417/417 (including new `CircleSwitcherTests` and
the switcher's `AccessibilityCopyTests` additions); snapshot 65/65 (12 `CircleSwitcher`
goldens, each looked at, not just diffed); `verify-fixture.sh` for `FixtureRoundTests` (7/7,
including `selectingACircleReScopesTheRoundToIt` against the real second circle `E19-01` put in
the fixture server for this). Per `CLAUDE.md` §8 F's device-matrix override, the manual SE and
`accessibility5` simulator pass is not required this slice — the golden matrix (SE + 15 Pro Max
× `large`/`accessibility1`/`accessibility5`, `-three-*` at `accessibility5` too) already covers
it and is what caught the truncation bug above; iPhone 17 is the live pass. Simulator: built and
ran against the fixture server — tapped the header on the sealed screen, the sheet opened sized
to its two rows (no wasted space), picked "Late Night Radio," and the whole screen re-scoped:
header name, seal-stamp initial (`T` → `L`), and the sealed-until time (8:00 PM → 9:00 PM, each
circle's own `reveal_hour`) all updated together, with no old-circle content visible mid-switch.
Switched back and confirmed row order stayed stable (both circles `sealed`, no needs-action, no
reshuffling). The needs-action mark and the stacked accessibility layout are verified by the
golden suite rather than re-demonstrated live, since the fixture's second circle is pinned to
`sealed`/`needs_action: false` and cannot exercise that state itself.

---

### E19-03 — A notification opens the circle it came from

**Status:** todo · **Deps:** E19-02, E23-01 · **Parallel:** no
**Reads:** `docs/05` §2, `docs/13` §9
**Touches:** `BlindDrop/App/DeepLink.swift`, `BlindDrop/App/Router.swift`,
`BlindDrop/Core/Push/PushRouter.swift`, unit tests
**Verify:** `./ios/scripts/lint.sh`; `DeepLinkTests`, `PushTests`, `RoutingTests`. Simulator:
delivered payloads for a non-active circle land on the right screen, cold and warm.

A reveal push for a circle the user is not currently looking at must switch to it, not drop them
into whatever was on screen. Cold launch, warm launch, and already-open all have to agree.

`Router` already refuses to apply a deep link before the round loads, which is the correct
instinct and gets harder here: the target circle's round may not be loaded at all.

- [ ] Payloads carry the circle; the parser is total and rejects malformed input safely
- [ ] Tapping switches circle and lands on the right phase, from cold, warm, and foreground
- [ ] A link naming a circle the user has left, or never joined, fails gracefully
- [ ] Phase gates still hold — a deep link can never open a screen the phase forbids
