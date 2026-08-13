import Foundation

/// docs/13 §8. The one thing about the app that changes between the simulator, the fixture
/// server, and production. Everything else about a build is a compile-time setting.
///
/// A value type on purpose: `AppEnvironment` takes it as an initialiser argument, so a test
/// can build a second, fixture-pointed environment without touching process-wide state.
struct AppConfiguration: Sendable, Equatable {
    let apiBaseURL: URL
    /// Supabase Auth (`docs/14` §5) — a *sibling* of the functions base, not a path under it.
    /// Derived from `apiBaseURL` by default so there is one address to point at a fixture or a
    /// project, and one launch argument to override when they ever diverge.
    let authBaseURL: URL
    /// The publishable anon key, sent as `apikey` on the auth calls. Public by design
    /// (`docs/14` §4, §6): it grants nothing on its own. Empty in a fixture run, where there
    /// is no gate to satisfy.
    let anonKey: String
    /// Spotify's public app identifier. It is not a credential; PKCE is what lets a mobile
    /// client use it without carrying a client secret (`docs/06` §6).
    let spotifyClientID: String
    /// Debug UI tests can begin with a fixture-issued bearer rather than trying to automate
    /// Apple's system-owned sign-in sheet. `RootView` only consults this under `#if DEBUG`, so
    /// Release/TestFlight builds have no session-bypass path even if an argument is supplied.
    let usesFixtureSession: Bool
    /// The reduced-motion full-loop variant is injected at the SwiftUI environment boundary.
    /// Like `usesFixtureSession`, this is ignored by Release builds.
    let forcesReducedMotionForUITests: Bool
    /// Opens the archive directly for its isolated accessibility walk. Debug-only at resolution.
    let opensRecordForUITests: Bool

    /// The launch-argument key. `-apiBaseURL http://127.0.0.1:8787` in the UI test scheme
    /// points the app at `ios/Fixtures/server.ts` (E00-05).
    static let apiBaseURLKey = "apiBaseURL"
    static let authBaseURLKey = "authBaseURL"
    static let anonKeyKey = "supabaseAnonKey"
    static let spotifyClientIDKey = "spotifyClientID"

    /// `authBaseURL` and `anonKey` default off `apiBaseURL` and the bundle, so every existing
    /// call site — and every test that only cares about the API address — keeps working.
    init(
        apiBaseURL: URL,
        authBaseURL: URL? = nil,
        anonKey: String = "",
        spotifyClientID: String = "",
        usesFixtureSession: Bool = false,
        forcesReducedMotionForUITests: Bool = false,
        opensRecordForUITests: Bool = false
    ) {
        self.apiBaseURL = apiBaseURL
        self.authBaseURL = authBaseURL ?? Self.deriveAuthBaseURL(from: apiBaseURL)
        self.anonKey = anonKey
        self.spotifyClientID = spotifyClientID
        self.usesFixtureSession = usesFixtureSession
        self.forcesReducedMotionForUITests = forcesReducedMotionForUITests
        self.opensRecordForUITests = opensRecordForUITests
    }

    /// `…/functions/v1` → `…/auth/v1`; anything else gets `/auth/v1` appended.
    ///
    /// Supabase puts the two services side by side under the project host, so the auth address
    /// is not reachable by appending to the functions one — `…/functions/v1/auth/v1` is a 404,
    /// and it is the mistake this function exists to make impossible.
    static func deriveAuthBaseURL(from api: URL) -> URL {
        let functions = "/functions/v1"
        var path = api.path
        while path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix(functions) { path.removeLast(functions.count) }

        guard var components = URLComponents(url: api, resolvingAgainstBaseURL: false) else {
            return api.appending(path: "auth/v1")
        }
        components.path = path + "/auth/v1"
        return components.url ?? api.appending(path: "auth/v1")
    }

    /// docs/04 intro: the hosted production Edge Functions root.
    static let productionAPIBaseURL = URL(
        string: "https://ojzwgaffeegssfscoaiv.supabase.co/functions/v1"
    )!

    /// Foundation folds `-key value` launch arguments into `UserDefaults`' `NSArgumentDomain`
    /// before any of our code runs, so we read the key rather than hand-scanning
    /// `CommandLine.arguments`. That also lets a developer set it in the scheme's Arguments
    /// tab, and it keeps the fixture server invisible to the rest of the app.
    ///
    /// `defaults` is a parameter, not a hardcoded `.standard`, so `AppConfigurationTests` can
    /// prove the override works without mutating the test runner's own defaults.
    static func resolve(
        _ defaults: UserDefaults = .standard,
        bundle: Bundle = .main,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> AppConfiguration {
        let api = absoluteURL(defaults.string(forKey: apiBaseURLKey)) ?? productionAPIBaseURL
        #if DEBUG
        let usesFixtureSession = arguments.contains("-fixtureSession")
        let forcesReducedMotionForUITests = arguments.contains("-uiTestReduceMotion")
        let opensRecordForUITests = arguments.contains("-uiTestRecord")
        #else
        let usesFixtureSession = false
        let forcesReducedMotionForUITests = false
        let opensRecordForUITests = false
        #endif
        return AppConfiguration(
            apiBaseURL: api,
            authBaseURL: absoluteURL(defaults.string(forKey: authBaseURLKey)),
            // The launch argument wins so a fixture run needs no bundle key; otherwise the
            // `Info.plist` value, which is injected at build time and is public by design.
            anonKey: defaults.string(forKey: anonKeyKey)
                ?? bundle.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
                ?? "",
            spotifyClientID: defaults.string(forKey: spotifyClientIDKey)
                ?? bundle.object(forInfoDictionaryKey: "SPOTIFY_CLIENT_ID") as? String
                ?? "",
            usesFixtureSession: usesFixtureSession,
            forcesReducedMotionForUITests: forcesReducedMotionForUITests,
            opensRecordForUITests: opensRecordForUITests
        )
    }

    /// A bare word parses as a *relative* URL and would silently produce a request to nowhere.
    /// Requiring a scheme turns a typo into "use the default", not "hang".
    private static func absoluteURL(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw), url.scheme != nil else { return nil }
        return url
    }
}
