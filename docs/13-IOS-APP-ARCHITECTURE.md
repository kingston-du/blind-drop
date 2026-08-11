# 13 — iOS app architecture

Swift 6, strict concurrency, iOS 17.0 minimum. SwiftUI only. **Zero third-party
dependencies** except the bundled Bricolage Grotesque font file.

---

## 1. File tree

```
ios/
├── BlindDrop.xcodeproj
├── BlindDrop/
│   ├── App/
│   │   ├── BlindDropApp.swift          @main, .preferredColorScheme(.light)
│   │   ├── AppEnvironment.swift        composition root; the only singleton
│   │   ├── RootView.swift              routes on session + round state
│   │   └── DeepLink.swift              blinddrop:// parsing
│   │
│   ├── Core/
│   │   ├── Networking/
│   │   │   ├── APIClient.swift         URLSession, envelope, retry, auth header
│   │   │   ├── APIError.swift          error codes from docs/04 §1
│   │   │   ├── Endpoints.swift         one function per route
│   │   │   └── DTO/                    Codable mirrors of docs/04 payloads
│   │   │       ├── RoundDTO.swift
│   │   │       ├── TrackDTO.swift
│   │   │       ├── ResultsDTO.swift
│   │   │       ├── GroupDTO.swift
│   │   │       └── RecordDTO.swift
│   │   ├── Time/
│   │   │   ├── ServerClock.swift       THE clock. See §5.
│   │   │   └── CountdownTimer.swift    1Hz publisher driven by ServerClock
│   │   ├── Auth/
│   │   │   ├── SessionStore.swift      Supabase session, refresh, sign out
│   │   │   ├── AppleSignIn.swift       ASAuthorizationController wrapper
│   │   │   ├── Keychain.swift          minimal wrapper, no dependency
│   │   │   └── SpotifyAuth.swift       PKCE + ASWebAuthenticationSession
│   │   ├── Audio/
│   │   │   └── PreviewPlayer.swift     AVPlayer, one at a time, session lifecycle
│   │   ├── Push/
│   │   │   ├── PushRegistrar.swift     APNs token → POST /devices
│   │   │   └── PushRouter.swift        payload → DeepLink
│   │   └── Persistence/
│   │       └── LocalFlags.swift        hasSeenUnseal(roundId), hasSeenResultsReveal
│   │
│   ├── DesignSystem/
│   │   ├── Palette.swift               docs/07 §2
│   │   ├── Typography.swift            docs/07 §3
│   │   ├── Space.swift                 Space, Radius, Stroke
│   │   ├── Haptics.swift
│   │   ├── Motion/
│   │   │   ├── SealAnimation.swift     docs/09 §2
│   │   │   ├── UnsealAnimation.swift   docs/09 §3
│   │   │   └── MotionTokens.swift      curves, durations, stagger()
│   │   └── Components/
│   │       ├── PrimaryButton.swift
│   │       ├── SecondaryButton.swift
│   │       ├── TrackRow.swift
│   │       ├── FlightCard.swift
│   │       ├── SealedCard.swift
│   │       ├── NameChip.swift
│   │       ├── CountdownView.swift
│   │       ├── StatMeter.swift
│   │       ├── ArtworkView.swift       template URL sizing + placeholder
│   │       └── EmptyState.swift
│   │
│   ├── Features/
│   │   ├── Onboarding/
│   │   │   ├── OnboardingFlow.swift
│   │   │   ├── OnboardingStore.swift
│   │   │   ├── SignInScreen.swift
│   │   │   ├── DisplayNameScreen.swift
│   │   │   ├── JoinOrCreateScreen.swift
│   │   │   └── CreateGroupScreen.swift
│   │   ├── Round/
│   │   │   ├── RoundScreen.swift       switches on state
│   │   │   └── RoundStore.swift        owns the round, polls, refetches
│   │   ├── Submit/
│   │   │   ├── SubmitScreen.swift
│   │   │   ├── SealedScreen.swift
│   │   │   ├── VoidedScreen.swift
│   │   │   ├── SearchSheet.swift
│   │   │   ├── ConfirmScreen.swift
│   │   │   └── SubmitStore.swift
│   │   ├── Reveal/
│   │   │   ├── RevealScreen.swift
│   │   │   ├── GuessSheet.swift
│   │   │   └── RevealStore.swift       local sheet state + debounced save
│   │   ├── Results/
│   │   │   ├── ResultsScreen.swift
│   │   │   ├── StandingsView.swift
│   │   │   ├── ResultsStore.swift
│   │   │   └── Share/
│   │   │       ├── ShareCardView.swift
│   │   │       ├── ShareRenderer.swift ImageRenderer, both variants
│   │   │       └── ShareHeadline.swift precedence rules, docs/10 §2
│   │   ├── Record/
│   │   │   ├── RecordScreen.swift
│   │   │   ├── RecordStore.swift
│   │   │   └── Export/
│   │   │       ├── SpotifyExporter.swift
│   │   │       └── AppleMusicExporter.swift
│   │   └── Settings/
│   │       ├── GroupSettingsScreen.swift
│   │       └── SettingsStore.swift
│   │
│   └── Resources/
│       ├── Localizable.strings         docs/11
│       ├── Localizable.stringsdict     plurals
│       ├── Fonts/BricolageGrotesque.ttf
│       └── Assets.xcassets             app icon only — no illustrations
│
└── BlindDropTests/
    ├── Unit/
    │   ├── PaletteContrastTests.swift
    │   ├── ScoringFormatTests.swift
    │   ├── ServerClockTests.swift
    │   ├── ShareHeadlineTests.swift
    │   ├── MotionTokenTests.swift
    │   └── A11yLabelTests.swift
    ├── Snapshot/
    │   ├── ScreenSnapshotTests.swift   5 screens × 3 type sizes × 2 devices
    │   └── ShareCardSnapshotTests.swift
    └── UI/
        ├── FullLoopUITests.swift       AC-10, the 90-second loop
        └── ReducedMotionUITests.swift
```

