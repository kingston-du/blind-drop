import SwiftUI

/// The one primary action on a screen (`docs/07` §4: *"single column, one primary action per
/// screen"*).
///
/// Full width, 52pt, `Radius.control`, `bodyLStrong`. **The accent is a parameter and is never
/// read from `Palette` in here** — that is what makes "exactly one accent per screen"
/// (`CLAUDE.md` §2.5) a decision the screen makes once. A button that knew it was amber during
/// `open` would be a second place the phase is decided, and the client does not decide phases.
struct PrimaryButton: View {
    private let title: LocalizedStringKey
    private let accent: PhaseAccent
    private let isEnabled: Bool
    private let action: () -> Void

    /// - Parameter title: a copy-deck key. The screen owns the words (`docs/11`); this view
    ///   owns their setting. Buttons name what happens and keep the name through the flow —
    ///   **Drop a song → Seal it → Sealed** (`CLAUDE.md` §6).
    init(
        _ title: LocalizedStringKey,
        accent: PhaseAccent,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.accent = accent
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .typeStyle(.bodyLStrong)
                .frame(maxWidth: .infinity)
                // The height is a *minimum*, not a frame: at `.accessibility5` a two-line label
                // has to make the button taller rather than being clipped by it (`docs/12` §1 —
                // nothing truncates, nothing overlaps).
                .frame(minHeight: Layout.buttonHeight)
                .padding(.horizontal, Space.lg)
        }
        .buttonStyle(PrimaryButtonStyle(accent: accent, isEnabled: isEnabled))
        .disabled(!isEnabled)
        .accessibilityAddTraits(.isButton)
    }
}

/// The press behaviour of `docs/07` §5 and `docs/09` §1: fill darkens to the `Deep` variant,
/// scale 0.985, 120ms. Disabled has no press animation, because a control that responds to
/// touch and then does nothing is worse than one that plainly does not respond.
private struct PrimaryButtonStyle: ButtonStyle {
    let accent: PhaseAccent
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed && isEnabled
        configuration.label
            .foregroundStyle(isEnabled ? accent.onFill : Palette.inkFaint)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(fill(isPressed: isPressed))
            )
            .scaleEffect(isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: isPressed)
            .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }

    private func fill(isPressed: Bool) -> Color {
        guard isEnabled else { return Palette.paperSunk }
        return isPressed ? accent.fillPressed : accent.fill
    }
}
