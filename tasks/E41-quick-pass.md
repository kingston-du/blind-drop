# E41 — The quick pass

Two slices. From an owner request, diagnosing a real asymmetry: people drop reliably and don't
guess. The two acts look symmetric and are not — dropping is one decision in a ten-hour window,
guessing is `N − 1` decisions in a two-hour evening slot, and the cost grows with the circle
while the drop's stays flat. `docs/prompts/QUICK-PASS-DESIGN-PROMPT.md` states the problem in
full and is this epic's design brief.

**The fix.** One card at a time, full screen, tap a name, next. The same `N − 1` decisions
arranged as a ninety-second posture instead of a five-minute one, and it is where a reveal push
now lands. The call sheet is untouched and stays the considered path — this is the on-ramp to it,
not a replacement for it.

**What this epic does not need.** No migration, no endpoint, no DTO, no push-worker change.
`PUT /rounds/{group}/current/guesses` is already a partial upsert
(`server/supabase/functions/rounds/index.ts:731`), `RevealStore` already debounces the whole
sheet, and the `reveal` and `guess_reminder` pushes already deep-link to the round root
(`push-worker/worker.ts:114`), which during `revealed` is `RevealHost`. Both slices are
client-only.

> **Owner amendment — the per-slice simulator pass is suspended for this epic.** `CLAUDE.md` §8 F
> asks for an install-and-launch pass per user-facing slice. The owner has said not to spend on
> them here and will confirm feel on a physical device. So: automated verification per slice, and
> **one** consolidated simulator screenshot pass after both slices are merged, covering the states
> listed in E41-02's Verify. Anything not covered there is named as unverified at close.

> **Open question — does the quick pass stop on the player's own card?**
> Interpretation taken: **no.** The run is the cards you can name; your own is passed over and the
> flight numeral simply jumps (`03` → `05`). The alternative — showing it with *Yours* and a
> Continue — costs a tap on the one screen whose entire argument is that taps are the scarce
> resource, and the flight behind already shows the card in place, so nothing is hidden. The cost
> is that the numeral sequence has a hole in it, which is exactly the thing `docs/08` §6 refuses
> to do on the flight. It is defensible here and not there: the flight is a list of everything,
> the quick pass is a list of what you have to do.

> **Open question — does the quick pass auto-present over the unseal?**
> Interpretation taken: **no, it waits.** The unseal is one of the two moments carrying the app's
> entire motion budget (`docs/09` §1) and it plays once per round. Covering it with a modal on the
> first arrival at `revealed` would spend the signature moment on nothing. So on a round's first
> arrival the unseal plays on the flight and the quick pass presents when it settles; on every
> later arrival, including a `guess_reminder` tap, it presents immediately. This is the one place
> the epic departs from the owner's literal *"should land on the first card, not the full sheet"*,
> and it is a one-line change to reverse if the device pass disagrees.

---

### E41-01 — One card, one tap, next

**Status:** wip
**Deps:** —
**Parallel:** no
**Reads:** `docs/prompts/QUICK-PASS-DESIGN-PROMPT.md`, `docs/07` §2/§3/§4/§5, `docs/08` §6,
`docs/09` §1, `docs/11` (reveal block), `docs/12` §1/§2,
`ios/BlindDrop/Features/Reveal/{RevealScreen,RevealStore,GuessSheet}.swift`,
`ios/BlindDrop/Features/Round/RoundScreen.swift:776` (`RevealHost`),
`ios/BlindDrop/DesignSystem/Components/{NameChip,PreviewControl,ArtworkView,CloseButton,PrimaryButton}.swift`
**Touches:** new `Features/Reveal/QuickPass/{QuickPassScreen,QuickPassSequence}.swift`,
`Features/Reveal/RevealStore.swift` (one new method), `Features/Round/RoundScreen.swift`
(presentation + entry), `Features/Reveal/RevealScreen.swift` (entry control),
`DesignSystem/Components/NameChip.swift` (a `.large` size), `DesignSystem/Motion/MotionTokens.swift`
(one advance spring), `Resources/Localizable.strings`, `docs/08` (a new §6.1), `docs/11`,
`ios/BlindDropTests/{Unit,Snapshot}/`
**Verify:** `./ios/scripts/lint.sh`; `-only-testing:BlindDropUnitTests/QuickPassSequenceTests
-only-testing:BlindDropUnitTests/RevealStoreTests
-only-testing:BlindDropSnapshotTests/QuickPassSnapshotTests`. No simulator pass — see the owner
amendment above.
**Proves:** AC-4

**No new store.** `QuickPassScreen` is a second view over the *same* `RevealStore` that
`RevealHost` already builds (`RoundScreen.swift:817`). Every assignment goes through the store's
existing debounced whole-sheet save, so the quick pass and the call sheet can never disagree about
what the player said, and closing the cover mid-run loses nothing. The only store change is a new
`place(_ name: String, on cardNumber: Int)` funnelling into the private `assign(_:to:)`
(`RevealStore.swift:290`) **without** touching `focusedCard` or `selectedMember` — those are call
sheet interaction state and the quick pass has no business moving them.

