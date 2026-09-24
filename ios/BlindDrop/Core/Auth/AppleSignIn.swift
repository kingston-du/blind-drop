import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// What Apple hands back: the two things Supabase Auth needs, plus the name Apple already
/// knows.
///
/// **The name is here because App Review says it has to be** (guideline 4, 2026-09-21). This
/// request used to ask for no scopes at all, and the app then made every new user type a name
/// on `docs/08` §1.2 before it would let them continue — *"users are required to provide their
/// name … even though that information is already provided by the Authentication Services
/// framework"*. So the request asks for `.fullName`, and `SessionStore` adopts it rather than
/// asking a second time.
///
/// Still no email. The app has no use for one — there is no mail it sends and no address it
/// stores (`docs/14` §9) — and a field we do not need is a field we cannot leak.
struct AppleIdentity: Sendable, Equatable {
    /// The signed JWT from Apple. Verified by Supabase, never by us.
    let identityToken: String
    /// The **raw** nonce. Apple was given its SHA-256 digest; Supabase is given this, hashes it
    /// itself, and refuses the exchange if the two do not match. That is what stops an identity
    /// token captured off one device being replayed from another.
    let nonce: String
    /// Apple's short-lived, single-use code. Account deletion exchanges a fresh code
    /// server-side and revokes the resulting Apple token without storing it long term.
    let authorizationCode: String
    /// The display name to adopt, already cleaned and length-checked, or `nil` when Apple sent
    /// nothing usable.
    ///
    /// **Apple sends this on the first authorization of an Apple ID and never again.** Every
    /// later sign-in from the same Apple ID — a reinstall, a second device, the re-auth the
    /// account-deletion flow runs — carries `nil`, whatever scopes were asked for. That is not
    /// a gap to work around: the profile the first authorization created still holds the name,
    /// so the only caller who ever needs this is the one creating a profile.
    var suggestedName: String?
}

/// The seam the store talks to. `AppleSignIn` is the one implementation; a test supplies its
/// own, because there is no way to drive Apple's sheet from a unit test and no value in trying.
@MainActor
protocol AppleIdentityProviding {
    func requestIdentity() async throws -> AppleIdentity
}

/// `ASAuthorizationController` wrapped in an `async` API (E09-01).
///
/// The controller is a delegate-callback API that can call back exactly once, which is what
/// makes `withCheckedThrowingContinuation` the right shape rather than a convenient one. The
/// class holds the continuation and the request's nonce for the life of one authorization and
/// nothing else — a second `requestIdentity()` while one is in flight throws rather than
/// stomping the first, because resuming a continuation twice is a crash.
@MainActor
final class AppleSignIn: NSObject, AppleIdentityProviding {

    /// Whether to ask Apple for the user's name.
    ///
    /// True for signing in, where the name is the whole point of asking. **False for the
    /// account-deletion re-auth**, which needs a fresh authorization code and nothing else: the
    /// profile being deleted already has a name, and asking to see somebody's again on the way
    /// out is a permission request with no purpose behind it.
    private let requestsName: Bool

    init(requestsName: Bool = true) {
        self.requestsName = requestsName
    }

    private var pending: CheckedContinuation<AppleIdentity, any Error>?
    private var nonce: String?
    /// The controller is retained for the life of the request — `ASAuthorizationController`
    /// does not retain itself, and a deallocated one never calls its delegate.
    private var controller: ASAuthorizationController?

