import SwiftUI

private struct ForcedReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Test-only override layered on top of the real system accessibility preference. The
    /// default is false, so production behavior continues to be driven entirely by iOS.
    var blindDropForcesReducedMotion: Bool {
        get { self[ForcedReduceMotionKey.self] }
        set { self[ForcedReduceMotionKey.self] = newValue }
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
