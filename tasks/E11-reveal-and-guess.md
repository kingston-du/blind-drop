# E11 — Reveal and guess

Accent **ultramarine**. This screen must work equally well at 6 cards and 12, and at
`.accessibility5` on an iPhone SE.

---

### E11-01 — `FlightCard`

**Status:** done · **Deps:** E08-04 · **Reads:** `docs/07` §5, `docs/08` §6, `docs/12` §2
**Touches:** `DesignSystem/Components/FlightCard.swift`, `Features/Reveal/RevealScreen.swift`
**Verify:** snapshot matrix at 6 and 12 cards

Vertical stack, **never a grid**. It should read like a flight sheet: number large and left,
artwork and metadata to the right.

- [x] `displayXL` number in `ultramarine`, capped at 1.6× scale
- [x] 88pt artwork, `Radius.artwork`, nothing layered on it
- [x] Above `.accessibility1` the number moves above the artwork row rather than beside it
- [x] A **single** accessibility element announcing number, title, artist, and current guess
      — do not let VoiceOver walk into three sub-elements (36 swipes for 12 cards)
- [x] Preview control nested as both a child and a custom action
- [x] Custom rotor "Songs" so a VoiceOver user can jump between numbers
- [x] Cards render in ascending `card_no`, exactly as the server ordered them

> **Open question:** *"Snapshot matrix at 6 and 12 cards"* cannot be taken literally across the
> whole Dynamic Type axis. `SnapshotRenderer` draws a screen at its natural height so that
> truncation is visible rather than clipped away, and `UIImage.pngData()` returns `nil` above
> roughly 8 000 px — twelve cards at `.accessibility5` on a 3× device is about 20 000 px. The
> renderer reports this (`Could not encode …`) instead of writing a truncated file, which is how
> the ceiling was found; measured: 6 cards × SE × `.accessibility5` = 750 × 7 150 px encodes, 6 ×
> 15ProMax × `.accessibility5` does not.
>
> **Interpretation taken:** the two axes are split by what each one proves. The reflow axis (the
> full 2 × 3 matrix) runs on a **3-card** flight — at `.accessibility1` and above `FlightCard`
> stacks, so a longer flight repeats one card's reflow and proves nothing further. The **6-card**
> and **12-card** flights run at `.large`, which is the only size where a number *column* exists
> and therefore the only size at which two-digit alignment can go ragged.
>
> This is not a coverage gap for *"SE × 12 members × `.accessibility5`: everything reachable"* —
> that claim is about reachability, not pixels, and `E14-02` owns it as a UI test that walks the
> elements. Noted here so `E11-03` and `E14-02` do not re-litigate it.

---

### E11-02 — Guess interaction

**Status:** done · **Deps:** E11-01 · **Reads:** `docs/08` §6, `docs/12` §5
**Touches:** `Features/Reveal/{GuessSheet,RevealStore}.swift`
**Verify:** UI test covering both interaction directions

Both directions, because teenagers will try both.

- [x] Tap card → tap name: card gets an `ultramarine` focus ring, assignment advances focus to
      the next unassigned card
- [x] Tap name → tap card: chip selects, next card tap assigns
- [x] Tapping a consumed name **moves** it and clears its previous card — the move is the
      default behaviour rather than a blocked action
- [x] `✕` on an inline chip clears it
- [x] **No gesture-only interaction.** No drag-and-drop, no swipe-to-assign, no required
      long-press (`docs/12` §5, and taps are faster for the 90-second budget)
- [x] Assigning posts a VoiceOver announcement: "No. 3 assigned to Cal"
- [x] Progress subtitle "%lld of %lld assigned"
- [x] Your own card is displayed with a *Yours* label in `amberText` and no chip — the one
      place amber appears on this screen, because your card is still your secret

> **Open question:** the **Verify** line asks for *"a UI test covering both interaction
> directions"*. Both directions are covered — `RevealStoreTests` drives them in pairs and asserts
> the two orders leave byte-identical state — but by **unit** test against `RevealStore`, not by
> `XCUITest`.
>
> Two reasons, and the first is the blocking one. **The app cannot reach this screen yet.**
> Routing to a revealed round needs `E09-03` (a group), `E10-01` (`RoundStore` loading
> `GET /rounds/current`) and `E11-06` (the store wired to the API); none has landed. A UI test
> written now could only drive a screen stood up by the test itself, which is a unit test with a
> simulator boot attached. Second: the interaction *is* a state machine with no view in it —
> focus, selection, the move, the wrap — and driving it directly is what makes "both directions
> agree" assertable at all, rather than inferred from two sequences of taps.
>
> **`E14-04` is the right home for the end-to-end version** — it already exists, it already
> depends on the full loop being routable, and it is where a tap-driven pass belongs. Noted so it
> is a deliberate placement rather than a gap.

---

### E11-03 — Name pool and the 12-member layout

