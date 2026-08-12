import AuthenticationServices
import SwiftUI
import UIKit

/// Apple's own button — `docs/08` §1.1: *"**Sign in with Apple** button (Apple's own, black,
/// `Radius.control`)"*.
///
/// This is a `UIViewRepresentable` rather than SwiftUI's `SignInWithAppleButton`, and the
/// reason is the nonce. `SignInWithAppleButton` performs the authorization itself and hands
/// back a `Result` in a callback; it cannot be driven by, or awaited from, the `async` wrapper
/// E09-01 requires around `ASAuthorizationController`. Splitting the button from the request
/// keeps one code path for signing in — `AppleSignIn.requestIdentity()` — instead of one for
/// the screen and another for anything else that ever needs a credential.
///
/// `CLAUDE.md` §4 rules out UIKit **view controllers**. `ASAuthorizationAppleIDButton` is a
/// `UIControl`, and it is the same control SwiftUI's wrapper draws.
struct AppleSignInButton: UIViewRepresentable {

    /// Called on tap. Held by the coordinator and replaced on every update, so a button made
    /// once never calls a closure that captured a stale view.
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(
            authorizationButtonType: .signIn,
            authorizationButtonStyle: .black
        )
        button.cornerRadius = Radius.control
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        // The button's own intrinsic width would centre it at whatever Apple thinks the label
        // needs; the screen is a single column and the primary action spans it (`docs/07` §4).
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        // **Vertically it hugs.** A `UIViewRepresentable` with no vertical hugging priority takes
        // every point SwiftUI offers it, and `SignInScreen` offers it everything between two
        // `Spacer`s — which draws Apple's 52pt control as a black panel two thirds of the screen
        // tall. The snapshot goldens cannot see this: `SnapshotRenderer` sizes a view to its
        // natural height, so there is no spare space for a greedy view to eat, and it took a
        // launch on a simulator to notice.
        button.setContentHuggingPriority(.required, for: .vertical)
        button.setContentCompressionResistancePriority(.required, for: .vertical)
        return button
    }

    func updateUIView(_ button: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.action = action
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func tapped() { action() }
    }
}
