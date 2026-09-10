import SwiftUI

/// The quiet action beside the loud one — **Replace song**, **Open in Spotify**, **Skip**
/// (`docs/07` §5).
///
/// Text only: `inkDim`, `bodyL`, no border and no fill. It carries no accent on purpose. An
/// outlined secondary button would put a second emphasised control on a screen whose whole
/// layout law is one primary action, and giving it the phase colour would put the accent on
/// something that is not the point of the screen.
struct SecondaryButton: View {
    private let title: LocalizedStringKey
    private let isEnabled: Bool
    private let action: () -> Void

    init(_ title: LocalizedStringKey, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .typeStyle(.bodyL)
                .foregroundStyle(isEnabled ? Palette.inkDim : Palette.inkQuiet)
                .padding(.horizontal, Space.sm)
                .padding(.vertical, Space.sm)
                // Text-only, so nothing draws the 44pt region the finger needs (`docs/12` §5).
                .minimumTouchTarget()
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityAddTraits(.isButton)
    }
}

/// The full-width second action: a white surface, an `edge` border, an `ink` label.
///
/// Three buttons now exist and each has a job, which is why none of them is a style parameter
/// on the others. `PrimaryButton` is the thing the screen is for. `OutlineButton` is a real
/// second choice — *start a group instead of joining one*, *go back and change the song*. And
/// `SecondaryButton` is a text link for the thing that is barely a choice at all.
///
/// It never wears an accent. An accented outline would be a second amber on a screen that
/// already has one, and `CLAUDE.md` §2.5 allows exactly one.
struct OutlineButton: View {
    private let title: LocalizedStringKey
    private let isEnabled: Bool
    private let action: () -> Void

    init(_ title: LocalizedStringKey, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .typeStyle(.bodyL)
                .frame(maxWidth: .infinity)
                // A minimum, not a frame: at `.accessibility5` a two-line label makes the button
                // taller rather than being clipped by it (`docs/12` §1).
                .frame(minHeight: Layout.buttonHeight)
                .padding(.horizontal, Space.lg)
        }
        .buttonStyle(OutlineButtonStyle(isEnabled: isEnabled))
        .disabled(!isEnabled)
        .accessibilityAddTraits(.isButton)
    }
}

private struct OutlineButtonStyle: ButtonStyle {
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed && isEnabled
        configuration.label
            .outlineButtonChrome(isEnabled: isEnabled)
            // The press is carried by the surface sinking to `paper` rather than by a darker
            // fill: white has nothing darker to go to that is not simply grey.
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(isPressed ? Palette.paperSunk : Color.clear)
            )
            .scaleEffect(isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: isPressed)
    }
}
