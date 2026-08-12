# E08 — iOS foundation

Design system, networking, and the clock. Everything in `Features/` composes from what this
epic builds; if a screen task needs a colour, a font, or a component that isn't here, add it
here rather than inlining it.

Runs against the fixture server (`E00-05`), so it does not wait on the backend.

> **Open question:** `CLAUDE.md` §5 and this epic's **Verify** lines pin
> `platform=iOS Simulator,name=iPhone 15`, which no longer ships in Xcode on the build
> machine — the available devices are iPhone 17, 17 Pro, 17 Pro Max, 17e and Air. Agents are
> using `name=iPhone 17`, which is the interpretation that lets verification actually run.
> The owner needs to decide whether `CLAUDE.md` §5 and CI keep pinning a device that no
> longer exists, pin a generic `platform=iOS Simulator,OS=latest` destination instead, or fix
> the fleet. Until then a fresh checkout on a machine with a different Xcode will fail
> verification for a reason that has nothing to do with the code.

> **Open question:** the **Verify** lines for `E08-02`, `E08-03`, `E08-05`, `E08-06` and
> `E08-07` name `-only-testing:BlindDropTests/…`. `BlindDropTests/` is the directory on disk;
> the three test *targets* are `BlindDropUnitTests`, `BlindDropSnapshotTests` and
> `BlindDropUITests` (`E00-03`). The runnable form is
> `-only-testing:BlindDropUnitTests/<SuiteName>`.

---

### E08-01 — App skeleton, light mode, environment

**Status:** done · **Deps:** E00-03 · **Reads:** `docs/13` §1, §4, §8, `docs/07` (intro)
**Touches:** `App/BlindDropApp.swift`, `App/AppEnvironment.swift`, `App/AppConfiguration.swift`,
`App/RootView.swift`, `App/Route.swift`, `App/Router.swift`, `App/DeepLink.swift`,
`Core/Auth/SessionStore.swift`, `Core/Time/ServerClock.swift`, `Core/Networking/APIClient.swift`,
`Features/{Onboarding,Round,Record,Settings}/*Screen.swift`,
`BlindDropTests/Unit/{DeepLinkTests,RoutingTests,AppConfigurationTests}.swift`
**Verify:** app launches to a placeholder in the simulator —
`xcodebuild test -scheme BlindDrop -destination 'platform=iOS Simulator,name=iPhone 17'`
(`PlaceholderUITests.testAppLaunches` launches with `-apiBaseURL` and asserts
`.runningForeground`; the routing, configuration and deep-link rules are unit-tested so none
of this is a manual check — `CLAUDE.md` §7)

- [x] `.preferredColorScheme(.light)` at the root; **no** `colorScheme` branching anywhere
- [x] `AppEnvironment` is the composition root and the only singleton, injected via
      `.environment(_:)` — deliberately **no** `static let shared`
- [x] `-apiBaseURL` launch argument honoured so tests point at the fixture server
- [x] `RootView` routes on session state per `docs/13` §4
- [x] `NavigationStack` with a typed path; two destinations, one modal. **No tab bar.**
- [x] `blinddrop://` parsing for the four routes in `docs/05` §5, stored as `pendingRoute`
      and consumed only after the round loads

Notes for the tasks that build on this:

- `SessionState` carries a fifth case, `.unknown`, on top of `docs/13` §4's four. It is
  `docs/13` §5 rule 3 — "before the first response the app does not know" — applied to
  identity: the root renders nothing rather than guessing `.signedOut` and showing a sign-in
  wall to a signed-in user. E09-01 attaches the real transitions.
- `ServerClock` and `APIClient` land here as shapes only, so the composition root does not
  have to be rewritten by `E08-05`/`E08-06`. Both are one-line constructors with the wiring
  (`APIClient` holds the *same* `ServerClock` instance every countdown reads) already correct.
- `Router.consume(session:roundIsLoaded:)` is deliberately **not** given the round's phase.
  `docs/05` §5 says a link never shortcuts a phase gate, and a phase parameter is the standing
  temptation to gate on it. `.results` therefore pops to the root exactly like `.round` — the
  server decides what renders.
- The placeholder screens carry no copy. `docs/11` owns every string; inventing one to fill a
  blank screen is how strings get written outside the copy deck.

---

### E08-02 — Palette and contrast test

**Status:** done · **Deps:** E08-01 · **Reads:** `docs/07` §2
**Touches:** `DesignSystem/Palette.swift`, `BlindDropTests/Unit/PaletteContrastTests.swift`
**Verify:** `xcodebuild test -only-testing:BlindDropTests/PaletteContrastTests`

Transcribe the tokens exactly. Write the WCAG relative-luminance function and assert every
row of the `docs/07` §2 contrast table.

- [x] All tokens present with the exact hex values
- [x] Contrast test covers all ten rows and fails loudly if a hex changes
- [x] Doc comments record the three amber tiers and their jobs: `amber` fills, `amberDeep`
      draws, `amberText` writes
