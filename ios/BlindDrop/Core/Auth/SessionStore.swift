import Foundation

/// What the **server** has told us about the caller. Every transition is server-declared;
/// none of them is inferred client-side (`docs/13` §4, `docs/04` §1–§2).
///
/// | Server says | state |
/// |---|---|
/// | `401 UNAUTHENTICATED` | `.signedOut` |
/// | `409 NO_PROFILE` | `.noProfile` |
/// | `409 NO_GROUP`, or `GET /me` → `has_group: false` | `.noGroup` |
/// | `GET /me` → `has_group: true` | `.ready` |
///
/// `.unknown` is the fifth case and is not a deviation from `docs/13` §4's four: it is
/// `docs/13` §5 rule 3 — "before the first successful response the app does not know" —
/// applied to identity as well as to time. It renders nothing rather than guessing
/// `.signedOut`, because guessing wrong shows a sign-in wall to a signed-in user.
enum SessionState: Equatable, Sendable {
    case unknown
    case signedOut
    case noProfile
    /// The caller's profile exists but they are in no group yet.
    case noGroup
    case ready
}

/// Owns the Supabase session (`docs/13` §1). The only place `SessionState` is assigned.
///
/// Three things about this file are load-bearing:
///
/// 1. **The refresh token is only ever in the Keychain** (`docs/14` §5), with
///    `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. The access token is in memory and
///    nowhere else — it is short-lived and re-obtainable, so persisting it would add a second
///    thing to steal for no benefit.
/// 2. **One 401 buys one refresh.** `APIClient` calls `refreshCredentials(after:)` with the
///    token the failed request actually used. If it is not the token we hold any more, some
///    other request already refreshed and this one simply retries — which is how three screens
///    waking at 8:00 PM produce one refresh rather than three, and how the second of them
///    avoids spending a rotated refresh token that would fail.
/// 3. **Sign-out revokes server-side** (`docs/14` §5). `endSession()` is the other ending — the
///    server has already rejected us past our one refresh, so there is nothing left to revoke.
@Observable @MainActor
final class SessionStore {

    private(set) var state: SessionState = .unknown

    /// Why identity is still unknown after a launch attempt. This is deliberately separate from
    /// `state`: a network failure is not evidence that the person is signed out, but it is enough
    /// information for the root to offer an honest retry instead of showing a permanent blank.
    private(set) var loadFailure: APIError?

    /// The bearer token on every request, or `nil` when there is no session.
    private(set) var accessToken: String?

    /// The caller, once `GET /me` has answered. `nil` in every state but `.noGroup` and
    /// `.ready` — before that the app does not know who is asking.
    private(set) var user: UserDTO?

    private let auth: any AuthService
    private let secrets: any SecretStore

    /// Set by `AppEnvironment` after both objects exist. `weak` because `APIClient` holds this
    /// store: the pair is a cycle otherwise, and a cycle around the composition root is the
    /// kind that never shows up in a leak check because the objects genuinely live forever.
    private weak var api: APIClient?

    /// Set by `AppEnvironment`, `weak` for the same reason: `AppEnvironment` is the app's one
    /// long-lived composition root (`docs/13` §2), so a session that did not clear the circle
    /// cache on `endSession()` would show the previous account's circles to the next one signed
    /// in on the same install (`E19-01`).
    private weak var circles: CircleStore?

    /// In memory only. It is written to the Keychain and read back from it; this is the copy
    /// the running process spends.
    private var refreshToken: String?

    /// The one refresh in flight, if any.
    private var refreshInFlight: Task<Bool, Never>?

    init(auth: any AuthService, secrets: any SecretStore) {
        self.auth = auth
        self.secrets = secrets
    }

    func attach(_ api: APIClient) {
        self.api = api
    }

    func attach(_ circles: CircleStore) {
        self.circles = circles
    }

    // MARK: - Launch

    /// Restores a session from the Keychain, then asks the server who this is.
    ///
    /// The order is: read the refresh token → if there is none we are signed out and say so →
    /// otherwise call `GET /me` with whatever we have and let the 401 path do the refreshing.
    /// Refreshing pre-emptively at launch would spend a good refresh token on a question the
    /// next request answers for free.
    func load() async {
        loadFailure = nil
        refreshToken = try? secrets.read(Keychain.Account.refreshToken)
        guard refreshToken != nil else {
            state = .signedOut
            return
        }
        // There is a refresh token but no access token yet, so the first `GET /me` is
        // guaranteed to 401 — which is precisely the path that refreshes and retries.
        await loadIdentity()
    }

    #if DEBUG
    /// Starts the app side of a fixture-backed UI test after Apple's system sheet has been
    /// deliberately removed from scope. The real `APIClient`, identity route, DTO decoding,
    /// session routing, and every subsequent bearer request are still exercised. This method is
    /// absent from Release/TestFlight binaries.
    func startFixtureSession() async {
        accessToken = "fixture-ui-access-token"
        await loadIdentity()
    }
    #endif

