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

    /// The name the caller is playing under, or `nil` before the server has said who they are.
    ///
    /// **Passed in rather than read off the session**, which is what lets the goldens render
    /// this screen with and without a name and without a test-only hook in `SessionStore` — the
    /// rule `OnboardingSnapshots` already states about the `NOT_FOUND` line.
    var playingAs: String?

    @FocusState private var isCodeFocused: Bool
    /// The rename sheet. This screen is the first thing a new user sees now that
    /// `SessionStore.adoptAppleName(_:)` takes the name from Apple, so it is also the first
    /// chance they get to disagree with it.
    @State private var isRenaming = false
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
            .sheet(isPresented: $isRenaming) {
                DisplayNameSheet(store: store, current: playingAs ?? "")
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
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("onboarding.group.title")
                    .typeStyle(.displayL)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let playingAs, !playingAs.isEmpty {
                    identityRow(playingAs)
                }
            }

            Spacer(minLength: Space.none)

            VStack(alignment: .leading, spacing: Space.sm) {
                SectionLabel("onboarding.group.code.label")
                InsetField(
                    "onboarding.group.code.placeholder",
                    // One write per edit, through the store's own setter — see
                    // `OnboardingStore.code` for the two ways of doing this that do not work
                    // and what each of them looked like on screen.
                    text: Binding(get: { store.code }, set: { store.setCode($0) }),
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

    /// **Who you are playing as, and the way to change it.**
    ///
    /// This row exists because of App Review's guideline 4 rejection (2026-09-21) and the fix
    /// for it: the name now arrives from Apple and `docs/08` §1.2 is skipped, so without this
    /// the first time anybody saw the name they would be guessed by is in tomorrow night's
    /// guess sheet. It is a statement with one affordance on it, not a step — nothing here
    /// blocks joining, which is the whole point of the rejection.
    ///
    /// Quiet on purpose: the sentence is `inkDim`, only the verb is `ink`, and there is no
    /// accent on it (`CLAUDE.md` §2.5 — this screen is in neither phase). VoiceOver gets one
    /// button rather than two labels and a word.
    private func identityRow(_ name: String) -> some View {
        let playing = Text(verbatim: Copy.format("onboarding.group.identity", name))
            .typeStyle(.bodyM)
            .foregroundStyle(Palette.inkDim)
        let change = Text("onboarding.group.identity.change")
            .typeStyle(.bodyM)
            .foregroundStyle(Palette.ink)

        return Button {
            isCodeFocused = false
            isRenaming = true
        } label: {
            // **`ViewThatFits`, not `dynamicTypeSize`.** At `.accessibility5` on an SE the two
            // pieces do not share a line: the sentence wraps to two and the verb floats beside
            // it, vertically centred against nothing. Every other reflow in the app decides
            // this from `dynamicTypeSize` (`FlightCard.isStacked`), and that is exactly what
            // cannot be done here — `snapshotContent` is rendered outside this view's `body`,
            // where an `@Environment` read resolves to the default and the golden would be a
            // picture of a screen at `.large` wearing an `.accessibility5` label. A fit is
            // measured rather than read, so it is true in both places.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.sm) {
                    playing.lineLimit(1)
                    change.lineLimit(1)
                }

                VStack(alignment: .leading, spacing: Space.xxs) {
                    playing.fixedSize(horizontal: false, vertical: true)
                    change.fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: Layout.minimumTouchTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("onboarding.group.identity.change"))
        .accessibilityValue(Text(verbatim: name))
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
