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
    @State private var showsReviewSignIn = false
    @State private var reviewEmail = ""
    @State private var reviewPassword = ""
    /// **How to play**, reachable before there is even a session (`docs/08` §1.1). The one place
    /// this app puts the `[?]` on its own row rather than beside a menu — there is no header here
    /// to share one with, so it gets the top-right corner to itself, the same corner it occupies
    /// everywhere else.
    @State private var isShowingHowTo = false

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.itemGap) {
            HStack(spacing: Space.none) {
                Spacer(minLength: Space.none)
                HelpButton(action: { isShowingHowTo = true })
            }

            // Capped, not plain: a bare `Spacer()` here split the leftover height evenly with
            // the one below the Apple button, and the two sides are not the same fixed content —
            // this row is a 44pt touch target, the App Review link at the foot is a shorter one —
            // so an even split always left the title block sitting visibly below true centre
            // with a lot of air over it. Capping this one keeps the gap under the help button a
            // fixed, designed distance rather than half of whatever is left, which is what moves
            // the title, subtitle and Apple button up as one block. The App Review link does not
            // move: its own position is set by the *total* leftover height, not by how the two
            // gaps split it, so capping this one alone leaves it exactly where it was. It still
            // collapses to `.none` at accessibility sizes, same as a plain `Spacer()` would, so a
            // tall title never fights it for room.
            Spacer(minLength: Space.none)
                .frame(maxHeight: Space.x6 + Space.xxl)

            Text("onboarding.title")
                .typeStyle(.displayL)
                .foregroundStyle(Palette.ink)

            Text("onboarding.subtitle")
                .typeStyle(.bodyL)
                .foregroundStyle(Palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)

            if let key = failure?.copyKey {
                Text(LocalizedStringKey(key))
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.alert)
                    .transition(.opacity)
            }

            // A little air over Apple's button, so the one control on the screen is not touching
            // the sentence that explains it. `blockGap` less the stack's own `itemGap`, so the
            // total gap is one block rather than a block plus an item.
            AppleSignInButton(action: signIn)
                .frame(maxWidth: .infinity, minHeight: Layout.buttonHeight)
                .disabled(isSigningIn)
                .opacity(isSigningIn ? 0.6 : 1)
                .accessibilityLabel(Text("onboarding.signin.apple"))
                .padding(.top, Layout.blockGap - Layout.itemGap)

            Spacer()

            // **App Review's way in, at the foot of the screen and centred.**
            //
            // It is not part of the sign-in flow — it is the door Apple's reviewer needs and
            // nobody else ever opens (`docs/14`). Keeping it in the column, directly under the
            // Apple button, made it read as a second way to sign in. At the foot and centred it
            // reads as what it is: apparatus, not a choice being offered.
            VStack(alignment: .leading, spacing: Layout.itemGap) {
                Button("onboarding.signin.review") {
                    withAnimation(.easeInOut(duration: 0.2)) { showsReviewSignIn.toggle() }
                }
                .buttonStyle(.plain)
                .typeStyle(.bodyM)
                .foregroundStyle(Palette.inkDim)
                .frame(maxWidth: .infinity, alignment: .center)

                if showsReviewSignIn {
                    InsetField("onboarding.signin.email", text: $reviewEmail)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)

                    SecureField("onboarding.signin.password", text: $reviewPassword)
                        .textContentType(.password)
                        .padding(.horizontal, Space.lg)
                        .frame(minHeight: Layout.fieldHeight)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                .fill(Palette.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                .stroke(Palette.edge, lineWidth: Stroke.border)
                        )

                    PrimaryButton("onboarding.signin.continue", fill: .neutral, isEnabled: !isSigningIn) {
                        signInForReview()
                    }
                }
            }
            .transition(.opacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Layout.screenInset)
        .padding(.top, Layout.blockGap)
        .padding(.bottom, Layout.blockGap)
        .background(Palette.paper)
        .sheet(isPresented: $isShowingHowTo) {
            HowToSheet(close: { isShowingHowTo = false })
        }
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

    private func signInForReview() {
        guard !isSigningIn else { return }
        isSigningIn = true
        failure = nil
        Task {
            do {
                try await env.session.signIn(email: reviewEmail, password: reviewPassword)
            } catch let error as AuthError {
                failure = error
            } catch {
                failure = .unreadable
            }
            isSigningIn = false
        }
    }
}
