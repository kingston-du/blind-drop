import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// What Apple hands back, reduced to the two things Supabase Auth needs.
///
/// There is no name and no email in here, and that is deliberate: `docs/14` §9 lists the
/// complete set of data the app collects — *"Apple sub or phone, display name, group
/// membership, song choices, guesses, APNs token"*. The display name is the one the user types
/// in `docs/08` §1.2, not the one on their Apple ID, so the request asks for no scopes at all.
/// A field we do not need is a field we cannot leak.
struct AppleIdentity: Sendable, Equatable {
    /// The signed JWT from Apple. Verified by Supabase, never by us.
    let identityToken: String
    /// The **raw** nonce. Apple was given its SHA-256 digest; Supabase is given this, hashes it
    /// itself, and refuses the exchange if the two do not match. That is what stops an identity
    /// token captured off one device being replayed from another.
    let nonce: String
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

    private var pending: CheckedContinuation<AppleIdentity, any Error>?
    private var nonce: String?
    /// The controller is retained for the life of the request — `ASAuthorizationController`
    /// does not retain itself, and a deallocated one never calls its delegate.
    private var controller: ASAuthorizationController?

    func requestIdentity() async throws -> AppleIdentity {
        guard pending == nil else { throw AuthError.busy }

        let raw = Self.makeNonce()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        // No scopes. See `AppleIdentity`.
        request.requestedScopes = []
        request.nonce = Self.digest(of: raw)

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
            let nonce
        else {
            finish(.failure(AuthError.unreadable))
            return
        }
        finish(.success(AppleIdentity(identityToken: token, nonce: nonce)))
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
