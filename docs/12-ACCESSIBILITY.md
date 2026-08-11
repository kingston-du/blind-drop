# 12 — Accessibility

This is a quality floor, not a stretch goal. A build that fails these is not done.

---

## 1. Dynamic Type

**Full support up to the accessibility sizes** (`.accessibility5` / XXXL).

Rules:
- Every text style is registered with a `TextStyle` and scales. No fixed `.font(.system(size:))`
  anywhere. The display face scales via `UIFontMetrics`/`ScaledMetric` against `.largeTitle`.
- **Nothing truncates and nothing overlaps at `.accessibility5` on an iPhone SE.** Test that
  combination explicitly; it is the worst case in the app.
- Layouts that are side-by-side at default size **reflow to stacked** above
  `.accessibility1`. Use `@Environment(\.dynamicTypeSize)` and `ViewThatFits`, not a width
  check.
  - Results §7.2: the Readability / Ear pair stacks.
  - Share-card headline pair: stacks (already true in the story variant).
  - Reveal card: number moves above the artwork row rather than beside it.
- The reveal card's number is capped at 1.6× its base scale. At `.accessibility5` an
  uncapped 56pt display numeral is ~130pt and eats the card. The cap is the one place a
  scaling limit is allowed, and the number stays the largest element on the card regardless.
- Tabular figures persist at every size.

### Countdown at large sizes
`monoXL` at `.accessibility5` will not fit `HH:MM:SS` on an SE. Above `.accessibility2` the
countdown switches to the coarse form — "3 hours" / "12 minutes" / "under a minute" — in
`bodyLStrong`. It stops ticking every second and updates every minute. This is a genuine
improvement, not a fallback: at that text size the user is not reading seconds.

---

## 2. VoiceOver

Every card announces **its number, title, artist, and current guess** — that requirement is
literal and testable.

| Element | Trait | Label | Value / hint |
|---|---|---|---|
| Reveal card | `.button` | `a11y.card.guessed` / `a11y.card.unguessed` / `a11y.card.mine` | Hint: "Double-tap to choose who dropped this" |
| Name chip | `.button` | `a11y.namechip` | State: unassigned / assigned to No. N |
| Preview control | `.button`, `.startsMediaSession` | `a11y.preview.play` / `.stop` | — |
| Sealed card | `.image` + `.staticText` | `a11y.sealed` | — |
| Countdown | `.updatesFrequently` | `a11y.countdown` | Recomputed on focus, not every tick |
| Readability meter | `.adjustable` off, static | `a11y.readability` | Value announced as a percentage and a band name |
| Results card | `.staticText` | `a11y.card.result` (+ `.result.mine`) | — |
| Track row (search) | `.button` | "%@ by %@" | Hint: "Double-tap to choose this song" |

Rules:
- Cards are a **single accessibility element**. Do not let VoiceOver walk into the artwork,
  the title, and the artist separately — that is three swipes per card, 36 swipes to read a
  12-card reveal.
- The preview control is the one nested element, exposed as a custom action **and** as a
  child so it is reachable both ways.
- Assigning a guess posts `.announcement`: "No. 3 assigned to Cal."
- The seal posts `a11y.seal.done` after the animation. The unseal posts `a11y.unseal.done`
  once, after the sequence — not once per card.
- `.accessibilityRespondsToUserInteraction` is set correctly on disabled guess controls for
  non-submitters, and their label includes the reason. A disabled control that does not
  explain itself is worse than a hidden one.
- Rotor: reveal cards form a custom rotor "Songs" so a VoiceOver user can jump between
  numbers directly.

### The blind window applies to VoiceOver too
Do not add accessibility labels that expose anything the visual UI does not — no
"4 of 8 submitted" in a hidden label, no `accessibilityValue` on the submit screen that
counts anything. `E14`'s leak audit includes a pass over accessibility labels on the submit
screen.

---

## 3. Contrast

Verified in `07-DESIGN-SYSTEM.md` §2 and asserted by `PaletteContrastTests`.

Additional rules:
- `inkFaint` is **never** used for body text. Large text (≥24pt) and non-text UI only.
- `amber` (the fill tier) is never used for text or for a lone graphical mark. Use
  `amberText` and `amberDeep`.
- Consumed name chips are at 0.6 opacity **and** carry a state change in their accessibility
  value. Opacity alone is not a status indicator.
- Correct/incorrect in results is marked by **shape** (check vs strike) as well as colour.
  Colour is never the only channel.
- The focus ring on a selected card is a 2pt `ultramarine` border — 6.6:1 against `surface`,
  above the 3:1 required for a focus indicator.

---

## 4. Motion and haptics

- `accessibilityReduceMotion` handling is specified in `09-MOTION-SPEC.md` §5. The seal and
  unseal become crossfades; they are never eliminated, and no state is skipped.
- Colour transitions are retained under reduced motion because they carry meaning.
- Haptics still fire under reduced motion. Reduced motion is not reduced feedback.
- `accessibilityReduceTransparency`: nothing in this app uses material or blur, so there is
  nothing to do. Do not add any.

---

## 5. Touch targets and interaction

- Minimum 44 × 44pt for every interactive element. The preview control is visually 28pt with
  a 44pt `contentShape`.
- Name chips are 36pt tall visually with 44pt vertical `contentShape` including their
  spacing.
- **No gesture is the only way to do anything.** There is no swipe-to-assign, no long-press-
  required action, no drag-and-drop. Everything is a tap. (This also serves the 90-second
  budget — taps are faster than drags.)
- Keyboard / Full Keyboard Access: every control is focusable with a visible focus state.
  `focusable()` + `.focusEffectDisabled(false)`.
- The search field supports hardware keyboard return-to-select.

---

## 6. The 12-member small-device case

Called out separately because the PRD calls it out: **the guess sheet must not require
scrolling past the fold at 12 members on a small device without an obvious affordance.**

Implementation (`08-SCREEN-SPECS.md` §6):
- The name pool is pinned to the bottom, horizontally scrollable, with a trailing fade that
  makes overflow visible.
- At `.accessibility3`+, it becomes a 2-row wrapping grid capped at 40% of screen height with
  its own vertical scroll and a visible scroll indicator.
- A test asserts that at iPhone SE × 12 members × `.accessibility5`, every name chip is
  reachable and every card is reachable, with no zero-size or clipped hit regions.

---

## 7. Other

- **Reduce Motion for autoplay:** nothing autoplays audio, ever, under any setting.
- **VoiceOver + previews:** starting a preview does not duck or interrupt VoiceOver speech;
  configure the audio session with `.duckOthers` off.
- **Localisation readiness:** all strings are in `Localizable.strings`
  (`11-COPY-DECK.md`), pluralisation via `.stringsdict` for every `%lld` count. English only
  in v1, but no string is inlined.
- **Right-to-left:** not tested in v1, but use leading/trailing, never left/right. Free to
  get right, expensive to retrofit.

---

## 8. Verification

| Check | How |
|---|---|
| Dynamic Type to `.accessibility5` | Snapshot tests at `.large`, `.accessibility1`, `.accessibility5` for all five screens, iPhone SE and iPhone 15 Pro Max |
| No truncation at max size | Snapshot diff plus an assertion that no `Text` reports a truncated layout |
| VoiceOver labels present | UI test walks each screen and asserts every element has a non-empty label |
| Card announces all four facts | Unit test on the label builder against the `a11y.card.*` formats |
| Contrast | `PaletteContrastTests` |
| Touch targets | UI test asserts every hit region ≥ 44×44 |
| 12 members on SE | Dedicated snapshot + reachability test |
| Reduced motion end state | UI test comparing final state with and without the setting |