---

## 2. State model

One `@Observable` store per feature, owned by its screen, constructed from
`AppEnvironment`. No global mutable state, no `@EnvironmentObject` soup, no singletons other
than `AppEnvironment` injected via `.environment(_:)`.

```swift
@Observable @MainActor
final class RoundStore {
    private(set) var state: LoadState<RoundDTO> = .idle
    private let api: APIClient
    private let clock: ServerClock

    func load() async { … }
    func refreshIfPhaseElapsed() { … }   // countdown hit zero → refetch
}

enum LoadState<T> { case idle, loading, loaded(T), failed(APIError), stale(T, APIError) }
```

`stale` matters: when a refetch fails and we have cached data, the UI shows the old data with
the offline banner (`08-SCREEN-SPECS.md` §10) rather than blanking. Model it in the enum so no
screen can forget.

### Stores never decide phase

A store may *refetch* when a countdown elapses. It may never set `state` to a different
phase locally. There is exactly one place `RoundDTO.state` is assigned, and it is the decoder.
A code review that finds `round.state = .revealed` anywhere in the client rejects the PR.

---

## 3. Networking

```swift
actor APIClient {
    func send<R: Decodable>(_ endpoint: Endpoint<R>) async throws(APIError) -> R
}
```

- One `URLSession` with `waitsForConnectivity = false` — we want fast honest failures, not a
  spinner that resolves in 40 seconds.
- Every response passes through `Envelope<T>` which extracts `server_now` and feeds it to
  `ServerClock` **before** returning the payload. That is how the clock stays fresh with no
  extra requests.
- Auth header from `SessionStore`. On 401, refresh once, retry once, then sign out.
- Retry policy: idempotent GETs retry twice with 200ms/600ms backoff. `PUT
  /rounds/current/submission` and `PUT …/guesses` are idempotent by design
  (`04-API-CONTRACT.md`) and retry once. Nothing else retries.
- `X-Storefront` header on every request, from `Locale.current.region?.identifier.lowercased()`.

### DTOs mirror the contract exactly

`RoundDTO` uses an enum-with-associated-values for the phase so impossible states are
unrepresentable:

```swift
struct RoundDTO: Decodable {
    let id: String
    let localDate: String
    let opensAt: Date, revealsAt: Date, scoresAt: Date
    let phase: Phase

    enum Phase {
        case open(mySubmission: SubmissionDTO?)
        case voided(mySubmission: SubmissionDTO?)
        case revealed(RevealPayload)
        case scored
    }
}
```

The custom `init(from:)` switches on the `state` string and decodes only that case's keys.
A `revealed` payload's `cards` array is therefore **impossible to access** from a view holding
an `open` round — the compiler enforces the blind window on the client side too.

---

## 4. Routing

```swift
RootView
  switch session {
    case .signedOut:            SignInScreen
    case .noProfile:            DisplayNameScreen
    case .noGroup:              JoinOrCreateScreen
    case .ready:                RoundScreen   // + NavigationStack for Record/Settings
  }
```

`RoundScreen` switches on `round.phase` and nothing else. A deep link sets a `pendingRoute`
that is consumed **after** the round loads, so a link never lands on a phase that isn't
current (`05-JOBS-AND-NOTIFICATIONS.md` §5).