**The sequence is a value.** `QuickPassSequence` holds the ordered card numbers the player can
name — `store.cards` filtered by `isGuessable` (`RevealStore.swift:326`), which is what drops the
player's own card — plus a cursor. Built once when the cover appears so nothing reorders under a
finger mid-run, and it starts at the first card with no assignment. Every card already named means
it opens on the recap. A value with no view in it is a value a unit test can drive, which is where
the resume, skip, last-card and all-named rules get proved.

- [ ] `QuickPassSequence`: `init(cards:isGuessable:assignments:)`, `current`, `advance()`,
      `jump(to:)`, `isComplete`, `position` (`4 of 8` — the *flight* numbers, not run indices).
      Unit-tested for: a three-person circle where one card is yours, a twelve-person circle,
      resume onto the first unnamed card, all-named opening complete, and a run where the player
      re-names a card they already answered.
- [ ] `QuickPassScreen`, one column, `Layout.screenInset`, ultramarine and nothing else:
      - **The numeral is the anchor.** `04` in `displayXL` `ultramarine`, `/ 08` baseline-aligned
        beside it in `displayS` `inkFaint` — legal at 24pt, and it is the tasting-flight sheet's
        own grammar. Capped at 1.6× scale, the same cap `FlightCard` already takes (`docs/12` §1).
      - **Artwork is the hero and it is bigger than anywhere else in the app.** Square, leading
        edge of the column, `Radius.artwork`, nothing layered over it. Its side is the space the
        rest of the column does not need, clamped to `140…320` — so five names get a large one
        and eleven names get a smaller one without either layout breaking.
      - Title `bodyLStrong`, artist `bodyM` `inkDim`, `PreviewControl` on the row's trailing edge
        with its own 44pt target. A card with no preview URL renders no control at all.
      - **No prompt text.** `reveal.card.prompt` — *"Who dropped this?"* — is not drawn. The
        numeral, the song and a row of names are the question; writing it out is a line of copy
        on the one screen whose argument is that nothing should be read. Deliberate, recorded
        here so it is not re-added as an oversight.
      - Countdown to `answersAt`, `monoS` `inkDim`, top trailing. Present because the window is
        real; small because it is not a per-card clock.
      - `CloseButton` top leading.
