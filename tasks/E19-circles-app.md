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

**Status:** todo · **Deps:** E19-01 · **Parallel:** no
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

- [ ] Tapping the header name opens the sheet; it is a labelled control, reachable without the
      gesture (`docs/12` §5)
- [ ] Rows: name, the caller's state, an optional needs-action mark. Nothing else
- [ ] Needs-action circles first, no visible section
- [ ] A subtle mark beside the header name when another circle wants attention
- [ ] Switching re-scopes every store and lands on the right phase for that circle
- [ ] Sheet height suits one circle as well as three; SE and `accessibility5` checked
- [ ] Every string in `docs/11` first

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
