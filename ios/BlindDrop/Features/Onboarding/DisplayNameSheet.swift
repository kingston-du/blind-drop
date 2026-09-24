import SwiftUI

/// Changing the name Apple gave you, from the first screen that shows it.
///
/// **Why this exists at all.** App Review's guideline 4 rejection (2026-09-21) says an app must
/// not ask for a name the Authentication Services framework already provided, so
/// `SessionStore.adoptAppleName(_:)` takes Apple's name and the flow skips `docs/08` §1.2
/// entirely. Adopting a name without ever showing it would trade one bad outcome for another —
/// the name people guess with (`docs/11`, `onboarding.name.help`) decided by a field on the
/// Apple ID sign-up form, discovered tomorrow night in front of the circle. `JoinOrCreateScreen`
/// states the name; this is the one tap behind it.
///
/// **Why a sheet and not a step.** A step is exactly what the rejection forbids. A sheet is
/// opened by somebody who wants it, and the person who does not open it is not delayed by a
/// single frame.
///
/// Mechanically it is `GroupNameSheet`, and deliberately so — the two are the same gesture on
/// two different names, down to the measured detent and the three focus requests that get the
/// keyboard up *with* the sheet rather than a beat behind it. See that type for the argument
/// behind each one; changing either sheet's keyboard behaviour should change both.
struct DisplayNameSheet: View {
    let store: OnboardingStore
    /// The name already saved. Seeds the field, and is what "unchanged" is measured against.
    let current: String

    @Environment(\.dismiss) private var dismiss
    @State private var measuredHeight: CGFloat = Layout.fieldHeight + Layout.buttonHeight
        + Layout.blockGap * 2
    @FocusState private var focused: Bool

    /// Valid, not in flight, and not what is already saved. Offering to write the name that is
    /// already written is a button that does nothing, dressed as one that does something.
    private var canSave: Bool { store.canContinue && store.cleanedName != current }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text("onboarding.name.title")
                .typeStyle(.displayM)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text("onboarding.name.help")
                .typeStyle(.bodyM)
                .foregroundStyle(Palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)

            nameField

            // The screen's own error line does not exist on `JoinOrCreateScreen` — it has one
            // for the invite code and nothing for the name — so a refused save with no line
            // here would read as the button doing nothing at all.
            if let error = store.nameError {
                Text(LocalizedStringKey(error))
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.alert)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PrimaryButton("onboarding.name.save", fill: .neutral, isEnabled: canSave) {
                Task { await save() }
            }
        }
        .padding(.horizontal, Layout.screenInset)
        .padding(.top, Layout.blockGap)
        .padding(.bottom, Space.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { measuredHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, height in measuredHeight = height }
            }
        }
        .background(Palette.paper)
        .presentationBackground(Palette.paper)
        .presentationDetents([.height(measuredHeight)])
        .presentationCornerRadius(Radius.sheet)
        .presentationDragIndicator(.visible)
        .defaultFocus($focused, true)
        .resigningFocus($focused)
        .onAppear {
            store.name = current
            focused = true
        }
        .task { focused = true }
    }

    private var nameField: some View {
        @Bindable var store = store

        return InsetField("onboarding.name.placeholder", text: $store.name, isFocused: focused)
            .focused($focused)
            // `.never`, with the same field on `DisplayNameScreen` and in settings (owner,
            // 2026-09-11): people who write their own name lowercase mean it.
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .onSubmit { Task { await save() } }
            .accessibilityLabel(Text("onboarding.name.title"))
    }

    private func save() async {
        guard canSave else { return }
        // Resigned before the request: the field is finished with the moment the save is
        // committed to, so the keyboard leaves with the sheet rather than a beat behind it.
        focused = false
        if await store.saveName() { dismiss() }
    }
}