    /// `GET /me` → the state (`docs/13` §4). The only place `.noProfile`, `.noGroup` and
    /// `.ready` are assigned, and every one of them is a thing the server said.
    func loadIdentity() async {
        guard let api else { return }
        loadFailure = nil
        do {
            let me = try await api.send(.me)
            user = me
            state = me.hasGroup ? .ready : .noGroup
        } catch APIError.noProfile {
            user = nil
            state = .noProfile
        } catch APIError.noGroup {
            state = .noGroup
        } catch APIError.unauthenticated {
            // `APIClient` has already ended the session by the time this lands; assigning
            // `.signedOut` again is idempotent and keeps the branch honest rather than silent.
            endSession()
        } catch let error {
            // Offline, or the server is unwell. Neither is evidence about who the caller is,
            // so identity stays unknown while the root exposes this failure and a retry.
            loadFailure = error
        }
    }

    /// What **any** endpoint's failure says about who the caller is.
    ///
    /// `docs/04` §2: *"Returns `NO_PROFILE` … the client routes to onboarding step 2 on that
    /// code"* — on the code, from wherever it arrives, and not only from `GET /me`. The two
    /// cases that carry identity are the two in the table at the top of this file, and both can
    /// come back from a route that has nothing to do with identity: a person who left their
    /// group on another device gets `NO_GROUP` from `GET /rounds/current` and belongs on step
    /// 1.3, not on a round screen showing an error they cannot act on.
    ///
    /// Every other error is ignored here on purpose. A `WRONG_PHASE` or a `NOT_FOUND` says
    /// something about a request, not about a person, and a session that moved on those would be
    /// a session that signs people out because a song lookup failed.
    func noteServerSaid(_ error: APIError) {
        // A dead session is not walked backwards into onboarding by a response that was already
        // in flight when it ended.
        guard state != .signedOut else { return }

        switch error {
        case .noProfile:
            user = nil
            state = .noProfile
        case .noGroup:
            state = .noGroup
        default:
            break
        }
    }

    // MARK: - Signing in

    /// Apple → Supabase → the Keychain → `GET /me`.
    ///
    /// Throws `AuthError`. A `.cancelled` is thrown like the rest and swallowed by the screen,
    /// because "the user closed the sheet" is a fact the caller may want and never a thing to
    /// put on screen.
    func signIn(with provider: some AppleIdentityProviding) async throws {
        let identity = try await provider.requestIdentity()
        let tokens = try await auth.signIn(with: identity)
        try adopt(tokens)
        await loadIdentity()
    }

    /// App Review fallback. The app exposes sign-in, never account creation; the durable demo
    /// account is provisioned by the owner in Supabase and kept separate from pilot identities.
    func signIn(email: String, password: String) async throws {
        let tokens = try await auth.signIn(email: email, password: password)
        try adopt(tokens)
        await loadIdentity()
    }

    // MARK: - Refreshing

    /// One refresh, on one 401 (`docs/13` §3). Returns whether a *usable* token is now in
    /// place; `false` ends the session rather than retrying against a token the server has
    /// rejected.
    ///
    /// - Parameter staleToken: the access token the failed request carried. If it is no longer
    ///   the one we hold, another request already refreshed and this caller should just retry.
    func refreshCredentials(after staleToken: String?) async -> Bool {
        // Somebody else already rotated it while this request was in flight.
        if let current = accessToken, current != staleToken { return true }
        guard refreshToken != nil else { return false }

        if let refreshInFlight { return await refreshInFlight.value }

        let task = Task { @MainActor [weak self] () -> Bool in
            guard let self, let spending = self.refreshToken else { return false }
            do {
                let tokens = try await self.auth.refresh(spending)
                try self.adopt(tokens)
                return true
            } catch {
                return false
            }
        }
        refreshInFlight = task
        let succeeded = await task.value
        refreshInFlight = nil
        return succeeded
    }

    // MARK: - Signing out

    /// The user asked to leave. Revokes the refresh token **server-side** before discarding it
    /// (`docs/14` §5) — a local-only sign-out leaves a live credential on a server that would
    /// happily mint access tokens from it for weeks.
    func signOut() async {
        if let accessToken {
            await auth.revoke(accessToken: accessToken)
        }
        endSession()
    }

    /// The other ending: the server rejected us and the one refresh did not help. Called by
    /// `APIClient`. There is nothing to revoke — the credential is already dead — so this is
    /// local, and it must not be async, because it happens inside a failing request.
    func endSession() {
        refreshInFlight?.cancel()
        refreshInFlight = nil
        accessToken = nil
        refreshToken = nil
        user = nil
        loadFailure = nil
        try? secrets.delete(Keychain.Account.refreshToken)
        try? secrets.delete(Keychain.Account.spotifyAccessToken)
        try? secrets.delete(Keychain.Account.spotifyRefreshToken)
        state = .signedOut
        circles?.reset()
    }

    // MARK: - Storage

    /// Takes a new pair: access token to memory, refresh token to the Keychain.
    ///
    /// A Keychain write that fails is fatal to the sign-in rather than a silent downgrade to a
    /// memory-only session. The downgrade would look identical until the next launch, when the
    /// user would be asked to sign in again with no explanation — and `docs/14` §5's rule is
    /// that the refresh token lives in the Keychain, not that it lives there when convenient.
    private func adopt(_ tokens: AuthTokens) throws {
        do {
            try secrets.write(tokens.refreshToken, to: Keychain.Account.refreshToken)
        } catch {
            throw AuthError.unreadable
        }
        refreshToken = tokens.refreshToken
        accessToken = tokens.accessToken
    }
}