`NavigationStack` with a typed `path: [Route]`. Two destinations, one modal. Do not add a tab
bar.

---

## 5. `ServerClock` — the only source of time

This type is the client half of "server-authoritative time" (AC-2). Read it carefully.

```swift
@Observable @MainActor
final class ServerClock {
    /// Uptime-anchored offset. Immune to the user changing the device clock.
    private var anchor: (uptime: TimeInterval, serverTime: Date)?

    func sync(serverNow: Date) {
        anchor = (ProcessInfo.processInfo.systemUptime, serverNow)
    }

    var now: Date? {
        guard let a = anchor else { return nil }
        let elapsed = ProcessInfo.processInfo.systemUptime - a.uptime
        return a.serverTime.addingTimeInterval(elapsed)
    }

    func timeRemaining(until deadline: Date) -> TimeInterval? {
        now.map { deadline.timeIntervalSince($0) }
    }
}
```

Rules, all testable:

1. **`Date()` appears nowhere outside `ServerClock`** — enforced by a lint rule in CI. Not in
   a view, not in a store, not in a formatter, not in a log.
2. The anchor uses `systemUptime`, **not** `Date()`. `systemUptime` is monotonic and does not
   move when the user changes the clock or the timezone. Setting the device to 2029 changes
   nothing.
3. `now` is **optional**. Before the first successful response the app does not know what time
   it is, and it says so — the countdown shows `--:--:--`, not a guess.
4. Re-anchoring on every response means drift never accumulates.
5. `systemUptime` does not advance while the device is asleep. On `willEnterForeground` the
   anchor is invalidated and a refetch is issued before any countdown renders. Assume the
   anchor is stale after any background period.
6. All group-local formatting (a round's date, "8:00 PM") uses the **group's** timezone from
   `GroupDTO`, never `TimeZone.current`. A user travelling still plays on the group's clock.

`ServerClockTests` asserts: setting a fake device clock ±5 years changes no computed
countdown; a stale anchor after background returns `nil` until resync; drift over a simulated
2-hour session stays under 1 second.

---

## 6. Concurrency

- Swift 6 strict concurrency, no `@preconcurrency` escapes, no `@unchecked Sendable`.
- Stores are `@MainActor`. `APIClient` is an `actor`. DTOs are `Sendable` value types.
- Every `async` call from a view uses `.task(id:)` so it cancels on disappear and re-runs on
  identity change.
- The debounced guess save is one `Task` held by `RevealStore`, cancelled and replaced on each
  edit. Never a detached task, never a timer that outlives the screen.

---

## 7. Offline

- No local database. The app is a thin client to a server-authoritative game; a local cache
  of game state is a correctness hazard, not a feature.
- The in-memory `LoadState.stale` case covers a foreground refetch failure.
- **Mutations are never queued.** A submission that "sends when you reconnect" could land at
  20:01 and be silently rejected — or worse, silently accepted into tomorrow. Offline
  mutations fail immediately and say so (`11-COPY-DECK.md` `search.error.offline`).
- Artwork uses `URLCache` with a 100MB disk cap. That is the only thing cached to disk.

---

## 8. Build configuration

| Setting | Value |
|---|---|
| Deployment target | iOS 17.0 |
| Swift language mode | 6 |
| Supported orientations | Portrait only |
| Supported devices | iPhone only (no iPad layout — `16-OUT-OF-SCOPE.md`) |
| Appearance | `.light` forced at the root |
| Capabilities | Push Notifications, Sign in with Apple, MusicKit (export only), Associated Domains (invite links) |
| URL schemes | `blinddrop` |
| `Info.plist` | `SPOTIFY_CLIENT_ID` (public), `NSAppleMusicUsageDescription` |
| Background modes | **none** — remote notifications are alert-only, no silent pushes |

No `UIBackgroundModes`, no background fetch, no silent push. The app has nothing to do while
backgrounded, and adding a background mode is how an app starts feeling like it's watching
you.

---

## 9. Anti-patterns that will be rejected in review

- `Date()` outside `ServerClock`
- A raw hex, font size, or spacing literal in `Features/`
- `round.state` assigned anywhere but the decoder
- A `submissionCount`, `hasSubmitted`, or `participants` field on any `open`-phase model
- A third-party package
- A drop shadow outside the moving seal cover
- A tab bar
- `@unchecked Sendable`
- A string literal in a view instead of a `Localizable.strings` key
- `DispatchQueue.main.asyncAfter` used to sequence an animation
