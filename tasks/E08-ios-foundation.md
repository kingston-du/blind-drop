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

> **Open question:** `docs/07` §5 gives `StatMeter` *"five band labels below in `caption`
> `inkFaint`, with the active band in `ink`"*; `docs/08` §7.2 draws the same component with
> **one** label — *"open book"* under the marker. The five strings measure 320pt at `caption`'s
> 12pt and an iPhone SE has 335pt of content width, so five never fit there at any text size,
> and the equal-width columns that make them "fit" break *"Unreadable"* mid-word. `E08-04`
> renders five where the width allows and the active band alone otherwise, via `ViewThatFits`.
> The owner should decide whether the five-label spectrum is worth a smaller type style on the
> labels, or whether `docs/07` §5 should be amended to `docs/08` §7.2's single label.

> **Open question:** `docs/07` §5 specifies `TrackRow`'s title as *"1 line, truncating"*;
> `docs/12` §1 says *"nothing truncates and nothing overlaps at `.accessibility5` on an iPhone
> SE"* and `docs/12` §8 wants an assertion that no `Text` reports a truncated layout. At
> `.accessibility5` a one-line row truncates *"Motion Sickness"* to *"Motion…"*, so the two
> cannot both hold. `E08-04` reads each as governing its own case: one truncating line at the
> reading sizes, where the row is being scanned and a wrapping title turns a scannable list
> into a paragraph, and unbounded wrapping from `.accessibility1` up, where the reader needs
> the title more than they need the list to be short. The owner should confirm, because the
> alternative — truncating at every size and letting `docs/12`'s assertion carve out an
> exception for this row — is also defensible and is a smaller change.

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

**Status:** done · **Deps:** E08-02, E08-03 · **Reads:** `docs/07` §4–5, `docs/12` §2–5
**Touches:** `DesignSystem/Components/*`, `DesignSystem/Space.swift`, `DesignSystem/Haptics.swift`,
`DesignSystem/PhaseAccent.swift`, `DesignSystem/Copy.swift`, `Resources/Localizable.strings`,
`App/AppEnvironment.swift`, `BlindDropTests/Snapshot/{SnapshotRenderer,ComponentSnapshotTests}.swift`,
`BlindDropTests/Unit/ComponentTests.swift`, `BlindDropTests/__Snapshots__/Components/*`,
`docs/11-COPY-DECK.md`
**Verify:** `xcodebuild test -only-testing:BlindDropSnapshotTests` — one snapshot per component
at `{large, accessibility1, accessibility5}` — plus
`-only-testing:BlindDropUnitTests/ComponentRules` and `…/AccessibilityCopyTests` for the parts
that are rules rather than pixels

**Resolved** (owner, 2026-08-11): this task's **Verify** was snapshot tests, and the snapshot
harness is `E08-07`, which depends on `E08-04` — the two could not both go first. The renderer
moves **into this task** (it needs no component to exist), and `E08-07` keeps everything built
on top of it. The checklists below reflect that; the numbering is unchanged.

Ten components from `docs/07` §5. Build them with their accessibility from `docs/12` §2 —
retrofitting VoiceOver later means rebuilding the view hierarchy.

- [x] The renderer, first: draws a view at a given device size and Dynamic Type size and diffs
      it against a golden PNG. Hand-rolled, no third-party snapshot library (`docs/13` §1).
      `E08-07` builds the matrix, the diff output and the dark-mode test on top of it
- [x] `PrimaryButton` takes the phase accent as a parameter, never hardcodes it
- [x] `FlightCard` is a **single** accessibility element with the preview control as a nested
      child and a custom action
- [x] `StatMeter` renders a marker, **no fill from the left** — filling implies more is better
- [x] `NameChip` consumed state carries both opacity and an accessibility value change
- [x] `ArtworkView` substitutes `{w}x{h}` at the sizes in `docs/06` §2.1 × display scale,
      capped at 1200, with the `artwork_bg_color` placeholder at 12%
- [x] `CountdownView` takes a `ServerClock`, never `Date()`
- [x] No shadows on any component
- [x] Every interactive element ≥ 44×44 `contentShape`

Notes:

- **`PhaseAccent` is the type that keeps "one accent per screen" true.** Every component takes
  one; none reaches into `Palette` for amber or ultramarine. `PhaseAccent(_ state:)` maps
  `docs/07` §6, so a screen holding a `RoundDTO` never has to remember that `voided` is amber.
- **An eleventh file, `PreviewControl`, joins the ten.** It is a *part* of `TrackRow` and
  `FlightCard` rather than a component of its own — `docs/12` §2 gives it its own VoiceOver row,
  which is the clearest sign it is one thing and not two copies of thirty lines.
- **`Resources/Localizable.strings` starts here**, not at `E09-01`. `docs/12` §2 requires
  components to build their own VoiceOver labels, and a label is a string; the alternative was
  hardcoding words a component's file, which is what `docs/11` exists to prevent. Only the rows
  `DesignSystem/` renders are in it. Seven VoiceOver rows `docs/12` §2 specified in prose but
  never gave keys — the two hints, the two name-chip states, the assignment announcement, the
  track-row label, and the clear-guess action — were added to `docs/11` in the same commit
  (`CLAUDE.md` §6). Lint rules 7 and 8 are live from now on.