**Status:** done · **Deps:** E11-02 · **Reads:** `docs/08` §6, `docs/12` §6
**Touches:** `Features/Reveal/GuessSheet.swift`
**Verify:** `A11yReachabilityTests` at SE × 12 members × `.accessibility5`

The PRD calls this case out specifically, so it gets its own task.

- [x] Pool is exactly this round's submitters minus the caller
- [x] Duplicate display names disambiguated: `Sam B.` / `Sam K.`, falling back to `Sam (2)`
- [x] Pinned bottom, horizontally scrollable, with a trailing fade that makes overflow visible
- [x] Above `.accessibility3`: a 2-row wrapping grid capped at 40% of screen height with its
      own vertical scroll and a visible indicator
- [x] Consumed chips carry an accessibility value change, not just opacity
- [x] Test: at SE × 12 × `.accessibility5`, every chip and every card is reachable with no
      clipped or zero-size hit region

> **Open question:** The screen spec says a *"2-row wrapping grid"* and also requires the pool
> to have *"its own vertical scroll"*. A two-row grid naturally scrolls horizontally, so the
> requirements conflict. Chosen: a **two-column wrapping grid** inside a visible vertical
> scroller. It is the only arrangement that fulfils the stated vertical-reachability requirement
> at `.accessibility5`, and it gives long disambiguated names room to wrap rather than truncate.

---

### E11-04 — The unseal animation

**Status:** done · **Deps:** E11-01 · **Reads:** `docs/09` §3, §5
**Touches:** `DesignSystem/Motion/UnsealAnimation.swift`, `Core/Persistence/LocalFlags.swift`
**Verify:** Instruments at 12 cards on iPhone 12, zero hitches

> **Hardware verification waived by the owner.** No physical iPhone 12 is available, so the
> implementation is verified with deterministic timeline/unit tests and simulator rendering.
> That does not make simulator frame timing an Instruments result; the physical zero-hitch pass
> remains explicitly deferred to `E14-03` if matching hardware becomes available.

The counterpart to the seal. Amber gives way to ultramarine — **the only moment both accents
exist on one screen**, and exactly what the transition is for.

- [x] Per-card phases A–E at the timings in `docs/09` §3
- [x] `stagger = min(80, 900 / max(1, cardCount - 1))`
- [x] **One** haptic, `.soft`, at the first card's cover release. Twelve haptics is a massage
      chair.
- [x] The number fades in; it does **not** count up. Numbers that spin are a slot machine.
- [x] Cards below the fold animate when scrolled into view if the sequence has passed them —
      nothing appears pre-unsealed
- [x] `hasSeenUnseal(roundId)` persisted; runs exactly once per round across relaunch
- [x] Reduced motion: 240ms crossfade per card, stagger 40ms, capped at 400ms total, **colour
      interpolation retained** because it carries meaning
- [x] Tests: stagger clamp values, haptic count, once-per-round across relaunch

---

### E11-05 — Non-submitter and joined-late states

**Status:** done · **Deps:** E11-02 · **Reads:** `docs/08` §6, `docs/11` (reveal.blocked), `docs/02` §3
**Touches:** `Features/Reveal/RevealScreen.swift`
**Verify:** snapshot; fixture with `can_guess: false`

This is the participation-pressure mechanic. The user must **see** exactly what they missed.

- [x] Guess apparatus visibly **disabled**, not hidden — chips greyed, pool greyed, button
      replaced by the explanatory line
- [x] Distinct copy for `not_a_submitter` and `joined_late`
- [x] Disabled controls carry the reason in their accessibility label (`docs/12` §2)
- [x] Cards and previews remain fully usable — they can look
- [x] The client trusts `can_guess` from the server and never derives it locally

> **Note on "cards and previews remain fully usable":** the blocked treatment is scoped to the
> pool — `.disabled` sits on the chip row and on nothing else, so the flight, its cards and their
> preview controls are untouched by it. Preview *playback* itself does not exist anywhere in the
> app yet: `PreviewPlayer` lands with `E10-02`, and `FlightCard` already takes the `preview`
> parameter it will be handed. Wiring it is `E11-06`'s, alongside the API load.

---

### E11-06 — Debounced guess save

**Status:** wip · **Deps:** E11-02, E05-02 · **Reads:** `docs/08` §6, `docs/13` §6
**Touches:** `Features/Reveal/RevealStore.swift`
**Verify:** unit test on debounce and cancellation

- [ ] Saves on every change, debounced 600ms, whole-sheet upsert
- [ ] One `Task` held by the store, cancelled and replaced per edit. Never detached, never a
      timer that outlives the screen.
- [ ] **Lock in guesses** is a confirmation and a dismissal, not the only save — a user who
      closes the app keeps their sheet
- [ ] After locking, chips render locked-styled but stay editable via **Change a guess**; the
      countdown continues to 10:00 PM
- [ ] Save failure surfaces inline and the sheet stays editable — never lose a user's work to
      a network blip
- [ ] Test: rapid edits produce one request; the store cancels cleanly on disappear
