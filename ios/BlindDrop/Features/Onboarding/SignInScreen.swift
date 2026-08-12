import SwiftUI

/// `docs/08` §1.1. One screen: the app's name, one line of what this is, and Apple's button.
///
/// There is deliberately **no `SignInStore`**. `docs/13` §2 gives each feature a store for the
/// state it owns, and this screen owns almost none — the session is `SessionStore`'s, and the
/// routing off it is `RootView`'s. What is left is "a request is in flight" and "the last one
/// failed", which are two pieces of view state and belong in the view.
///
/// No accent (`CLAUDE.md` §2.5). Amber means sealed and ultramarine means revealed; neither is
/// true of a sign-in screen, and a screen that borrowed one would be using it decoratively.
struct SignInScreen: View {
    @Environment(AppEnvironment.self) private var env

    @State private var isSigningIn = false
    @State private var failure: AuthError?

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.itemGap) {
            Spacer()

            Text("onboarding.title")
                .typeStyle(.displayL)
                .foregroundStyle(Palette.ink)

            Text("onboarding.subtitle")
                .typeStyle(.bodyL)
                .foregroundStyle(Palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            if let key = failure?.copyKey {
                Text(LocalizedStringKey(key))
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.alert)
                    .transition(.opacity)
            }

            AppleSignInButton(action: signIn)
                .frame(maxWidth: .infinity, minHeight: Layout.buttonHeight)
                .disabled(isSigningIn)
                .opacity(isSigningIn ? 0.6 : 1)
                .accessibilityLabel(Text("onboarding.signin.apple"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Layout.screenInset)
        .padding(.bottom, Layout.blockGap)
        .background(Palette.paper)
    }

    private func signIn() {
        guard !isSigningIn else { return }
        isSigningIn = true
        failure = nil
        Task {
            do {
                // Built per attempt, not held: it owns a live continuation for exactly as long
                // as Apple's sheet is up, and a long-lived instance would be something a second
                // tap could interrupt.
                try await env.session.signIn(with: AppleSignIn())
            } catch let error as AuthError {
                // `.cancelled` and `.busy` resolve to no copy key: the user closed a sheet they
                // opened, and nothing should appear on screen because of it.
                failure = error
            } catch {
                failure = .unreadable
            }
            isSigningIn = false
        }
    }
}