- **Two spec details came from `docs/08` rather than `docs/07` §5**, and both change what the
  component draws: the caller's own card renders *"Yours"* as a plain `amberText` label and not
  a chip — §6's *"the ONE place amber appears here, because your card is still your secret"* —
  and an assigned card's chip carries a `✕`, exposed to VoiceOver as a named action so no
  gesture is the only way to do anything (`docs/12` §5).
- `SealedCard` draws the **landed** state of `docs/09` §2 rather than the animation, so
  `E10-04` has an end state to animate *to* instead of being the only place a sealed card
  exists. Its `coverage` parameter is the seam the animation drives.
- `ArtworkLoading` is a protocol with a **synchronous** cache read on it, because a view has to
  answer "do I have this already" while building its body. That is also what makes the
  snapshots deterministic: `ImageRenderer` never runs `.task`, so a rendered artwork is one the
  test put in the cache and nothing else.
- Three layout facts were found by looking at the goldens, not by reading the spec, and each is
  now a comment where it was fixed: `FlightCard` reserves a two-digit number column measured off
  the font (otherwise the artwork edge is ragged down a twelve-card list); its assignment chip
  sits below the artwork row indented to the artwork's edge, where `docs/08` §6 draws it, because
  the metadata column is narrower than *"Who dropped this?"*; and at `.accessibility1` the whole
  card stacks — the artwork leaves the row with the number — because an 88pt thumbnail beside the
  text leaves the title a column narrower than the word *Sickness*, and a column narrower than a
  word does not wrap, it breaks mid-word.
- `RECORD_SNAPSHOTS=1` must be exported to `xcodebuild` as **`TEST_RUNNER_RECORD_SNAPSHOTS=1`**.
  `xcodebuild` forwards only `TEST_RUNNER_`-prefixed variables into the simulator, with the
  prefix stripped. A bare `RECORD_SNAPSHOTS=1` and a trailing
  `TEST_RUNNER_RECORD_SNAPSHOTS=1` *argument* both fail the same quiet way — the goldens are
  written anyway, because a missing golden is always written, but every test reports the failure
  that says it happened.

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

**Status:** done · **Deps:** E08-04 · **Reads:** `docs/15` §3, `docs/12` §8
**Touches:** `BlindDropTests/Snapshot/{SnapshotRenderer,ComponentSnapshotTests,
LightModeOnlySnapshotTests}.swift`, `BlindDropTests/__Snapshots__/Components/*` (60 goldens),
`.gitignore`
**Verify:** `xcodebuild test -only-testing:BlindDropSnapshotTests`

Hand-rolled against golden PNGs — no third-party snapshot library (zero dependencies). The
renderer itself lands in `E08-04`, which needs it to verify; this task is everything built on
top of it.

- [x] Matrix helper: `{SE, 15 Pro Max} × {large, accessibility1, accessibility5}`
- [x] Failure writes the actual and the diff into a reviewable directory
- [x] `RECORD_SNAPSHOTS=1` regenerates goldens
- [x] A test that renders with the OS in dark mode and asserts output is identical to light —
      this is how "light mode only" stays true

Notes:

- **The matrix is 60 goldens** — ten components × two devices × three sizes. `SE` is 375pt at
  2× and is where every layout that breaks breaks first (`docs/12` §1, §8); `15 Pro Max` is
  430pt at 3× and catches the opposite failure, a layout that only looked right because it was
  cramped, and a `ViewThatFits` that should have taken its wide branch. Neither boots a
  simulator: a `Device` here is a width and a scale, so the goldens do not depend on which
  device the suite happened to run on.
- **Failures write `.actual.png`, `.expected.png` and `.diff.png`** into
  `__Snapshots__/__Failures__/`, git-ignored, with the path printed in the issue. The diff is
  the golden at half strength with the differing pixels in `alert` red — the first question
  about a snapshot failure is *where on the card*, and a percentage in a log cannot answer it.
  Verified by breaking a golden two ways: a size change (writes actual and expected, no diff —
  there is nothing to overlay) and a pixel change (writes all three).
- **The dark-mode test compares two renders, not a render and a golden**, at zero tolerance on
  both axes. Goldens can be re-recorded and a re-record with a bug in it would take the
  assertion with it; two renders in the same process cannot drift apart for any reason except
  the thing being tested. It catches what `lint.sh` rule 4 and `PaletteContrastTests`' source
  scan cannot: a system semantic colour — `Color.primary`, an unstyled control's tint, a
  `Material` — carries a dark appearance with the word `colorScheme` nowhere near it.
- **`theDarkModeCheckCanFail` is a control**, and it is the reason the nine assertions above it
  mean anything. It renders `Color.primary` and requires the two appearances to *differ*. If it
  ever passes at zero difference, the environment is not reaching `ImageRenderer` and every
  light-mode assertion has quietly become a comparison of two identical light renders.
- `RECORD_SNAPSHOTS` must reach `xcodebuild` as **`TEST_RUNNER_RECORD_SNAPSHOTS=1`** — see the
  note on `E08-04`, and the doc comment on `SnapshotRenderer.isRecording`.
- The renderer pins the width **before** applying the `paper` background. With `isOpaque` on,
  a background sized to the content's intrinsic width leaves the rest of the frame black; the
  first countdown golden was a strip of amber digits between two black bars.
