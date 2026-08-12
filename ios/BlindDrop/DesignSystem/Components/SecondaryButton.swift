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
                .foregroundStyle(isEnabled ? Palette.inkDim : Palette.inkFaint)
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