    func requestIdentity() async throws -> AppleIdentity {
        guard pending == nil else { throw AuthError.busy }

        let raw = Self.makeNonce()
        let request = makeRequest(nonce: raw)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        self.nonce = raw

        defer {
            self.controller = nil
            self.nonce = nil
        }
        return try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            controller.performRequests()
        }
    }

    /// The request, built where a test can look at it.
    ///
    /// Split out because the two facts that matter about this authorization are both *in the
    /// request* and neither is observable through `AppleIdentityProviding`: that the name is
    /// asked for, and that **the email never is**. `ASAuthorizationAppleIDRequest` is inert
    /// until a controller performs it, so a test can build one and read the scopes back without
    /// Apple's sheet appearing anywhere.
    func makeRequest(nonce raw: String) -> ASAuthorizationAppleIDRequest {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        // `.fullName` and nothing else. See `AppleIdentity` for why the name is asked for and
        // why the email never is.
        request.requestedScopes = requestsName ? [.fullName] : []
        request.nonce = Self.digest(of: raw)
        return request
    }

    // MARK: - The nonce

    /// 32 bytes of `SecRandomCopyBytes`, hex-encoded.
    ///
    /// `SecRandomCopyBytes` rather than `Int.random(in:)`: this is the value that makes the
    /// identity token unreplayable, and the system CSPRNG is the only source worth using for
    /// it. A failure to draw randomness is fatal — proceeding with a predictable nonce would
    /// be worse than not signing in.
    static func makeNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "the system CSPRNG refused: \(status)")
        return hex(bytes)
    }

    /// The SHA-256 of a nonce, hex-encoded — what goes to Apple. Apple copies it into the
    /// identity token's `nonce` claim, and Supabase compares that claim against the hash of the
    /// raw nonce we send it.
    static func digest(of nonce: String) -> String {
        hex(Array(SHA256.hash(data: Data(nonce.utf8))))
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - The name

    /// Apple's name components reduced to one display name, or `nil` when there is nothing
    /// usable in them.
    ///
    /// **Given name first, the full name only as a fallback.** `docs/08` §1.2 asks for *"the
    /// one your friends use"*, and the field it replaces is placeheld *"First name"* — a guess
    /// sheet listing `Ana Beltrán` next to `Dan` is reading like a contact list rather than
    /// like a room of people. The full name is used only when Apple sent no given name, which
    /// is a name somebody typed into their Apple ID as one piece, and the alternative there is
    /// nothing at all.
    ///
    /// Cleaned and length-checked by `DisplayName`, so what comes out is a name the server will
    /// accept — a 30-character Apple ID name, or one padded with invisibles, resolves to `nil`
    /// and the user is asked, which is the honest outcome rather than a silent truncation of
    /// somebody's name.
    static func displayName(from components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let candidates = [
            components.givenName,
            PersonNameComponentsFormatter.localizedString(from: components, style: .default)
        ]
        for candidate in candidates.compactMap({ $0 }) {
            let cleaned = DisplayName.clean(candidate)
            if DisplayName.problem(with: cleaned) == nil { return cleaned }
        }
        return nil
    }

    // MARK: - Delegate

    private func finish(_ result: Result<AppleIdentity, any Error>) {
        guard let continuation = pending else { return }
        pending = nil
        continuation.resume(with: result)
    }
}

extension AppleSignIn: ASAuthorizationControllerDelegate {

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let data = credential.identityToken,
            let token = String(data: data, encoding: .utf8),
            let codeData = credential.authorizationCode,
            let authorizationCode = String(data: codeData, encoding: .utf8),
            let nonce
        else {
            finish(.failure(AuthError.unreadable))
            return
        }
        finish(.success(AppleIdentity(
            identityToken: token,
            nonce: nonce,
            authorizationCode: authorizationCode,
            suggestedName: Self.displayName(from: credential.fullName)
        )))
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: any Error
    ) {
        // A cancelled sheet is not a failure and must not put an error line on the screen —
        // the user closed a thing they opened. Everything else is one error with one thing a
        // person can do about it.
        let cancelled = (error as? ASAuthorizationError)?.code == .canceled
        finish(.failure(cancelled ? AuthError.cancelled : AuthError.rejected))
    }
}

extension AppleSignIn: ASAuthorizationControllerPresentationContextProviding {

    /// The window the sheet hangs off. Reaching into `UIApplication` for it is the one thing
    /// `ASAuthorizationController` cannot do for itself, and it is a window lookup rather than
    /// a UIKit view controller — `CLAUDE.md` §4's rule is about hosting controllers in the view
    /// tree, and there are none here.
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first ?? ASPresentationAnchor()
    }
}
