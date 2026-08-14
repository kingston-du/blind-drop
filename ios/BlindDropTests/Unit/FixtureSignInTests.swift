import Foundation
import Testing
@testable import BlindDrop

/// E09-01's other verification: *"sign-in completes against the fixture server."*
///
/// Everything in `AuthTests` is doubles — which is what makes it fast and exact, and also what
/// makes it unable to notice that `SupabaseAuthService` builds a request Supabase would refuse.
/// This suite runs the **real** service, the **real** `Keychain`, and the **real** `APIClient`
/// against `ios/Fixtures/server.ts`. Only Apple's sheet is stubbed, because a sheet cannot be
/// driven from a simulator and there is nothing to learn from trying.
///
/// It is skipped unless `BLINDDROP_FIXTURE_API` is set, which `ios/scripts/verify-signin.sh`
/// does after starting the server. A test that silently passes when its server is not running
/// is worse than no test; a test that is visibly skipped is honest.
///
/// The address lives outside the suite because a `@Suite` trait that referred to a static on
/// the suite it decorates is a circular macro reference.
enum FixtureServer {
    static let baseURL: URL? = ProcessInfo.processInfo.environment["BLINDDROP_FIXTURE_API"]
        .flatMap(URL.init(string:))
}

@MainActor
@Suite(.enabled(if: FixtureServer.baseURL != nil))
struct FixtureSignInTests {

    /// Apple's half, canned. The fixture server checks that a provider, an identity token and a
    /// nonce all arrive — the three things a real exchange would be refused without.
    @MainActor
    private final class StubApple: AppleIdentityProviding {
        func requestIdentity() async throws -> AppleIdentity {
            AppleIdentity(
                identityToken: "eyJhbGciOiJSUzI1NiJ9.fixture.signature",
                nonce: AppleSignIn.makeNonce(),
                authorizationCode: "fixture.authorization.code"
            )
        }
    }

    /// The whole path, end to end: exchange → Keychain → `GET /me` → a routed state → refresh
    /// → revoke.
    @Test func signInRefreshAndSignOutCompleteAgainstTheFixtureServer() async throws {
        let base = try #require(FixtureServer.baseURL)
        let keychain = Keychain(service: "app.blinddrop.tests.\(UUID().uuidString)")
        defer { try? keychain.delete(Keychain.Account.refreshToken) }

        let env = AppEnvironment(
            configuration: AppConfiguration(apiBaseURL: base),
            secrets: keychain
        )
        #expect(env.configuration.authBaseURL.path().hasSuffix("/auth/v1"))

        // 1. Sign in. Apple's token goes to /auth/v1/token?grant_type=id_token, the session
        //    comes back, the refresh token lands in the Keychain, and GET /me decides the
        //    screen. The fixture's `me.json` has a group, so this is a user who lands on the
        //    round (`docs/08` §1.5).
        try await env.session.signIn(with: StubApple())
        #expect(env.session.state == .ready)
        #expect(env.session.user?.displayName == "Ana")
        let firstAccess = try #require(env.session.accessToken)
        let firstRefresh = try #require(try keychain.read(Keychain.Account.refreshToken))

        // 2. And the session is on server time — every response anchors the clock, including
        //    the first one after sign-in (`docs/13` §5).
        #expect(env.clock.now != nil)

        // 3. Refresh. The fixture rotates, exactly as Supabase does, so a stored token that
        //    did not change would mean the client kept spending a dead one.
        #expect(await env.session.refreshCredentials(after: firstAccess))
        #expect(env.session.accessToken != firstAccess)
        #expect(try keychain.read(Keychain.Account.refreshToken) != firstRefresh)

        // 4. Sign out revokes server-side and leaves nothing behind (`docs/14` §5).
        await env.session.signOut()
        #expect(env.session.state == .signedOut)
        #expect(env.session.accessToken == nil)
        #expect(try keychain.read(Keychain.Account.refreshToken) == nil)
    }

    /// A cold launch with the token from a previous one. This is the path that has to work
    /// every morning, and it is the only one that exercises the Keychain across two
    /// `SessionStore` instances.
    @Test func aStoredTokenSurvivesIntoTheNextLaunch() async throws {
        let base = try #require(FixtureServer.baseURL)
        let keychain = Keychain(service: "app.blinddrop.tests.\(UUID().uuidString)")
        defer { try? keychain.delete(Keychain.Account.refreshToken) }

        let first = AppEnvironment(configuration: AppConfiguration(apiBaseURL: base), secrets: keychain)
        try await first.session.signIn(with: StubApple())
        #expect(first.session.state == .ready)

        // A second launch: a new store, a new client, the same Keychain. It finds the token
        // the first one wrote and resolves to a routed state instead of a sign-in wall.
        //
        // What this does *not* assert is the 401→refresh→retry hop, because the fixture server
        // answers `GET /me` to anyone — it is a canned contract, not an auth gate (E00-05).
        // That hop is counted in `AuthTests.a401RefreshesOnceAndRetriesOnce`, where a stub can
        // actually refuse.
        let second = AppEnvironment(configuration: AppConfiguration(apiBaseURL: base), secrets: keychain)
        #expect(second.session.state == .unknown)
        await second.session.load()
        #expect(second.session.state == .ready)

        await second.session.signOut()
    }

    /// And a launch with nothing stored is signed out — not stuck on a blank screen waiting for
    /// a request it has no credential to make.
    @Test func aColdInstallIsSignedOut() async throws {
        let base = try #require(FixtureServer.baseURL)
        let env = AppEnvironment(
            configuration: AppConfiguration(apiBaseURL: base),
            secrets: Keychain(service: "app.blinddrop.tests.\(UUID().uuidString)")
        )
        await env.session.load()
        #expect(env.session.state == .signedOut)
    }
}
