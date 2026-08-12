import Foundation
import Testing
@testable import BlindDrop

/// `-apiBaseURL` is what points a test run at the fixture server (`ios/Fixtures/server.ts`,
/// E00-05) instead of production. `PlaceholderUITests` already passes it; this suite proves
/// the app actually reads it, without mutating the test runner's own defaults.
@Suite struct AppConfigurationTests {

    /// A throwaway suite so nothing leaks between tests or into `.standard`.
    private func defaults(_ value: String?) -> UserDefaults {
        let name = "BlindDropTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        if let value { d.set(value, forKey: AppConfiguration.apiBaseURLKey) }
        return d
    }

    @Test func launchArgumentOverridesTheBaseURL() {
        let config = AppConfiguration.resolve(defaults("http://127.0.0.1:8787"))
        #expect(config.apiBaseURL == URL(string: "http://127.0.0.1:8787")!)
    }

    @Test func withoutTheArgumentItFallsBackToProduction() {
        let config = AppConfiguration.resolve(defaults(nil))
        #expect(config.apiBaseURL == AppConfiguration.productionAPIBaseURL)
    }

    /// A schemeless string parses as a *relative* URL, which would produce requests to
    /// nowhere. Falling back is the honest failure; hanging is not.
    @Test func aValueWithoutASchemeFallsBackToProduction() {
        let config = AppConfiguration.resolve(defaults("not a url"))
        #expect(config.apiBaseURL == AppConfiguration.productionAPIBaseURL)
    }

    /// Supabase Auth is a **sibling** of the functions service, not a route inside it
    /// (`docs/14` §5). Appending would produce `…/functions/v1/auth/v1`, which is a 404 that
    /// would look exactly like a rejected sign-in.
    @Test func theAuthAddressIsASiblingOfTheFunctionsAddress() {
        #expect(AppConfiguration.deriveAuthBaseURL(from: AppConfiguration.productionAPIBaseURL)
                == URL(string: "https://project.supabase.co/auth/v1")!)
        // The fixture server has no `/functions/v1` prefix to replace, so the path is added.
        #expect(AppConfiguration.deriveAuthBaseURL(from: URL(string: "http://127.0.0.1:8787")!)
                == URL(string: "http://127.0.0.1:8787/auth/v1")!)
        #expect(AppConfiguration.deriveAuthBaseURL(from: URL(string: "http://127.0.0.1:8787/")!)
                == URL(string: "http://127.0.0.1:8787/auth/v1")!)
    }

    /// And the derived address is what a resolved configuration carries, so there is one
    /// launch argument to point a whole run — API and auth — at the fixture server.
    @Test func oneArgumentPointsBothServicesAtTheFixture() {
        let config = AppConfiguration.resolve(defaults("http://127.0.0.1:8787"))
        #expect(config.apiBaseURL == URL(string: "http://127.0.0.1:8787")!)
        #expect(config.authBaseURL == URL(string: "http://127.0.0.1:8787/auth/v1")!)
    }

    /// `-authBaseURL` overrides the derivation, and `-supabaseAnonKey` beats the bundle. Both
    /// exist so a run can be pointed at a real project without a rebuild.
    @Test func theAuthArgumentsOverrideTheDefaults() {
        let name = "BlindDropTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        d.set("http://127.0.0.1:8787", forKey: AppConfiguration.apiBaseURLKey)
        d.set("https://elsewhere.example/auth/v1", forKey: AppConfiguration.authBaseURLKey)
        d.set("pk-test", forKey: AppConfiguration.anonKeyKey)

        let config = AppConfiguration.resolve(d)
        #expect(config.authBaseURL == URL(string: "https://elsewhere.example/auth/v1")!)
        #expect(config.anonKey == "pk-test")
    }

    /// The composition root has to actually pass the configuration through, or honouring the
    /// argument buys nothing.
    @MainActor
    @Test func theEnvironmentCarriesTheConfiguredBaseURL() async {
        let fixture = AppConfiguration(apiBaseURL: URL(string: "http://127.0.0.1:8787")!)
        let env = AppEnvironment(configuration: fixture)
        #expect(env.configuration.apiBaseURL == fixture.apiBaseURL)
        #expect(await env.api.baseURL == fixture.apiBaseURL)
    }

    /// Paths are *appended*, never substituted: with the fixture base this yields
    /// `/rounds/current`, and with the production base `/functions/v1/rounds/current`.
    /// Replacing the path would silently drop `/functions/v1` in production.
    @Test func endpointPathsAppendToTheBase() {
        let fixture = URL(string: "http://127.0.0.1:8787")!
        #expect(fixture.appending(path: "rounds/current").absoluteString
                == "http://127.0.0.1:8787/rounds/current")
        #expect(AppConfiguration.productionAPIBaseURL.appending(path: "rounds/current").path()
                == "/functions/v1/rounds/current")
    }
}
