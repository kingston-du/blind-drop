import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

enum SpotifyAuthError: Error, Equatable {
    case notConfigured
    case cancelled
    case invalidCallback
    case rejected
    case unreadable
}

/// The browser half of Spotify authorization, injectable so the PKCE round-trip is testable.
@MainActor
protocol SpotifyWebAuthenticating: AnyObject {
    func callbackURL(for authorizationURL: URL, callbackHost: String, callbackPath: String) async throws -> URL
}

/// `ASWebAuthenticationSession` with a retained session and a real presentation anchor.
@MainActor
final class SpotifyWebAuthenticationSession: NSObject, SpotifyWebAuthenticating,
    ASWebAuthenticationPresentationContextProviding {

    private var session: ASWebAuthenticationSession?

    func callbackURL(
        for authorizationURL: URL,
        callbackHost: String,
        callbackPath: String
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authorizationURL,
                callback: .https(host: callbackHost, path: callbackPath)
            ) { [weak self] callback, error in
                self?.session = nil
                if let authError = error as? ASWebAuthenticationSessionError,
                   authError.code == .canceledLogin {
                    continuation.resume(throwing: SpotifyAuthError.cancelled)
                } else if error != nil {
                    continuation.resume(throwing: SpotifyAuthError.rejected)
                } else if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(throwing: SpotifyAuthError.invalidCallback)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            self.session = session
            guard session.start() else {
                self.session = nil
                continuation.resume(throwing: SpotifyAuthError.rejected)
                return
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first ?? ASPresentationAnchor()
    }
}

private struct SpotifyTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

/// Spotify Authorization Code with PKCE. Tokens never leave the device Keychain and the client
/// secret does not exist anywhere in this target (`docs/06` §6, `docs/14` §6).
@MainActor
protocol SpotifyAuthorizing: AnyObject {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

@MainActor
final class SpotifyAuth: SpotifyAuthorizing {
    // This exact string must also be registered as a redirect URI in the Spotify dashboard;
    // Spotify rejects the authorize call outright if it is not an exact match.
    static let redirectURI = "https://blinddrop.app/spotify-auth"
    static let callbackHost = "blinddrop.app"
    static let callbackPath = "/spotify-auth"
    static let scopes = "playlist-modify-private playlist-modify-public"

    private let clientID: String
    private let secrets: any SecretStore
    private let browser: any SpotifyWebAuthenticating
    private let transport: URLSession

    init(
        clientID: String,
        secrets: any SecretStore,
        browser: any SpotifyWebAuthenticating = SpotifyWebAuthenticationSession(),
        transport: URLSession = APIClient.makeTransport()
    ) {
        self.clientID = clientID
        self.secrets = secrets
        self.browser = browser
        self.transport = transport
    }

    /// Adds the bearer token, then handles exactly one 401 by refreshing once and, if the
    /// refresh is no longer usable, authorizing again.
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let first = try await send(request, token: try await accessToken())
        guard first.1.statusCode == 401 else { return first }

        let replacement: String
        do {
            replacement = try await refresh()
        } catch {
            clearTokens()
            replacement = try await authorize()
        }
        return try await send(request, token: replacement)
    }

    func accessToken() async throws -> String {
        if let token = try secrets.read(Keychain.Account.spotifyAccessToken), !token.isEmpty {
            return token
        }
        return try await authorize()
    }

    @discardableResult
    func authorize() async throws -> String {
        guard !clientID.isEmpty else { throw SpotifyAuthError.notConfigured }

        let verifier = Self.randomURLSafe(byteCount: 64)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = Self.randomURLSafe(byteCount: 32)
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
        ]
        guard let authorizationURL = components.url else { throw SpotifyAuthError.unreadable }
        let callback = try await browser.callbackURL(
            for: authorizationURL,
            callbackHost: Self.callbackHost,
            callbackPath: Self.callbackPath
        )
        let callbackParts = URLComponents(url: callback, resolvingAgainstBaseURL: false)
        var values: [String: String] = [:]
        for item in callbackParts?.queryItems ?? [] {
            // The callback is browser-controlled input. `Dictionary(uniqueKeysWithValues:)`
            // traps on a duplicate query name; reject an ambiguous OAuth callback instead of
            // allowing a malformed URL to terminate the app.
            guard values[item.name] == nil else { throw SpotifyAuthError.invalidCallback }
            values[item.name] = item.value ?? ""
        }
        guard callback.scheme == "https", callback.host() == Self.callbackHost,
              callback.path() == Self.callbackPath,
              values["state"] == state, values["error"] == nil,
              let code = values["code"], !code.isEmpty
        else { throw SpotifyAuthError.invalidCallback }

        return try await exchange([
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code_verifier", value: verifier),
        ], keepingRefreshToken: nil)
    }

    @discardableResult
    func refresh() async throws -> String {
        guard !clientID.isEmpty else { throw SpotifyAuthError.notConfigured }
        guard let refresh = try secrets.read(Keychain.Account.spotifyRefreshToken), !refresh.isEmpty
        else { throw SpotifyAuthError.rejected }
        return try await exchange([
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refresh),
            URLQueryItem(name: "client_id", value: clientID),
        ], keepingRefreshToken: refresh)
    }

    private func exchange(
        _ form: [URLQueryItem],
        keepingRefreshToken existing: String?
    ) async throws -> String {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = form
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)

        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let token = try? JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
        else { throw SpotifyAuthError.rejected }
        try secrets.write(token.accessToken, to: Keychain.Account.spotifyAccessToken)
        if let refresh = token.refreshToken ?? existing {
            try secrets.write(refresh, to: Keychain.Account.spotifyRefreshToken)
        }
        return token.accessToken
    }

    private func send(_ request: URLRequest, token: String) async throws -> (Data, HTTPURLResponse) {
        var authorized = request
        authorized.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport.data(for: authorized)
        guard let http = response as? HTTPURLResponse else { throw SpotifyAuthError.unreadable }
        return (data, http)
    }

    private func clearTokens() {
        try? secrets.delete(Keychain.Account.spotifyAccessToken)
        try? secrets.delete(Keychain.Account.spotifyRefreshToken)
    }

    static func randomURLSafe(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        precondition(status == errSecSuccess, "the system CSPRNG refused: \(status)")
        return base64URL(Data(bytes))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
