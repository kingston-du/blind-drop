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
    private let fill: Fill
    private let isEnabled: Bool
    private let action: () -> Void

    /// What the button is filled with.
    ///
    /// Two cases and not three: `.phase` is `docs/07` §5's *"accent from the current phase"*,
    /// and `.neutral` is for the screens that **have** no phase. Onboarding is the whole of
    /// that set — a display-name screen is neither sealed nor revealed, and a button that
    /// borrowed amber there would be using the accent decoratively, which `CLAUDE.md` §2.5
    /// forbids. `SignInScreen` already made this call for its own screen; this is the same call
    /// applied to a control.
    ///
    /// `.neutral` is `ink` filled with a `paper` label: the *first* row of `docs/07` §2's
    /// contrast table, read the other way round. It is not a new colour pair and not a third
    /// accent.
    enum Fill: Equatable, Sendable {
        case phase(PhaseAccent)
        case neutral

        var background: Color {
            switch self {
            case .phase(let accent): accent.fill
            case .neutral: Palette.ink
            }
        }

        /// The pressed fill (`docs/07` §5: *"fill darkens to the `Deep` variant"*).
        ///
        /// The neutral has no `Deep` variant to darken to — the palette's neutrals run from
        /// `ink` **upward**, and `inkDim` is lighter, so using it would make the press read as
        /// a release. Rather than invent a token, the neutral press is carried by the 0.985
        /// scale alone, which is the other half of the same 120ms gesture.
        var backgroundPressed: Color {
            switch self {
            case .phase(let accent): accent.fillPressed
            case .neutral: Palette.ink
            }
        }

        var label: Color {
            switch self {
            case .phase(let accent): accent.onFill
            case .neutral: Palette.paper
            }
        }
    }

    /// - Parameter title: a copy-deck key. The screen owns the words (`docs/11`); this view
    ///   owns their setting. Buttons name what happens and keep the name through the flow —
    ///   **Drop a song → Seal it → Sealed** (`CLAUDE.md` §6).
    init(
        _ title: LocalizedStringKey,
        fill: Fill,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.fill = fill
        self.isEnabled = isEnabled
        self.action = action
    }

    /// The phase-accented button, which is every button inside a round.
    init(
        _ title: LocalizedStringKey,
        accent: PhaseAccent,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.init(title, fill: .phase(accent), isEnabled: isEnabled, action: action)
    }

    var body: some View {
        Button(action: action) {
            PrimaryButtonLabel(title)
        }
        .buttonStyle(PrimaryButtonStyle(fill: fill, isEnabled: isEnabled))
        .disabled(!isEnabled)
        .accessibilityAddTraits(.isButton)
    }
}

/// The primary button's label, without the button.
///
/// It exists for `ShareLink`, which builds its own trigger and so cannot be given a
/// `ButtonStyle` — the invite screen's **Share invite** would otherwise be a hand-drawn copy of
/// this control living in a feature file, and the two would drift the first time either changed.
struct PrimaryButtonLabel: View {
    private let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .typeStyle(.bodyLStrong)
            .frame(maxWidth: .infinity)
            // The height is a *minimum*, not a frame: at `.accessibility5` a two-line label has
            // to make the button taller rather than being clipped by it (`docs/12` §1 — nothing
            // truncates, nothing overlaps).
            .frame(minHeight: Layout.buttonHeight)
            .padding(.horizontal, Space.lg)
    }
}

extension View {
    /// The primary button's chrome applied to a label that is not a `PrimaryButton` — again,
    /// `ShareLink`. Not a general-purpose modifier: `PrimaryButton` is the way a screen makes a
    /// primary action, and this is the one exception the platform forces.
    func primaryButtonChrome(fill: PrimaryButton.Fill) -> some View {
        foregroundStyle(fill.label)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(fill.background)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }
}

/// The press behaviour of `docs/07` §5 and `docs/09` §1: fill darkens to the `Deep` variant,
/// scale 0.985, 120ms. Disabled has no press animation, because a control that responds to
/// touch and then does nothing is worse than one that plainly does not respond.
private struct PrimaryButtonStyle: ButtonStyle {
    let fill: PrimaryButton.Fill
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed && isEnabled
        configuration.label
            .foregroundStyle(isEnabled ? fill.label : Palette.inkFaint)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(background(isPressed: isPressed))
            )
            .scaleEffect(isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: isPressed)
            .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }

    private func background(isPressed: Bool) -> Color {
        guard isEnabled else { return Palette.paperSunk }
        return isPressed ? fill.backgroundPressed : fill.background
    }
}
