import CryptoKit
import Foundation
import Security
import Testing
@testable import BlindDrop

// MARK: - Doubles
//
// At file scope rather than nested, because `NetworkingTests` builds a `SessionStore` too and
// a second copy of these would be a second thing to keep in step.

/// A `SecretStore` that is a dictionary. Stands in for the Keychain everywhere except the one
/// test that is *about* the Keychain.
@MainActor
final class MemorySecrets: SecretStore {
    private(set) var stored: [String: String] = [:]
    /// Simulates a device that will not hold the token — a locked keychain, a broken profile.
    var refusesWrites = false
    private(set) var deletions: [String] = []

    func read(_ account: String) throws -> String? { stored[account] }

    func write(_ value: String, to account: String) throws {
        if refusesWrites { throw KeychainError.status(errSecInteractionNotAllowed) }
        stored[account] = value
    }

    func delete(_ account: String) throws {
        deletions.append(account)
        stored[account] = nil
    }

    /// A token left over from a previous launch. Not `write`, so `refusesWrites` and the
    /// deletion log both start clean.
    func preload(_ value: String, to account: String) {
        stored[account] = value
    }
}

/// Supabase Auth, recorded rather than called.
@MainActor
final class FakeAuth: AuthService {
    var nextSignIn: Result<AuthTokens, AuthError> = .success(.init(accessToken: "access-1", refreshToken: "refresh-1"))
    var nextRefresh: Result<AuthTokens, AuthError> = .success(.init(accessToken: "access-2", refreshToken: "refresh-2"))

    private(set) var signInCalls: [AppleIdentity] = []
    private(set) var passwordSignInCalls: [(email: String, password: String)] = []
    private(set) var refreshCalls: [String] = []
    private(set) var revokedTokens: [String] = []

    func signIn(with identity: AppleIdentity) async throws -> AuthTokens {
        signInCalls.append(identity)
        return try nextSignIn.get()
    }

    func signIn(email: String, password: String) async throws -> AuthTokens {
        passwordSignInCalls.append((email, password))
        return try nextSignIn.get()
    }

    func refresh(_ refreshToken: String) async throws -> AuthTokens {
        refreshCalls.append(refreshToken)
        // A suspension point, so a second caller arriving mid-refresh actually finds one in
        // flight. Without it the refresh completes synchronously and the deduplication this
        // double exists to exercise is never reached.
        await Task.yield()
        return try nextRefresh.get()
    }

    func revoke(accessToken: String) async {
        revokedTokens.append(accessToken)
    }
}

/// Apple's sheet, without Apple's sheet.
@MainActor
final class FakeApple: AppleIdentityProviding {
    var result: Result<AppleIdentity, AuthError> = .success(
        .init(
            identityToken: "apple.identity.token",
            nonce: "raw-nonce",
            authorizationCode: "apple.authorization.code"
        )
    )
    private(set) var requests = 0

    /// The name Apple sends on a **first** authorization and never again. `nil` is the returning
    /// Apple ID, which is most sign-ins.
    func suggests(_ name: String?) {
        guard case .success(var identity) = result else { return }
        identity.suggestedName = name
        result = .success(identity)
    }

    func requestIdentity() async throws -> AppleIdentity {
        requests += 1
        return try result.get()
    }
}

/// Every distinct `SessionState` a store passed through, in order. A class because the sampler
/// that fills it is a `Task`, and Swift 6 will not let one close over a mutable local.
@MainActor
final class SessionStateLog {
    private(set) var states: [SessionState] = []

    func record(_ state: SessionState) {
        if states.last != state { states.append(state) }
    }
}

