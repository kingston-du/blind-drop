import SwiftUI

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
            RootView()
                .environment(env)
                .preferredColorScheme(.light)
                .task {
                    pushDelegate.attach(env)
                    // `docs/05` §4: `POST /devices` on every launch, a cheap upsert that refreshes
                    // `last_seen_at`. It **never prompts** — a launch that asked for notification
                    // permission is the thing that section exists to forbid.
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
}
