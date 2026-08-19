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

**Status:** wip · **Deps:** E18-01, E18-02 · **Parallel:** no — it moves shared infrastructure
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

- [ ] Group identity carried explicitly through the client — session, stores, endpoints
- [ ] `Endpoint.swift` keeps owning path construction; no path built at a call site
- [ ] Every store can be re-scoped and refetches rather than serving another circle's cache
- [ ] Deep links can name a circle; existing links still resolve to a sensible default
- [ ] Simulator: sign in, drop, seal, reveal, guess, results — one circle, no visible change

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
