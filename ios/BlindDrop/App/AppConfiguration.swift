import Foundation

/// docs/13 §8. The one thing about the app that changes between the simulator, the fixture
/// server, and production. Everything else about a build is a compile-time setting.
///
/// A value type on purpose: `AppEnvironment` takes it as an initialiser argument, so a test
/// can build a second, fixture-pointed environment without touching process-wide state.
struct AppConfiguration: Sendable, Equatable {
    let apiBaseURL: URL

    /// The launch-argument key. `-apiBaseURL http://127.0.0.1:8787` in the UI test scheme
    /// points the app at `ios/Fixtures/server.ts` (E00-05).
    static let apiBaseURLKey = "apiBaseURL"

    /// docs/04 intro: `https://<project>.supabase.co/functions/v1`. The project ref is not
    /// assigned yet (it lands with the release checklist, E14-05); until then the fixture
    /// server is the only address that actually resolves.
    static let productionAPIBaseURL = URL(string: "https://project.supabase.co/functions/v1")!

    /// Foundation folds `-key value` launch arguments into `UserDefaults`' `NSArgumentDomain`
    /// before any of our code runs, so we read the key rather than hand-scanning
    /// `CommandLine.arguments`. That also lets a developer set it in the scheme's Arguments
    /// tab, and it keeps the fixture server invisible to the rest of the app.
    ///
    /// `defaults` is a parameter, not a hardcoded `.standard`, so `AppConfigurationTests` can
    /// prove the override works without mutating the test runner's own defaults.
    static func resolve(_ defaults: UserDefaults = .standard) -> AppConfiguration {
        guard let raw = defaults.string(forKey: apiBaseURLKey),
              let url = URL(string: raw),
              // A bare word parses as a relative URL and would silently produce a request to
              // nowhere. Requiring a scheme turns a typo into "use production", not "hang".
              url.scheme != nil
        else {
            return AppConfiguration(apiBaseURL: productionAPIBaseURL)
        }
        return AppConfiguration(apiBaseURL: url)
    }
}
