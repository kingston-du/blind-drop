import SwiftUI

/// `docs/08` §1.3 — join first, because most users arrive via a link.
///
/// The ordering is the whole design of this screen: the code field and **Join a group** are the
/// primary action, and creating is a `SecondaryButton` underneath. One person in a group creates
/// it; everybody else joins, and putting the two side by side would make the common path a
/// choice rather than the obvious thing to do.
///
/// A `blinddrop://join/<CODE>` link lands here with the field already filled and the button
/// carrying VoiceOver focus (`docs/05` §5). **It does not join** — a link is a navigation hint,
/// not an authorization, and a forwarded message must never put somebody in a group they did not
/// choose.
struct JoinOrCreateScreen: View {
    let store: OnboardingStore

    @FocusState private var isCodeFocused: Bool
    /// Where VoiceOver lands when the field arrives already filled.
    @AccessibilityFocusState private var isJoinFocused: Bool

    var body: some View {
        content
            .padding(.horizontal, Layout.screenInset)
            .padding(.vertical, Layout.blockGap)
            .background(Palette.paper)
            .onAppear(perform: takeFocus)
            // A link that arrives while this screen is up fills the field under the user's
            // hands; the focus has to follow it, or the keyboard stays up over a code that is
            // already complete.
            .onChange(of: store.code) {
                if InviteCode.isComplete(store.code) { isCodeFocused = false }
            }
    }

    /// The screen's column, without the screen inset — see `DisplayNameScreen.snapshotContent`.
    private var content: some View {
        column(includeAccessibilityFocus: true)
    }

    /// The same column without the accessibility-focus binding.
    ///
    /// `@AccessibilityFocusState` may only be read from `body`. A snapshot renders this
    /// property from outside it, and a view that reads the binding there does not merely lose
    /// its focus behaviour — it fails to draw at all, which is how this was found: the primary
    /// button was simply absent from the golden while the space it occupies was not.
    /// `RevealScreen` splits its `@Namespace` rotor entries off for the same reason.
    var snapshotContent: some View {
        column(includeAccessibilityFocus: false)
    }

    private func column(includeAccessibilityFocus: Bool) -> some View {
        @Bindable var store = store

        return VStack(alignment: .leading, spacing: Layout.blockGap) {
            Text("onboarding.group.title")
                .typeStyle(.displayL)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: Space.none)

            VStack(alignment: .leading, spacing: Space.sm) {
                SectionLabel("onboarding.group.code.label")
                InsetField(
                    "onboarding.group.code.placeholder",
                    text: $store.code,
                    style: .monoM,
                    alignment: .leading,
                    isFocused: isCodeFocused
                )
                .focused($isCodeFocused)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textContentType(.oneTimeCode)
                .submitLabel(.join)
                .onSubmit(join)
                .accessibilityLabel(Text("onboarding.group.code.placeholder"))
                // The code alphabet has no lowercase and no `I`, `L`, `O`, `0` or `1`
                // (`docs/03` §2), so a spelled-out value is the only one a person can check
                // against the message they were sent.
                .accessibilityValue(Text(verbatim: Self.spelled(store.code)))

                if let error = store.joinFailure {
                    Text(LocalizedStringKey(error))
                        .typeStyle(.bodyM)
                        .foregroundStyle(Palette.alert)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }

            Spacer(minLength: Space.none)

            VStack(spacing: Space.sm) {
                let joinButton = PrimaryButton(
                    "onboarding.group.join",
                    fill: .neutral,
                    isEnabled: store.canJoin,
                    action: join
                )

                if includeAccessibilityFocus {
                    joinButton.accessibilityFocused($isJoinFocused)
                } else {
                    joinButton
                }

                OutlineButton("onboarding.group.create") {
                    isCodeFocused = false
                    store.startCreating()
                }
                Text("onboarding.group.help")
                    .typeStyle(.bodyS)
                    .foregroundStyle(Palette.inkDim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Space.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Prefilled → the button, empty → the field.
    ///
    /// *"Prefills the join field and focuses the button"* (`docs/05` §5). Someone who arrived by
    /// link has nothing to type, so raising a keyboard over a finished code would be six
    /// characters of work the app has already done, presented as work.
    private func takeFocus() {
        if InviteCode.isComplete(store.code) {
            isJoinFocused = true
        } else {
            isCodeFocused = true
        }
    }

    private func join() {
        guard store.canJoin else { return }
        isCodeFocused = false
        Task { await store.join() }
    }

    /// `K7MQ2X` → `K 7 M Q 2 X`, so VoiceOver spells it instead of trying to pronounce it.
    static func spelled(_ code: String) -> String {
        code.map(String.init).joined(separator: " ")
    }
}
