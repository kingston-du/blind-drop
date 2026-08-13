import Foundation

/// A session, as Supabase Auth returns it. Two strings, and nothing else is kept.
///
/// There is no `expiresIn` here on purpose. The app refreshes **reactively**, on the one 401
/// the server actually issues (`docs/13` §3), rather than pre-emptively against a deadline —
/// and a deadline would have to be compared against a clock, which on this client means
/// `ServerClock`, which is anchored by API responses, which is exactly the thing that has just
/// failed. Reacting to the server is both simpler and the only version that cannot be wrong.
struct AuthTokens: Sendable, Equatable {
    let accessToken: String
    let refreshToken: String
}

/// The calls the app makes to Supabase Auth (`docs/14` §5).
///
/// Not `APIClient`: these are not our API. They live under `/auth/v1` rather than
/// `/functions/v1`, they are not wrapped in `docs/04` §1's envelope, they carry no `server_now`
/// to anchor the clock with, and they authenticate with the anon key rather than a bearer
/// token. Routing them through the app's client would mean teaching it a second wire format
/// for three requests.
@MainActor
protocol AuthService {
    /// Trades an Apple identity token for a Supabase session.
    func signIn(with identity: AppleIdentity) async throws -> AuthTokens
    /// Review-only credential sign-in. There is no public sign-up UI.
    func signIn(email: String, password: String) async throws -> AuthTokens
    /// Spends a refresh token for a new pair. Supabase rotates: the old one is dead afterwards.
    func refresh(_ refreshToken: String) async throws -> AuthTokens
    /// Revokes the session **server-side** (`docs/14` §5). Best effort by design — see below.
    func revoke(accessToken: String) async
}

/// Supabase Auth over `URLSession`.
@MainActor
struct SupabaseAuthService: AuthService {

    /// `https://<project>.supabase.co/auth/v1`.
    let baseURL: URL
    /// The publishable anon key, sent as `apikey`. Public by design — it grants nothing on its
    /// own, because every table is deny-by-default under RLS and PostgREST is not client
    /// reachable (`docs/14` §4).
    let anonKey: String
    let transport: URLSession

    init(configuration: AppConfiguration, transport: URLSession = APIClient.makeTransport()) {
        self.baseURL = configuration.authBaseURL
        self.anonKey = configuration.anonKey
        self.transport = transport
    }

    // MARK: - The three calls

    func signIn(with identity: AppleIdentity) async throws -> AuthTokens {
        try await token(
            grant: "id_token",
            body: IdTokenGrant(provider: "apple", idToken: identity.identityToken, nonce: identity.nonce)
        )
    }

    func signIn(email: String, password: String) async throws -> AuthTokens {
        try await token(grant: "password", body: PasswordGrant(email: email, password: password))
    }

    func refresh(_ refreshToken: String) async throws -> AuthTokens {
        try await token(grant: "refresh_token", body: RefreshGrant(refreshToken: refreshToken))
    }

    /// `scope=local` — this device's session, not every device the person is signed in on.
    /// Signing out of a phone should not sign out the iPad in the kitchen.
    ///
    /// It returns `Void` and swallows its failures because the caller has already decided the
    /// session is over. A sign-out that could fail would leave the app signed in on a screen
    /// the user has already left; the token is discarded locally either way, and an unrevoked
    /// refresh token that nothing holds expires on its own.
    func revoke(accessToken: String) async {
        var request = post("logout", query: [URLQueryItem(name: "scope", value: "local")])
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        _ = try? await transport.data(for: request)
    }

    // MARK: - Transport

    private func token(grant: String, body: some Encodable & Sendable) async throws -> AuthTokens {
        var request = post("token", query: [URLQueryItem(name: "grant_type", value: grant)])
        request.httpBody = try? JSONEncoder().encode(body)
        guard request.httpBody != nil else { throw AuthError.unreadable }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch {
            throw AuthError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw AuthError.unreadable }
        guard (200..<300).contains(http.statusCode) else {
            // Every refusal from the identity provider is the same thing to a person standing
            // at a sign-in screen: it did not work, try again. The distinction that *does*
            // matter — a dead refresh token versus a network that is down — is the difference
            // between `.rejected` and `.offline`, and it is already made above.
            throw AuthError.rejected
        }
        guard let decoded = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw AuthError.unreadable
        }
        return AuthTokens(accessToken: decoded.accessToken, refreshToken: decoded.refreshToken)
    }

    private func post(_ path: String, query: [URLQueryItem]) -> URLRequest {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        components?.queryItems = query
        var request = URLRequest(url: components?.url ?? baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !anonKey.isEmpty {
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
        }
        return request
    }
}

// MARK: - The wire
//
// Supabase Auth's own shapes, snake case included. These types exist to be the JSON.

private struct IdTokenGrant: Encodable, Sendable {
    let provider: String
    let idToken: String
    let nonce: String

    enum CodingKeys: String, CodingKey {
        case provider, nonce
        case idToken = "id_token"
    }
}

private struct RefreshGrant: Encodable, Sendable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

private struct PasswordGrant: Encodable, Sendable {
    let email: String
    let password: String
}

/// Supabase returns a good deal more than this — `expires_in`, `token_type`, the whole user
/// object. Decoding two fields is the point: what is not decoded cannot be stored, and
/// `docs/14` §9's list of what the app holds is short on purpose.
private struct TokenResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

// MARK: - Failure

/// What can go wrong signing in, and the copy each case shows.
///
/// The keys are `docs/11`'s existing error rows — signing in does not get its own vocabulary of
/// failure, because from the user's side there are only three outcomes: nothing happened, the
/// network is down, or it did not work.
enum AuthError: Error, Equatable {
    /// The user dismissed Apple's sheet. **Not** an error state: nothing is shown.
    case cancelled
    /// A request already in flight. A second tap while the sheet is up.
    case busy
    case offline
    /// Apple or Supabase refused. A revoked Apple ID, a dead refresh token, a bad nonce.
    case rejected
    /// The response was not the shape it claims to be, or the Keychain would not hold the token.
    case unreadable

    /// The copy-deck key, or `nil` when the right thing to show is nothing at all.
    var copyKey: String? {
        switch self {
        case .cancelled, .busy: nil
        case .offline: "error.offline"
        case .rejected, .unreadable: "error.generic"
        }
    }
}