- [x] Doc comment on `alert`: errors only, never a game state
- [x] No `Color(light:dark:)` anywhere

---

### E08-03 — Typography and font bundling

**Status:** done · **Deps:** E08-01 · **Reads:** `docs/07` §3, `docs/12` §1
**Touches:** `DesignSystem/Typography.swift`, `Resources/Fonts/BricolageGrotesque.ttf`,
`Resources/Fonts/OFL.txt`, `Info.plist`, `BlindDropTests/Unit/TypographyTests.swift`
**Verify:** `xcodebuild test -only-testing:BlindDropUnitTests/TypographyTests`

- [x] Bricolage Grotesque variable font bundled and registered; `wdth` axis set to the widest
      cut the face carries — see the resolution below
- [x] The eleven `TypeStyle` cases from `docs/07` §3
- [x] Every style scales with Dynamic Type via `UIFontMetrics` / `ScaledMetric`
- [x] **Tabular figures on every mono style and every display numeral**
- [x] Display face capped at 1.6× scale (`docs/12` §1) — the one allowed scaling limit
- [x] Countdown switches to the coarse form above `.accessibility2` (`docs/12` §1)
- [x] Test: the display face actually loaded — assert the resolved font name is not SF Pro

**Resolved** (owner, 2026-08-11): `docs/07` §3 asked for `wdth 110` and Bricolage Grotesque's
width axis runs **75…100** — the shipped variable font (Google Fonts and ateliertriay ship the
same 408KB file) has no 110, so no build could honour the number as written. The rule is now
*the widest cut the face carries*, **read off the font** rather than transcribed: the numerals
are set at 100 today, and a release that widens the axis is picked up with no code change.
`docs/07` §3 is updated to say so, and `TypographyTests.theDisplayFaceIsSetOnItsAxes` asserts
both halves — the axis is at its own maximum, and that maximum is still the number the doc
records, so a font swap that quietly narrows the family fails the build.

Two smaller calls, also confirmed: the `opsz` axis is set to the size the glyphs are actually
drawn at (the file's 96pt default would set a 28pt screen title in spacing designed for a
poster), now documented in `docs/07` §3; and each style scales along a named Dynamic Type ramp
(`largeTitle` for the display face, `body` for body text) rather than all of them riding
`.body`, which is what keeps the 1.6× ceiling from being the only thing holding the display
face down.

---

### E08-04 — Component library

**Status:** wip · **Deps:** E08-02, E08-03 · **Reads:** `docs/07` §4–5, `docs/12` §2–5
**Touches:** `DesignSystem/Components/*`, `DesignSystem/Space.swift`, `DesignSystem/Haptics.swift`,
`BlindDropTests/Snapshot/SnapshotRenderer.swift`
**Verify:** `xcodebuild test -only-testing:BlindDropSnapshotTests` — one snapshot per component
at `{large, accessibility1, accessibility5}`

**Resolved** (owner, 2026-08-11): this task's **Verify** was snapshot tests, and the snapshot
harness is `E08-07`, which depends on `E08-04` — the two could not both go first. The renderer
moves **into this task** (it needs no component to exist), and `E08-07` keeps everything built
on top of it. The checklists below reflect that; the numbering is unchanged.

Ten components from `docs/07` §5. Build them with their accessibility from `docs/12` §2 —
retrofitting VoiceOver later means rebuilding the view hierarchy.

- [ ] The renderer, first: draws a view at a given device size and Dynamic Type size and diffs
      it against a golden PNG. Hand-rolled, no third-party snapshot library (`docs/13` §1).
      `E08-07` builds the matrix, the diff output and the dark-mode test on top of it
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

