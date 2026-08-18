import SwiftUI

private struct ForcedReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

private struct SnapshotRenderKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Test-only override layered on top of the real system accessibility preference. The
    /// default is false, so production behavior continues to be driven entirely by iOS.
    var blindDropForcesReducedMotion: Bool {
        get { self[ForcedReduceMotionKey.self] }
        set { self[ForcedReduceMotionKey.self] = newValue }
    }

    /// True only inside `SnapshotRenderer`, which draws with `ImageRenderer`.
    ///
    /// **`ImageRenderer` cannot rasterise a `Menu`.** It draws a yellow placeholder with a red
    /// slash through it instead — the same class of hole as the `ScrollView` one `GuessSheet`
    /// documents, and worse in its consequences, because a `ScrollView` renders as nothing while
    /// a `Menu` renders as something that looks deliberate. Left alone it bakes an error box into
    /// every answer-card golden and blinds that corner of the card to every future regression.
    ///
    /// A `Menu` has no appearance of its own; its appearance is its label, which is an ordinary
    /// glyph that renders fine. So under this flag `TrackUtilityMenu` draws the label and not the
    /// container — the goldens then show exactly what the device shows, and the one thing they do
    /// not cover is the presentation, which is a picture's business least of all. `ComponentTests`
    /// is what proves the menu's *items* are the right ones.
    var blindDropRendersForSnapshot: Bool {
        get { self[SnapshotRenderKey.self] }
        set { self[SnapshotRenderKey.self] = newValue }
    }
}

/// docs/07: **light mode only**. There is no dark mode in v1, no `colorScheme` branching,
/// and no `Color(light:dark:)` constructors. This is the one place the appearance is set.
///
/// `@MainActor` on the conformer is load-bearing: `AppEnvironment` is main-actor isolated, so
/// its initialiser cannot run from a non-isolated stored-property initialiser under Swift 6
/// strict concurrency. Annotating here is the least-surprising fix — a `nonisolated init` on
/// `AppEnvironment` would only move the same problem down to `ServerClock`.
@main
@MainActor
struct BlindDropApp: App {
    /// The one instance. Injected by type with `.environment(_:)` and read back with
    /// `@Environment(AppEnvironment.self)` — never `@EnvironmentObject`, and never a static
    /// `shared` (`docs/13` §2).
    @State private var env = AppEnvironment()

    /// The two APNs callbacks SwiftUI has no equivalent for (`docs/05` §4). It holds no state and
    /// makes no decisions; `attach(_:)` below is how it reaches the environment without a global.
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate

    var body: some Scene {
        WindowGroup {
            configuredRoot
                .environment(env)
                .preferredColorScheme(.light)
                .task(id: env.session.state) {
                    pushDelegate.attach(env)
                    // APNs may return a token immediately. Do not ask for one until `GET /me`
                    // has established an authenticated, profiled session: a token sent while the
                    // Keychain session is still loading would receive a 401 and could end that
                    // otherwise-valid session. The state change reruns this task after launch and
                    // after sign-in.
                    guard env.session.state == .noGroup || env.session.state == .ready else {
                        return
                    }
                    // `docs/05` §4: `POST /devices` on every authenticated launch, a cheap upsert
                    // that refreshes `last_seen_at`. It **never prompts**.
                    await env.push.registerIfAuthorized()
                }
                // docs/05 §5: a deep link is a navigation hint, not an authorization. It is
                // stored here and applied only after the round has loaded.
                .onOpenURL { url in env.router.receive(DeepLink(url)) }
                // The invite universal link, `https://blinddrop.app/j/<CODE>` (`docs/05` §5).
                // A different door into the same room: it goes through the same parser and the
                // same router, so it cannot end up meaning something the custom scheme does not.
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    env.router.receive(DeepLink(url))
                }
        }
    }

    @ViewBuilder private var configuredRoot: some View {
        #if DEBUG
        if env.configuration.forcesReducedMotionForUITests {
            RootView().environment(\.blindDropForcesReducedMotion, true)
        } else {
            RootView()
        }
        #else
        RootView()
        #endif
    }
}
