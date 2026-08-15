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
        return button
    }

    /// Apple's UIKit control has a short intrinsic height. Returning the design-system height
    /// here makes the black control itself 56pt tall; a SwiftUI frame alone would only make a
    /// 56pt transparent wrapper around Apple's visibly smaller button.
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: ASAuthorizationAppleIDButton,
        context: Context
    ) -> CGSize? {
        CGSize(
            width: proposal.width ?? uiView.intrinsicContentSize.width,
            height: Layout.buttonHeight
        )
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