**Status:** done · **Deps:** E08-01 · **Reads:** `docs/13` §3, §6, `docs/04` §1–6
**Touches:** `Core/Networking/*`, `Core/Auth/SessionStore.swift` (token, refresh, sign-out —
the three things `APIClient` calls on a 401), `Core/Time/ServerClock.swift` (the anchor, so
`Envelope`'s `server_now` has somewhere to land — the rest of `docs/13` §5 is E08-06),
`BlindDropTests/Unit/NetworkingTests.swift`
**Verify:** `xcodebuild test -only-testing:BlindDropUnitTests/NetworkingTests`

- [x] `APIClient` is an `actor`; DTOs are `Sendable` value types
- [x] Every response passes through `Envelope<T>`, which feeds `server_now` to `ServerClock`
      **before** returning the payload — including failure envelopes, which carry it too
- [x] `RoundDTO.Phase` is an enum with associated values, decoding **only** that phase's keys
      — a view holding an `open` round must be unable to reach `cards` (`docs/13` §3)
- [x] Every error code from `docs/04` §1 mapped to `APIError`, with the **copy-deck key** it
      renders through — see the note below
- [x] `waitsForConnectivity = false` — fast honest failures
- [x] Retry: idempotent GETs twice (200/600ms); the two idempotent PUTs once; nothing else,
      and only for transport failures and 5xx — a 409 is not a flake
- [x] `X-Storefront` on every request
- [x] `LoadState` includes a `.stale(T, APIError)` case so no screen can forget the
      cached-data path, with the transition written once on `LoadState.apply(_:)`
- [x] Every endpoint in `docs/04` §2–§6 is a `static` on `Endpoint`, so no screen builds a URL

Notes:

- **`APIError` carries the copy *key*, not the string.** The checklist says "with its
  copy-deck string"; the strings live in `Localizable.strings` (E09-01) and putting them here
  too would make this file a second, untranslated copy of `docs/11` — the exact drift the copy
  deck exists to prevent. `APIError.copyKey` is asserted against `docs/11` in
  `NetworkingTests`, so the mapping is still pinned by test.
- Two client-side cases sit beside the fourteen server ones: `.offline` (the request never
  left the phone — `docs/11` `error.offline`) and `.unreadable` (a body that is not our
  envelope). A raw `URLError` or `DecodingError` never reaches a view.
- `SessionStore.refreshCredentials()` returns `false` until E09-01 attaches Sign in with
  Apple. That is not a stub standing in for success: with no refresh token to spend it is the
  correct answer, and it makes `APIClient`'s "refresh once, then sign out" path reachable and
  tested today.

---

### E08-06 — `ServerClock` and the `Date()` lint

**Status:** done · **Deps:** E08-05 · **Reads:** `docs/13` §5, `docs/15` AC-2
**Touches:** `Core/Time/ServerClock.swift`, `Core/Time/CountdownTimer.swift`,
`BlindDropTests/Unit/ServerClockTests.swift`, `docs/11-COPY-DECK.md`
**Verify:** `xcodebuild test -only-testing:BlindDropUnitTests/ServerClockTests`

This type is the client half of AC-2. Read `docs/13` §5 carefully; all six rules are testable.

- [x] Anchored to `ProcessInfo.systemUptime`, **not** `Date()`
- [x] `now` is **optional** — before the first response the app doesn't know the time and
      says `--:--:--` rather than guessing
- [x] Re-anchors on every response — `APIClient` does it from every envelope, failures included
- [x] Anchor invalidated on `willEnterForeground`; a refetch precedes any countdown render
      (`RootView` already invalidates on `.active`, E08-01)
- [x] Group-local formatting uses the **group's** timezone, never `TimeZone.current` —
      `GroupCalendar`, whose fallback for an unknown identifier is UTC rather than the device
- [x] Lint rule: `Date()` outside this file fails CI — `ios/scripts/lint.sh` rule 1 (E00-04),
      **and** `ServerClockTests` scans the tree itself, because `docs/15` §7 wants a passing
      test rather than a script somebody might not run
- [x] Tests: ±5-year device-clock shift changes nothing; timezone change changes nothing;
      stale anchor returns `nil`; drift over a simulated 2h session is not just under a second
      but exactly zero — `now` is computed from the anchor, never accumulated

Notes:

- `CountdownTimer` publishes a **value**, `CountdownDisplay`, not a formatted string: the words
  are `docs/11`'s and the view applies them. Its tick follows the form — one second for
  `HH:MM:SS`, one minute for the coarse form, because a one-second tick behind a "3 hours"
  label wakes the CPU 3,599 times to render the same string.
- Four copy-deck rows were added for the countdown itself (`countdown.unknown`,
  `countdown.coarse.hours|minutes|soon`). `docs/12` §1 quotes those words and `docs/11` did not
  have them; `CLAUDE.md` §6 says add them in the same commit rather than invent them at the
  call site. The plural of `%lld hours` needs a `.stringsdict` — flagged as an open question
  there, for E09, since the singular wording is a voice decision.
- `hasElapsed` is deliberately a three-state `Bool?` and the screen refetches on `true`. A
  countdown reaching zero is **not** a phase transition (`CLAUDE.md` §2.2) — the server says
  what happens next, and a client that flipped its own state at zero would show a reveal that
  had not happened.

---

### E08-07 — Snapshot test harness

**Status:** todo · **Deps:** E08-04 · **Reads:** `docs/15` §3, `docs/12` §8
**Touches:** `BlindDropTests/Snapshot/*`
**Verify:** `xcodebuild test -only-testing:BlindDropSnapshotTests`

Hand-rolled against golden PNGs — no third-party snapshot library (zero dependencies). The
renderer itself lands in `E08-04`, which needs it to verify; this task is everything built on
top of it.

- [ ] Matrix helper: `{SE, 15 Pro Max} × {large, accessibility1, accessibility5}`
- [ ] Failure writes the actual and the diff into a reviewable directory
- [ ] `RECORD_SNAPSHOTS=1` regenerates goldens
- [ ] A test that renders with the OS in dark mode and asserts output is identical to light —
      this is how "light mode only" stays true