/// A `URLProtocol` that answers from a queue and records what it was asked. Its own class, and
/// not `NetworkingTests`' one, so the two suites cannot answer each other's requests.
final class AuthStub: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status: Int = 200
        var body: Data = Data()
        var networkError: URLError.Code?
    }

    nonisolated(unsafe) private static var queue: [Reply] = []
    nonisolated(unsafe) private static var last = Reply()
    nonisolated(unsafe) private(set) static var requests: [URLRequest] = []
    private static let lock = NSLock()

    static func arm(_ replies: [Reply]) {
        lock.lock(); defer { lock.unlock() }
        queue = replies
        last = replies.last ?? Reply()
        requests = []
    }

    static func next() -> Reply {
        lock.lock(); defer { lock.unlock() }
        return queue.isEmpty ? last : queue.removeFirst()
    }

    static func record(_ request: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        requests.append(request)
    }

    static var taken: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        AuthStub.record(request)
        let reply = AuthStub.next()
        if let networkError = reply.networkError {
            client?.urlProtocol(self, didFailWithError: URLError(networkError))
            return
        }
        let http = HTTPURLResponse(
            url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// A session store wired to a stubbed `APIClient`, with the three doubles reachable.
@MainActor
struct AuthHarness {
    let auth: FakeAuth
    let secrets: MemorySecrets
    let apple: FakeApple
    let session: SessionStore
    /// Held so the client outlives the test — `SessionStore` keeps only a weak reference.
    let api: APIClient

    init() {
        let auth = FakeAuth()
        let secrets = MemorySecrets()
        let session = SessionStore(auth: auth, secrets: secrets)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthStub.self]
        let api = APIClient(
            baseURL: URL(string: "https://fixture.test/functions/v1")!,
            clock: ServerClock(),
            session: session,
            transport: APIClient.makeTransport(configuration)
        )
        session.attach(api)
        self.auth = auth
        self.secrets = secrets
        self.apple = FakeApple()
        self.session = session
        self.api = api
    }
}

/// `docs/14` §5 and E09-01, made testable. Nothing here talks to a network or to Apple.
///
/// `.serialized` because `AuthStub` is process-wide: one queue of canned replies and one list
/// of requests, which is what makes "two requests, not three" a countable fact.
@MainActor
@Suite(.serialized) struct AuthTests {

