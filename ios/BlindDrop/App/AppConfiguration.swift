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

    /// The launch-argument key. `-apiBaseURL http://127.0.0.1:8787` in the UI test scheme
    /// points the app at `ios/Fixtures/server.ts` (E00-05).
    static let apiBaseURLKey = "apiBaseURL"
    static let authBaseURLKey = "authBaseURL"
    static let anonKeyKey = "supabaseAnonKey"

    /// `authBaseURL` and `anonKey` default off `apiBaseURL` and the bundle, so every existing
    /// call site — and every test that only cares about the API address — keeps working.
    init(apiBaseURL: URL, authBaseURL: URL? = nil, anonKey: String = "") {
        self.apiBaseURL = apiBaseURL
        self.authBaseURL = authBaseURL ?? Self.deriveAuthBaseURL(from: apiBaseURL)
        self.anonKey = anonKey
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
    static func resolve(
        _ defaults: UserDefaults = .standard,
        bundle: Bundle = .main
    ) -> AppConfiguration {
        let api = absoluteURL(defaults.string(forKey: apiBaseURLKey)) ?? productionAPIBaseURL
        return AppConfiguration(
            apiBaseURL: api,
            authBaseURL: absoluteURL(defaults.string(forKey: authBaseURLKey)),
            // The launch argument wins so a fixture run needs no bundle key; otherwise the
            // `Info.plist` value, which is injected at build time and is public by design.
            anonKey: defaults.string(forKey: anonKeyKey)
                ?? bundle.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
                ?? ""
        )
    }

    /// A bare word parses as a *relative* URL and would silently produce a request to nowhere.
    /// Requiring a scheme turns a typo into "use the default", not "hang".
    private static func absoluteURL(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw), url.scheme != nil else { return nil }
        return url
    }
}
