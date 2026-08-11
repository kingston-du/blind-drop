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

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .preferredColorScheme(.light)
                // docs/05 §5: a deep link is a navigation hint, not an authorization. It is
                // stored here and applied only after the round has loaded.
                .onOpenURL { url in env.router.receive(DeepLink(url)) }
        }
    }
}
