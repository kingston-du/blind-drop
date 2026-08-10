# E08 — iOS foundation

Design system, networking, and the clock. Everything in `Features/` composes from what this
epic builds; if a screen task needs a colour, a font, or a component that isn't here, add it
here rather than inlining it.

Runs against the fixture server (`E00-05`), so it does not wait on the backend.

---

### E08-01 — App skeleton, light mode, environment

**Status:** todo · **Deps:** E00-03 · **Reads:** `docs/13` §1, §4, §8, `docs/07` (intro)
**Touches:** `App/BlindDropApp.swift`, `App/AppEnvironment.swift`, `App/RootView.swift`, `App/DeepLink.swift`
**Verify:** app launches to a placeholder in the simulator

- [ ] `.preferredColorScheme(.light)` at the root; **no** `colorScheme` branching anywhere
- [ ] `AppEnvironment` is the composition root and the only singleton, injected via
      `.environment(_:)`
- [ ] `-apiBaseURL` launch argument honoured so tests point at the fixture server
- [ ] `RootView` routes on session state per `docs/13` §4
- [ ] `NavigationStack` with a typed path; two destinations, one modal. **No tab bar.**
- [ ] `blinddrop://` parsing for the four routes in `docs/05` §5, stored as `pendingRoute`
      and consumed only after the round loads

---

### E08-02 — Palette and contrast test

**Status:** todo · **Deps:** E08-01 · **Reads:** `docs/07` §2
**Touches:** `DesignSystem/Palette.swift`, `BlindDropTests/Unit/PaletteContrastTests.swift`
**Verify:** `xcodebuild test -only-testing:BlindDropTests/PaletteContrastTests`

Transcribe the tokens exactly. Write the WCAG relative-luminance function and assert every
row of the `docs/07` §2 contrast table.

- [ ] All tokens present with the exact hex values
- [ ] Contrast test covers all ten rows and fails loudly if a hex changes
- [ ] Doc comments record the three amber tiers and their jobs: `amber` fills, `amberDeep`
      draws, `amberText` writes
- [ ] Doc comment on `alert`: errors only, never a game state
- [ ] No `Color(light:dark:)` anywhere

---

### E08-03 — Typography and font bundling

**Status:** todo · **Deps:** E08-01 · **Reads:** `docs/07` §3, `docs/12` §1
**Touches:** `DesignSystem/Typography.swift`, `Resources/Fonts/BricolageGrotesque.ttf`, `Info.plist`
**Verify:** `xcodebuild test -only-testing:BlindDropTests/TypographyTests`

- [ ] Bricolage Grotesque variable font bundled and registered; `wdth` axis set to 110
- [ ] The eleven `TypeStyle` cases from `docs/07` §3
- [ ] Every style scales with Dynamic Type via `UIFontMetrics` / `ScaledMetric`
- [ ] **Tabular figures on every mono style and every display numeral**
- [ ] Display face capped at 1.6× scale (`docs/12` §1) — the one allowed scaling limit
- [ ] Countdown switches to the coarse form above `.accessibility2` (`docs/12` §1)
- [ ] Test: the display face actually loaded — assert the resolved font name is not SF Pro

---

### E08-04 — Component library

**Status:** todo · **Deps:** E08-02, E08-03 · **Reads:** `docs/07` §4–5, `docs/12` §2–5
**Touches:** `DesignSystem/Components/*`, `DesignSystem/Space.swift`, `DesignSystem/Haptics.swift`
**Verify:** snapshot tests for each component at three type sizes

Ten components from `docs/07` §5. Build them with their accessibility from `docs/12` §2 —
retrofitting VoiceOver later means rebuilding the view hierarchy.

- [ ] `PrimaryButton` takes the phase accent as a parameter, never hardcodes it
- [ ] `FlightCard` is a **single** accessibility element with the preview control as a nested
      child and a custom action
- [ ] `StatMeter` renders a marker, **no fill from the left** — filling implies more is better
- [ ] `NameChip` consumed state carries both opacity and an accessibility value change
- [ ] `ArtworkView` substitutes `{w}x{h}` at the sizes in `docs/06` §2.1 × display scale,
      capped at 1200, with the `artwork_bg_color` placeholder at 12%
- [ ] `CountdownView` takes a `ServerClock`, never `Date()`
- [ ] No shadows on any component
- [ ] Every interactive element ≥ 44×44 `contentShape`

---

### E08-05 — `APIClient` and DTOs

**Status:** todo · **Deps:** E08-01 · **Reads:** `docs/13` §3, §6, `docs/04` §1–6
**Touches:** `Core/Networking/*`
**Verify:** `xcodebuild test -only-testing:BlindDropTests/NetworkingTests`

- [ ] `APIClient` is an `actor`; DTOs are `Sendable` value types
- [ ] Every response passes through `Envelope<T>`, which feeds `server_now` to `ServerClock`
      **before** returning the payload
- [ ] `RoundDTO.Phase` is an enum with associated values, decoding **only** that phase's keys
      — a view holding an `open` round must be unable to reach `cards` (`docs/13` §3)
- [ ] Every error code from `docs/04` §1 mapped to `APIError` with its copy-deck string
- [ ] `waitsForConnectivity = false` — fast honest failures
- [ ] Retry: idempotent GETs twice (200/600ms); the two idempotent PUTs once; nothing else
- [ ] `X-Storefront` on every request
- [ ] `LoadState` includes a `.stale(T, APIError)` case so no screen can forget the
      cached-data path

---

### E08-06 — `ServerClock` and the `Date()` lint

**Status:** todo · **Deps:** E08-05 · **Reads:** `docs/13` §5, `docs/15` AC-2
**Touches:** `Core/Time/ServerClock.swift`, `Core/Time/CountdownTimer.swift`, `ios/scripts/lint.sh`
**Verify:** `xcodebuild test -only-testing:BlindDropTests/ServerClockTests`

This type is the client half of AC-2. Read `docs/13` §5 carefully; all six rules are testable.

- [ ] Anchored to `ProcessInfo.systemUptime`, **not** `Date()`
- [ ] `now` is **optional** — before the first response the app doesn't know the time and
      says `--:--:--` rather than guessing
- [ ] Re-anchors on every response
- [ ] Anchor invalidated on `willEnterForeground`; a refetch precedes any countdown render
- [ ] Group-local formatting uses the **group's** timezone, never `TimeZone.current`
- [ ] Lint rule: `Date()` outside this file fails CI
- [ ] Tests: ±5-year device-clock shift changes nothing; timezone change changes nothing;
      stale anchor returns `nil`; drift over a simulated 2h session < 1s

---

### E08-07 — Snapshot test harness

**Status:** todo · **Deps:** E08-04 · **Reads:** `docs/15` §3, `docs/12` §8
**Touches:** `BlindDropTests/Snapshot/*`
**Verify:** `xcodebuild test -only-testing:BlindDropTests/Snapshot`

Hand-rolled against golden PNGs — no third-party snapshot library (zero dependencies).

- [ ] Renders a view at a given device size and Dynamic Type size, diffs against a golden
- [ ] Matrix helper: `{SE, 15 Pro Max} × {large, accessibility1, accessibility5}`
- [ ] Failure writes the actual and the diff into a reviewable directory
- [ ] `RECORD_SNAPSHOTS=1` regenerates goldens
- [ ] A test that renders with the OS in dark mode and asserts output is identical to light —
      this is how "light mode only" stays true
