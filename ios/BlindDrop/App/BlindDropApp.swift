import SwiftUI

/// docs/07: **light mode only**. There is no dark mode in v1, no `colorScheme` branching,
/// and no `Color(light:dark:)` constructors. This is the one place the appearance is set.
@main
struct BlindDropApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)
        }
    }
}
