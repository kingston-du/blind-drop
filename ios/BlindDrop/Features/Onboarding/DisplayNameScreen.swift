import SwiftUI

/// `docs/08` §1.2 — the name people will be guessing with.
///
/// One prompt, one help line, one field, one button. The help line is doing real work and is not
/// decoration: it is the only place the app explains **why** the name matters, and a person who
/// types `xX_dan_Xx` here because they thought it was a username has a worse time every night
/// for the rest of the group's life.
///
/// Reached whenever the server says `NO_PROFILE`, from any endpoint and not only at first
/// launch (`docs/04` §2) — `SessionStore.noteServerSaid(_:)` is what makes that true, and
/// `APIClient` is what calls it.
struct DisplayNameScreen: View {
    let store: OnboardingStore

    /// Raised on appearance. There is one field and nothing else to do on this screen; making
    /// somebody tap it first is a tap that buys nothing, and `docs/08` §1 budgets the whole
    /// flow at thirty seconds.
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        snapshotContent
            .padding(.horizontal, Layout.screenInset)
            .padding(.vertical, Layout.blockGap)
            .background(Palette.paper)
            .onAppear { isFieldFocused = true }
    }

    /// The screen's column, without the screen inset.
    ///
    /// Separated for the snapshots, which supply the inset themselves — a column carrying its
    /// own would be indented twice, costing 40pt and wrapping a title that fits perfectly well
    /// on the device (`SnapshotRenderer`). Every onboarding screen exposes this under the same
    /// name, which is the one `RevealScreen` already uses.
    var snapshotContent: some View {
        @Bindable var store = store

        return VStack(alignment: .leading, spacing: Layout.blockGap) {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("onboarding.name.title")
                    .typeStyle(.displayM)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text("onboarding.name.help")
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: Space.sm) {
                InsetField(
                    "onboarding.name.placeholder",
                    text: $store.name,
                    isFocused: isFieldFocused
                )
                    .focused($isFieldFocused)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.continue)
                    .onSubmit(save)
                    .accessibilityLabel(Text("onboarding.name.title"))

                // Inline, under the field, in `alert` — never a modal (`docs/08` §1.2). A modal
                // for a four-word correction takes the field away from the person fixing it.
                if let error = store.nameError {
                    Text(LocalizedStringKey(error))
                        .typeStyle(.bodyM)
                        .foregroundStyle(Palette.alert)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }

            Spacer(minLength: Space.none)

            PrimaryButton(
                "onboarding.continue",
                fill: .neutral,
                isEnabled: store.canContinue,
                action: save
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func save() {
        guard store.canContinue else { return }
        isFieldFocused = false
        Task { await store.saveName() }
    }
}