- [ ] **Names at tap scale.** `NameChip` gains a `size` of `.regular` (today's 36pt `bodyM`) and
      `.large` (52pt, `bodyL`) rather than a second component — the consumed and selected
      contracts, the wrapping rule and the accessibility value in `docs/12` §3 all come along for
      free. Flow-wrapped, `Space.sm` gaps. A consumed name stays struck through and stays
      tappable: the API permits naming one person twice (`rounds/index.ts:750`) and the quick pass
      must not be stricter than the sheet.
- [ ] **Skip is a peer, and it is a word.** Its own row under the grid, separated by `Space.lg`,
      an intrinsic-width pill at the same 52pt height, **dashed** 1pt `edgeStrong` border, no fill,
      `inkDim` `bodyL`, reading `Skip`. Dashed already means *nothing is written here* in this app
      — it is the unassigned chip's own outline — so the treatment is semantic rather than
      decorative. No icon: the app draws almost none, and a bare glyph here reads as *next* rather
      than as *I don't know*. It is not small grey text and it is not a full-width button; it is
      one more thing you can tap with the same thumb.
- [ ] **The advance is 220ms and it is not a set piece.** Tap a name → the chip fills
      `ultramarine` for ~100ms → haptic `.impact(.light)` at 0.5 → the card's content leaves
      leading with a fade while the next arrives trailing, `spring(response: 0.30,
      dampingFraction: 0.90)` in a new `Motion.QuickPass.advance`. Skip is the same transition with
      `.impact(.soft)` and no chip fill. No flick physics, no deck, no flip, no page turn, no
      sound, no confetti — `docs/09` §1's budget is spent on the seal and the unseal and this is
      not either of them. **Reduce Motion collapses it to a cross-dissolve** with no offset.
- [ ] Entry from the flight: the reveal screen's primary action reads `reveal.quickpass.start`
      while the sheet is empty and reverts to `reveal.action` (*Lock in guesses*) once anything is
      assigned. Tapping a card still opens the call sheet exactly as it does today — both routes
      survive, and the screen still has exactly one primary action (`docs/07` §4).
- [ ] Presented as a `fullScreenCover` from `RevealHost`. **The first one in the app** — every
      existing modal is a `.sheet` (`RootView.swift:117`, `RoundScreen.swift:242…277`). Justified
      rather than casual: a sheet's grabber and inset corners keep the flight visible behind the
      one screen in the app that is deliberately about a single card, and the detent chrome would
      sit exactly where the name grid needs to be.
- [ ] Blocked players never reach it: `canGuess == false` renders no entry control and the cover
      cannot be presented. The flight keeps showing them the disabled apparatus in full
      (`docs/08` §6) — they must still see what they missed.
- [ ] `docs/12`: the card is a **single** accessibility element announcing number, title, artist;
      advancing posts an announcement naming the card arrived at, so a VoiceOver user is never
      moved silently. Chips and Skip are buttons at 44pt minimum. State never carried by colour
      alone.
- [ ] `accessibility5` on an SE: artwork clamps to its floor, the pool becomes a single column,
      the page scrolls. Snapshot goldens must render the content **outside** its `ScrollView` — the
      `snapshotContent(typeSize:)` pattern `RevealScreen.swift` already uses, because
      `ImageRenderer` asked for a `ScrollView` produces a fixed rectangle with the rest clipped.
- [ ] New copy in `docs/11` in the same commit (`CLAUDE.md` §6): `quickpass.skip` = *Skip*,
      `reveal.quickpass.start` = *Start naming*, `a11y.quickpass.card`. Reuses `reveal.card.mine`,
      `reveal.action`, `reveal.callsheet`, `reveal.countdown.label`.

---

### E41-02 — Where the push lands, and how the run ends

**Status:** todo
**Deps:** E41-01
**Parallel:** no
**Reads:** `ios/BlindDrop/App/{Router,DeepLink,RootView}.swift`,
`ios/BlindDrop/Core/Push/PushRouter.swift`, `ios/BlindDrop/App/PushAppDelegate.swift:59`,
`server/supabase/functions/push-worker/worker.ts:99` (`notificationDeepLink`),
`docs/05` §, `docs/08` §6
**Touches:** `Features/Reveal/QuickPass/QuickPassScreen.swift` (the recap),
`Features/Round/RoundScreen.swift` (`RevealHost` auto-present rule),
`Features/Reveal/RevealStore.swift` (nothing, if E41-01 got `place` right),
`Resources/Localizable.strings`, `docs/08` §6.1, `docs/11`, snapshot goldens
**Verify:** `./ios/scripts/lint.sh`;
`-only-testing:BlindDropUnitTests/QuickPassSequenceTests
-only-testing:BlindDropUnitTests/RouterTests
-only-testing:BlindDropSnapshotTests/QuickPassSnapshotTests`. Then **one** simulator pass on
iPhone 17, both slices merged, screenshotting: card 1 of a six-person run · a name tapped ·
a skipped card · the recap · the flight after handoff · the run re-entered half-finished ·
`accessibility5`. Physical-device confirmation of feel is the owner's.
**Proves:** AC-4

**Nothing on the server changes, and that is the finding, not an omission.** The `reveal` and
`guess_reminder` pushes already carry `deep_link = blinddrop://circle/<group>/round/current`
(`worker.ts:114`), `PushAppDelegate` already hands it to `PushRouter`
(`PushAppDelegate.swift:64`), and `Router.consume` already pops to root and lets the phase gate
choose (`Router.swift:85`) — which during `revealed` is `RevealHost`. The whole of "the push lands
on the first card" is therefore a presentation rule inside `RevealHost`, not a new URL, a new
`DeepLink` case, or a payload field.

**A *Guess now* notification action is deliberately not built.** It would need `aps.category` in
`worker.ts:187`, a kind→category map in `_shared/apns.ts`, a `UNNotificationCategory` registration
and an `actionIdentifier` branch in `PushAppDelegate.swift:59` — to reach the screen that tapping
the notification body now reaches anyway. Recorded here so it is a decision rather than a gap.

- [ ] Auto-present rule in `RevealHost`, in priority order:
      1. Never when `canGuess == false`, when every card is named, or while the round's unseal is
         unplayed or running (the open question above).
      2. **Always** when `router.pending` is a `.round` link for this circle — that is a push tap
         or a link, an explicit intent, and it re-presents however many times it happens.
      3. **Once per round otherwise**, keyed by round id in `UserDefaults`, so a player who
         dismissed the cover to browse the flight is not handed it again on every foreground.
      Unit-test the rule as a pure function over those inputs rather than through the view.
- [ ] The recap, when the run completes — the beat that makes the flow finishable without ever
      touching the call sheet. `reveal.callsheet` as a `displayM` heading, then one compact row per
      card: `numberM` numeral · 40pt artwork · title `bodyM` · the name in `bodyLStrong`
      `ultramarine`, *Yours* in `amberText` on your own card, an em dash in `inkQuiet` on a skipped
      one. Tapping a row jumps back to that card. `PrimaryButton` **Lock in guesses** at the foot,
      calling the store's existing `lockIn()`. Scrolls at twelve rows; same `snapshotContent`
      treatment.
- [ ] The em dash on a skipped card is the honest mark and it is `inkQuiet`, not `alert` and not
      amber. Once `E39` lands, a skipped card is filled at chance rather than scored as wrong, so
      the recap must never render a blank as a failure. Nothing here blocks on `E39`; the treatment
      is chosen so that it does not have to change when it arrives.
- [ ] Dismissing the recap — by **Lock in guesses** or by `CloseButton` — lands on the flight with
      the call sheet at its open detent, every chip filled in, ready to change. *"Here is what you
      said"*, not another screen of the same task.
- [ ] `docs/08` gains §6.1 describing the quick pass, its states and the auto-present rule, so the
      screen spec is not only in this epic.