    private static let me = Data(#"{"user_id":"u_ana","display_name":"Ana","has_group":true}"#.utf8)
    private static let meNoGroup = Data(#"{"user_id":"u_ana","display_name":"Ana","has_group":false}"#.utf8)

    private static func envelope(_ payload: Data) -> Data {
        var body = Data(#"{"server_now":"2026-08-10T18:42:07Z","data":"#.utf8)
        body.append(payload)
        body.append(Data("}".utf8))
        return body
    }

    private static func failure(_ code: String) -> Data {
        Data(#"{"server_now":"2026-08-10T18:42:07Z","error":{"code":"\#(code)","message":"x"}}"#.utf8)
    }

    private static func ok(_ payload: Data) -> AuthStub.Reply {
        .init(status: 200, body: envelope(payload))
    }

    private static let unauthorized = AuthStub.Reply(status: 401, body: failure("UNAUTHENTICATED"))

    // MARK: - The Keychain

    /// `docs/14` §5, literally: the refresh token is written with
    /// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Asserted by reading the protection
    /// class back off the item that was actually stored, not by reading the source.
    ///
    /// - `AfterFirstUnlock` because a push at 8:00 PM can need a token refresh with the phone
    ///   in a pocket.
    /// - `ThisDeviceOnly` because a restored iCloud backup must not carry a live session onto
    ///   a second device.
    @Test func theRefreshTokenIsKeychainedAfterFirstUnlockThisDeviceOnly() throws {
        let keychain = Keychain(service: "app.blinddrop.tests.\(UUID().uuidString)")
        let account = Keychain.Account.refreshToken
        defer { try? keychain.delete(account) }

        #expect(try keychain.read(account) == nil, "nothing is stored until something is")

        try keychain.write("refresh-1", to: account)
        #expect(try keychain.read(account) == "refresh-1")
        #expect(try keychain.accessibility(of: account)
                == (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String))

        // Rotation is an update, not a duplicate — and it keeps the protection class.
        try keychain.write("refresh-2", to: account)
        #expect(try keychain.read(account) == "refresh-2")
        #expect(try keychain.accessibility(of: account)
                == (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String))

        try keychain.delete(account)
        #expect(try keychain.read(account) == nil)
        // Deleting what is not there is a success: sign-out must not fail on a second tap.
        #expect(throws: Never.self) { try keychain.delete(account) }
    }

    /// Two accounts in the same service do not see each other. The Spotify token lands beside
    /// this one in E13-03.
    @Test func accountsAreSeparate() throws {
        let keychain = Keychain(service: "app.blinddrop.tests.\(UUID().uuidString)")
        defer {
            try? keychain.delete("a")
            try? keychain.delete("b")
        }
        try keychain.write("one", to: "a")
        try keychain.write("two", to: "b")
        #expect(try keychain.read("a") == "one")
        #expect(try keychain.read("b") == "two")
    }

    // MARK: - Signing in

    /// The whole path: Apple → Supabase → the Keychain → `GET /me` → a routed state.
    @Test func signingInStoresTheRefreshTokenAndAsksTheServerWhoThisIs() async throws {
        let h = AuthHarness()
        AuthStub.arm([Self.ok(Self.me)])

        try await h.session.signIn(with: h.apple)

        #expect(h.auth.signInCalls.map(\.identityToken) == ["apple.identity.token"])
        #expect(h.auth.signInCalls.map(\.nonce) == ["raw-nonce"], "the raw nonce, not its digest")
        #expect(h.session.state == .ready)
        #expect(h.session.user?.displayName == "Ana")
        #expect(h.secrets.stored[Keychain.Account.refreshToken] == "refresh-1")
    }

    /// `docs/14` §5: the refresh token is persisted; the access token is not. It is short-lived
    /// and re-obtainable, so storing it would add a second thing to steal for no benefit.
    @Test func theAccessTokenIsNeverPersisted() async throws {
        let h = AuthHarness()
        AuthStub.arm([Self.ok(Self.me)])

        try await h.session.signIn(with: h.apple)

        #expect(h.session.accessToken == "access-1")
        #expect(h.secrets.stored.count == 1)
        #expect(!h.secrets.stored.values.contains("access-1"))
    }

    /// `GET /me` decides the screen (`docs/13` §4), and the client does not compute it. A
    /// profile-less caller lands on naming; a group-less one on joining.
    @Test func theServerDecidesWhichScreenFollowsSignIn() async throws {
        let noProfile = AuthHarness()
        AuthStub.arm([.init(status: 409, body: Self.failure("NO_PROFILE"))])
        try await noProfile.session.signIn(with: noProfile.apple)
        #expect(noProfile.session.state == .noProfile)
        #expect(noProfile.session.user == nil)

        let noGroup = AuthHarness()
        AuthStub.arm([Self.ok(Self.meNoGroup)])
        try await noGroup.session.signIn(with: noGroup.apple)
        #expect(noGroup.session.state == .noGroup)
        #expect(noGroup.session.user?.hasGroup == false)
    }

    /// A device that will not hold the token fails the sign-in rather than quietly downgrading
    /// to a session that evaporates at the next launch. The downgrade looks identical until
    /// tomorrow, when the user is asked to sign in again with no explanation.
    @Test func aKeychainThatRefusesTheTokenFailsTheSignIn() async throws {
        let h = AuthHarness()
        h.secrets.refusesWrites = true
        AuthStub.arm([Self.ok(Self.me)])

        await #expect(throws: AuthError.unreadable) { try await h.session.signIn(with: h.apple) }
        #expect(h.session.accessToken == nil)
        #expect(h.session.state == .unknown, "a failed sign-in is not a sign-out")
        #expect(AuthStub.taken.isEmpty, "no /me for a session that was never established")
    }

    /// Dismissing Apple's sheet is not a failure. It propagates so the screen can distinguish
    /// it, and it resolves to no copy at all.
    @Test func aCancelledSheetShowsNothing() async throws {
        let h = AuthHarness()
        h.apple.result = .failure(.cancelled)

        await #expect(throws: AuthError.cancelled) { try await h.session.signIn(with: h.apple) }
        #expect(h.auth.signInCalls.isEmpty, "nothing was exchanged")
        #expect(AuthError.cancelled.copyKey == nil)
        #expect(AuthError.busy.copyKey == nil)
    }

    /// Supabase refusing the identity token is one error with one thing to do about it.
    @Test func aRefusedExchangeIsAnOrdinaryFailure() async throws {
        let h = AuthHarness()
        h.auth.nextSignIn = .failure(.rejected)

        await #expect(throws: AuthError.rejected) { try await h.session.signIn(with: h.apple) }
        #expect(h.session.state == .unknown)
        #expect(h.secrets.stored.isEmpty)
    }

    // MARK: - The name Apple supplies (App Review guideline 4)

    /// **The rejection, as a test** (2026-09-21): *"users are required to provide their name …
    /// even though that information is already provided by the Authentication Services
    /// framework"*. A first authorization carries a name, so the app saves it and the caller is
    /// past `docs/08` §1.2 without ever seeing it.
    @Test func appleSuppliedNameIsAdoptedForACallerWithNoProfile() async throws {
        let h = AuthHarness()
        h.apple.suggests("Ana")
        AuthStub.arm([
            .init(status: 409, body: Self.failure("NO_PROFILE")),
            Self.ok(Self.me),
            Self.ok(Self.meNoGroup),
        ])

        try await h.session.signIn(with: h.apple)

        let requests = AuthStub.taken
        #expect(requests.map(\.httpMethod) == ["GET", "PUT", "GET"])
        #expect(Self.bodyString(of: requests[1]).contains(#""display_name":"Ana""#))
        #expect(h.session.state == .noGroup, "1.3, not the name screen")
        #expect(h.session.user?.displayName == "Ana")
    }

    /// **The `NO_PROFILE` that decides the write is never published.** `SessionStore` routes on
    /// any endpoint's `NO_PROFILE` (`noteServerSaid(_:)`), so the reconnaissance read inside
    /// `adoptAppleName(_:)` would otherwise assign `.noProfile` — and an assignment is a frame
    /// of `DisplayNameScreen`, keyboard and all, in the middle of the flow built to remove it.
    /// Asserted from outside: the same 409 that reaches the store here leaves the state alone,
    /// and only the final read moves it.
    @Test func adoptingANameNeverRoutesThroughTheNameScreen() async throws {
        let h = AuthHarness()
        h.apple.suggests("Ana")
        AuthStub.arm([
            .init(status: 409, body: Self.failure("NO_PROFILE")),
            Self.ok(Self.me),
            Self.ok(Self.meNoGroup),
        ])

        let log = SessionStateLog()
        let sampler = Task { @MainActor in
            // Sampled on every main-actor turn the sign-in suspends for, which is where a
            // published `.noProfile` would appear.
            while !Task.isCancelled {
                log.record(h.session.state)
                await Task.yield()
            }
        }
        try await h.session.signIn(with: h.apple)
        sampler.cancel()

        #expect(!log.states.contains(.noProfile), "the name screen was never routed to")
        #expect(h.session.state == .noGroup)
    }

    /// The other half of the same rule: a name is *offered*, never imposed on a profile that
    /// already has one. Apple sends nothing on a repeat authorization, but the guard says so in
    /// its own right rather than relying on Apple's behaviour to be the reason.
    @Test func anExistingProfileIsNeverRenamedBySigningInAgain() async throws {
        let h = AuthHarness()
        h.apple.suggests("Someone Else")
        AuthStub.arm([Self.ok(Self.me)])

        try await h.session.signIn(with: h.apple)

        let requests = AuthStub.taken
        #expect(!requests.map(\.httpMethod).contains("PUT"), "nothing was written")
        #expect(requests.count == 2, "the suppressed read, then the one that routes")
        #expect(h.session.user?.displayName == "Ana")
        #expect(h.session.state == .ready)
    }

    /// The returning Apple ID — a reinstall, a second device — gets the name screen, which is
    /// the same screen everybody used to get and is allowed: nothing was provided to re-ask for.
    @Test func noNameFromAppleLeavesTheCallerOnTheNameScreen() async throws {
        let h = AuthHarness()
        h.apple.suggests(nil)
        AuthStub.arm([.init(status: 409, body: Self.failure("NO_PROFILE"))])

        try await h.session.signIn(with: h.apple)

        #expect(AuthStub.taken.count == 1, "no name to write")
        #expect(h.session.state == .noProfile)
    }

    /// A refused write is not a refused sign-in. The session is real, the state is still
    /// `.noProfile`, and the user types a name — the same outcome as having no name at all.
    @Test func aRefusedNameSaveStillSignsTheCallerIn() async throws {
        let h = AuthHarness()
        h.apple.suggests("Ana")
        AuthStub.arm([
            .init(status: 409, body: Self.failure("NO_PROFILE")),
            .init(status: 500, body: Self.failure("INTERNAL")),
            .init(status: 409, body: Self.failure("NO_PROFILE")),
        ])

        try await h.session.signIn(with: h.apple)

        #expect(AuthStub.taken.map(\.httpMethod) == ["GET", "PUT", "GET"])
        #expect(h.session.state == .noProfile, "1.2, and the user types one")
        #expect(h.session.accessToken == "access-1")
        #expect(h.secrets.stored[Keychain.Account.refreshToken] == "refresh-1")
    }

    /// Given name first, the full name only when there is no given name, and `nil` for anything
    /// `DisplayName` would not let a person type — a 24-character limit applies to a name that
    /// arrived from Apple exactly as it applies to one typed into the field.
    @Test func appleNameComponentsReduceToOneDisplayName() {
        var given = PersonNameComponents()
        given.givenName = "Ana"
        given.familyName = "Beltrán"
        #expect(AppleSignIn.displayName(from: given) == "Ana", "the name friends use, not the record")

        var familyOnly = PersonNameComponents()
        familyOnly.familyName = "Beltrán"
        #expect(AppleSignIn.displayName(from: familyOnly) == "Beltrán")

        var padded = PersonNameComponents()
        padded.givenName = "  Ana\u{200B} "
        #expect(AppleSignIn.displayName(from: padded) == "Ana", "cleaned the way the field cleans")

        var tooLong = PersonNameComponents()
        tooLong.givenName = String(repeating: "a", count: 25)
        #expect(AppleSignIn.displayName(from: tooLong) == nil, "asked for rather than truncated")

        #expect(AppleSignIn.displayName(from: PersonNameComponents()) == nil)
        #expect(AppleSignIn.displayName(from: nil) == nil)
    }

    /// **The scopes, read off the request Apple would actually be handed.**
    ///
    /// Two claims, and the second is the one worth a test: the name *is* asked for (guideline 4,
    /// 2026-09-21) and the email is **never** asked for, in either mode. `docs/14` §9's list of
    /// what this app collects has no address on it, and the cheapest way for one to appear is a
    /// scope somebody adds without noticing. The deletion re-auth asks for nothing at all — it
    /// needs a fresh authorization code, and a permission prompt on the way out is a prompt with
    /// no purpose behind it.
    @Test func theRequestAsksForTheNameAndNeverTheEmail() {
        let signingIn = AppleSignIn().makeRequest(nonce: "raw-nonce")
        #expect(signingIn.requestedScopes == [.fullName])
        #expect(signingIn.nonce == AppleSignIn.digest(of: "raw-nonce"), "Apple gets the digest")

        let reauthenticating = AppleSignIn(requestsName: false).makeRequest(nonce: "raw-nonce")
        #expect(reauthenticating.requestedScopes?.isEmpty ?? true)

        for request in [signingIn, reauthenticating] {
            #expect(request.requestedScopes?.contains(.email) != true)
        }
    }

    /// `URLSession` moves an `httpBody` into an `httpBodyStream` before a `URLProtocol` sees it.
    private static func bodyString(of request: URLRequest) -> String {
        if let body = request.httpBody { return String(decoding: body, as: UTF8.self) }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(contentsOf: buffer[..<read])
        }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Launch

    /// No stored token means signed out, said immediately and without a request. A sign-in
    /// wall behind a spinner is the worst of both.
    @Test func launchingWithNoStoredTokenIsSignedOut() async {
        let h = AuthHarness()
        AuthStub.arm([Self.ok(Self.me)])

        await h.session.load()

        #expect(h.session.state == .signedOut)
        #expect(AuthStub.taken.isEmpty)
    }

    /// A stored refresh token restores the session — through the 401 path, not around it. The
    /// first `GET /me` has no access token to carry, so it 401s, refreshes, and retries. That
    /// is one round trip more than refreshing pre-emptively and one fewer good refresh token
    /// spent on a question the request answers for free.
    @Test func launchingWithAStoredTokenRestoresTheSession() async throws {
        let h = AuthHarness()
        h.secrets.preload("refresh-0", to: Keychain.Account.refreshToken)
        AuthStub.arm([Self.unauthorized, Self.ok(Self.me)])

        await h.session.load()

        #expect(h.auth.refreshCalls == ["refresh-0"])
        #expect(h.session.state == .ready)
        #expect(h.session.accessToken == "access-2")
        #expect(h.secrets.stored[Keychain.Account.refreshToken] == "refresh-2", "rotation is stored")
    }

    @Test func anOfflineLaunchKeepsIdentityUnknownAndCanRetry() async throws {
        let h = AuthHarness()
        h.secrets.preload("refresh-0", to: Keychain.Account.refreshToken)
        AuthStub.arm([.init(networkError: .notConnectedToInternet)])

        await h.session.load()

        #expect(h.session.state == .unknown)
        #expect(h.session.loadFailure == .offline)
        #expect(h.secrets.stored[Keychain.Account.refreshToken] == "refresh-0")

        AuthStub.arm([Self.unauthorized, Self.ok(Self.me)])
        await h.session.load()

        #expect(h.session.state == .ready)
        #expect(h.session.loadFailure == nil)
    }

    // MARK: - The 401

    /// `docs/13` §3, counted: one 401 buys one refresh and one retry, and the retry carries the
    /// **new** bearer.
    @Test func a401RefreshesOnceAndRetriesOnce() async throws {
        let h = AuthHarness()
        h.secrets.preload("refresh-0", to: Keychain.Account.refreshToken)
        AuthStub.arm([Self.unauthorized, Self.ok(Self.me)])
        await h.session.load()

        let sent = AuthStub.taken
        #expect(sent.count == 2, "one refused attempt, one retry — not a loop")
        #expect(sent.first?.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(sent.last?.value(forHTTPHeaderField: "Authorization") == "Bearer access-2")
        #expect(h.auth.refreshCalls.count == 1)
    }

    /// And when the refresh does not help, the session is over — after exactly one attempt,
    /// not in a loop against a revoked token. The Keychain is cleared on the way out.
    @Test func a401WhoseRefreshFailsEndsTheSession() async throws {
        let h = AuthHarness()
        h.secrets.preload("refresh-0", to: Keychain.Account.refreshToken)
        h.auth.nextRefresh = .failure(.rejected)
        AuthStub.arm([Self.unauthorized])

        await h.session.load()

        #expect(AuthStub.taken.count == 1)
        #expect(h.session.state == .signedOut)
        #expect(h.session.accessToken == nil)
        #expect(h.secrets.stored[Keychain.Account.refreshToken] == nil, "a dead token is not kept")
        #expect(h.secrets.deletions.contains(Keychain.Account.refreshToken))
    }

    /// Three screens waking at 8:00 PM must not produce three refreshes. Supabase **rotates**:
    /// the second spend of a refresh token is a sign-out, so "one refresh" is a correctness
    /// requirement rather than a politeness.
    ///
    /// Two mechanisms, both asserted here. Requests that fail *together* share the one
    /// in-flight refresh; a request that fails *after* somebody else's refresh landed carries a
    /// token that is no longer the current one, and simply retries.
    @Test func concurrentFailuresProduceExactlyOneRefresh() async throws {
        let h = AuthHarness()
        AuthStub.arm([Self.ok(Self.me)])
        try await h.session.signIn(with: h.apple)

        async let a = h.session.refreshCredentials(after: "access-1")
        async let b = h.session.refreshCredentials(after: "access-1")
        async let c = h.session.refreshCredentials(after: "access-1")
        let together = await [a, b, c]

        #expect(together == [true, true, true])
        #expect(h.auth.refreshCalls == ["refresh-1"], "one refresh, whatever the fan-out")
        #expect(h.session.accessToken == "access-2")

        // A fourth request, built before the rotation and refused after it.
        let late = await h.session.refreshCredentials(after: "access-1")
        #expect(late, "a token that has already been rotated away is a retry, not a refresh")
        #expect(h.auth.refreshCalls.count == 1)
    }

    // MARK: - Signing out

    /// `docs/14` §5: sign-out revokes the refresh token **server-side**, not just locally. A
    /// local-only sign-out leaves a live credential that would mint access tokens for weeks.
    @Test func signingOutRevokesServerSideAndClearsTheKeychain() async throws {
        let h = AuthHarness()
        AuthStub.arm([Self.ok(Self.me)])
        try await h.session.signIn(with: h.apple)
        h.secrets.preload("spotify-access", to: Keychain.Account.spotifyAccessToken)
        h.secrets.preload("spotify-refresh", to: Keychain.Account.spotifyRefreshToken)

        await h.session.signOut()

        #expect(h.auth.revokedTokens == ["access-1"])
        #expect(h.session.state == .signedOut)
        #expect(h.session.accessToken == nil)
        #expect(h.session.user == nil)
        #expect(h.secrets.stored.isEmpty)
        #expect(h.secrets.deletions.contains(Keychain.Account.spotifyAccessToken))
        #expect(h.secrets.deletions.contains(Keychain.Account.spotifyRefreshToken))
    }

    /// Apple accounts make deletion a two-request flow: the first response asks for fresh
    /// proof, the second carries Apple's single-use code, and a successful delete ends the
    /// local session immediately.
    @Test func deletingAnAppleAccountReauthenticatesAndEndsTheSession() async throws {
        let h = AuthHarness()
        AuthStub.arm([Self.ok(Self.me)])
        try await h.session.signIn(with: h.apple)

        AuthStub.arm([
            .init(status: 409, body: Self.failure("REAUTHENTICATION_REQUIRED")),
            .init(status: 204),
        ])
        let center = FakeNotificationAuthority(status: .authorized, grants: true)
        let push = PushRegistrar(
            api: h.api,
            flags: LocalFlags(defaults: RoundFixture.scratchDefaults()),
            center: center
        )
        let router = Router()
        router.path = [.settings]
        let store = SettingsStore(api: h.api, session: h.session, router: router, push: push)

        await store.deleteAccount(using: h.apple)

        #expect(h.apple.requests == 2, "one sign-in and one fresh deletion authorization")
        #expect(h.session.state == .signedOut)
        #expect(router.path.isEmpty)
        #expect(center.didClearDeliveredNotifications)
        let requests = AuthStub.taken
        #expect(requests.map(\.httpMethod) == ["DELETE", "DELETE"])
    }

    // MARK: - Notifications recovery (Settings)

    /// `docs/05` §4 — `SettingsStore.load()` surfaces the recovery row only when `skip()` left
    /// the pre-prompt declined without iOS ever actually being asked.
    @Test func settingsLoadSurfacesNotificationRecoveryOnlyWhenDeclinedWithoutARealAsk() async {
        let h = AuthHarness()
        let flags = LocalFlags(defaults: RoundFixture.scratchDefaults())
        let center = FakeNotificationAuthority(status: .notDetermined, grants: true)
        let push = PushRegistrar(api: h.api, flags: flags, center: center)
        await push.promptAfterFirstSeal()
        push.skip()
        let store = SettingsStore(api: h.api, session: h.session, router: Router(), push: push)

        await store.load()

        #expect(store.showsNotificationRecovery)
    }

    /// Nobody who has not declined the pre-prompt sees the row — including somebody who has
    /// never been asked at all, which is `load()`'s default and must stay `false` without a
    /// registrar call proving it.
    @Test func settingsLoadHidesTheRowWhenNothingWasDeclined() async {
        let h = AuthHarness()
        let flags = LocalFlags(defaults: RoundFixture.scratchDefaults())
        let center = FakeNotificationAuthority(status: .notDetermined, grants: true)
        let push = PushRegistrar(api: h.api, flags: flags, center: center)
        let store = SettingsStore(api: h.api, session: h.session, router: Router(), push: push)

        await store.load()

        #expect(!store.showsNotificationRecovery)
    }

    /// Tapping the row's button spends the real dialog and closes the row — `SettingsStore` is a
    /// thin read of `PushRegistrar`'s state, not a second copy of it.
    @Test func turningOnNotificationsFromSettingsClosesTheRecoveryRow() async {
        let h = AuthHarness()
        let flags = LocalFlags(defaults: RoundFixture.scratchDefaults())
        let center = FakeNotificationAuthority(status: .notDetermined, grants: true)
        let push = PushRegistrar(api: h.api, flags: flags, center: center)
        await push.promptAfterFirstSeal()
        push.skip()
        let store = SettingsStore(api: h.api, session: h.session, router: Router(), push: push)
        await store.load()
        #expect(store.showsNotificationRecovery)

        await store.turnOnNotifications()

        #expect(center.didRequestAuthorization)
        #expect(!store.showsNotificationRecovery)
    }

    /// The other ending. `APIClient` calls it when a 401 survives its one refresh, and there is
    /// nothing to revoke because the credential is already dead — so it must not spend a round
    /// trip finding that out.
    @Test func anExpiredSessionRevokesNothing() async throws {
        let h = AuthHarness()
        AuthStub.arm([Self.ok(Self.me)])
        try await h.session.signIn(with: h.apple)

        h.session.endSession()

        #expect(h.auth.revokedTokens.isEmpty)
        #expect(h.session.state == .signedOut)
        #expect(h.secrets.stored.isEmpty)
    }

    // MARK: - The nonce

    /// Apple is given the SHA-256 of the nonce; Supabase is given the nonce. Supabase hashes it
    /// and compares against the identity token's claim, which is what stops a token captured
    /// off one device being replayed from another.
    @Test func appleGetsTheDigestAndSupabaseGetsTheNonce() {
        // A published vector, so this asserts SHA-256 rather than asserting CryptoKit agrees
        // with itself: sha256("abc").
        #expect(AppleSignIn.digest(of: "abc")
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

        let first = AppleSignIn.makeNonce()
        let second = AppleSignIn.makeNonce()
        #expect(first.count == 64, "32 bytes, hex")
        #expect(first != second)
        #expect(AppleSignIn.digest(of: first).count == 64)
        #expect(AppleSignIn.digest(of: first) != first)
    }

    // MARK: - The flag

    /// `docs/14` §5: phone OTP is behind a build flag and off in v1. It needs an SMS provider
    /// and its own rate limiting before it could be anything else.
    @Test func phoneAuthIsOff() {
        #expect(AuthFeatures.isPhoneAuthEnabled == false)
    }

    // MARK: - Copy

    /// Every failure a person can be shown resolves to a real row in `Localizable.strings`. A
    /// missing key renders as the key, which is the one failure mode a user cannot act on.
    @Test func everyAuthErrorThatSpeaksHasAString() throws {
        for error in [AuthError.offline, .rejected, .unreadable] {
            let key = try #require(error.copyKey)
            #expect(Copy.string(key) != key, "\(key) is not in Localizable.strings")
        }
        for silent in [AuthError.cancelled, .busy] {
            #expect(silent.copyKey == nil)
        }
    }
}
