import SwiftUI

/// A name token in the guess sheet (`docs/07` §5).
///
/// Pill, `Radius.pill`, 36pt tall, `bodyM`. Three states, and the consumed one is the reason
/// this component has an accessibility contract at all:
///
/// - **Unused** — `surface` fill, `edge` border, `ink` label.
/// - **Consumed** (already assigned to a card) — `paperSunk` fill, `inkFaint` label, 0.6
///   opacity. **Still tappable**: tapping moves it.
/// - **Selected** — `ultramarine` fill, white label.
///
/// `docs/12` §3: *"Consumed name chips are at 0.6 opacity **and** carry a state change in their
/// accessibility value. Opacity alone is not a status indicator."* A VoiceOver user gets the
/// same fact the sighted user gets from the dimming — which card the name is currently on.
struct NameChip: View {
    let member: MemberDTO
    let state: State
    let action: () -> Void

    /// A chip's three states. `.consumed` carries the card number it went to, because *"already
    /// used"* is not the fact — *"on No. 3"* is, and it is what the announcement says.
    enum State: Equatable {
        case unused
        case consumed(cardNumber: Int)
        case selected

        var assignedCardNumber: Int? {
            if case let .consumed(cardNumber) = self { cardNumber } else { nil }
        }
    }

    var body: some View {
        Button(action: action) {
            Text(verbatim: member.displayName)
                .typeStyle(.bodyM)
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .padding(.horizontal, Space.md)
                .frame(minHeight: Layout.chipHeight)
                .background(
                    RoundedRectangle(cornerRadius: Radius.pill, style: .continuous).fill(fill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                        .stroke(border, lineWidth: Stroke.border)
                )
                .opacity(state == .unused || state == .selected ? 1 : 0.6)
                // 36pt drawn, 44pt tapped — the chip's spacing is part of its hit region
                // (`docs/12` §5), so a row of chips has no dead gaps between them.
                .frame(minHeight: Layout.minimumTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            Copy.A11y.nameChip(member.displayName, assignedTo: state.assignedCardNumber)
        )
        .accessibilityAddTraits(state == .selected ? [.isButton, .isSelected] : .isButton)
    }

    private var fill: Color {
        switch state {
        case .unused: Palette.surface
        case .consumed: Palette.paperSunk
        case .selected: Palette.ultramarine
        }
    }

    private var border: Color {
        switch state {
        case .unused: Palette.edge
        case .consumed: Palette.paperSunk
        case .selected: Palette.ultramarine
        }
    }

    private var labelColor: Color {
        switch state {
        case .unused: Palette.ink
        case .consumed: Palette.inkFaint
        case .selected: Color.white
        }
    }
}
