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
    /// The resolved name the reveal screen shows. It differs from `member.displayName` only
    /// when two people share a first name (`Sam B.` / `Sam K.`); identity and interaction stay
    /// on `userID`, never on what happens to fit on the chip.
    var displayName: String?
    let state: State
    let action: () -> Void
    /// Why this chip cannot be used, when it cannot (`E11-05`). Present for a non-submitter and
    /// for someone who joined after the reveal; `nil` in the ordinary case.
    ///
    /// It carries the reason into the **label**, which is `docs/12` §2's requirement, and it
    /// drops `.accessibilityRespondsToUserInteraction` so VoiceOver stops offering an activation
    /// that does nothing. The chip stays visible and stays in the pool: `docs/08` §6 wants the
    /// apparatus *disabled, not hidden*, because the user has to see exactly what they missed.
    var unavailableReason: String?
    /// The accessibility-size pool is two columns wide, so a long, resolved name must grow its
    /// chip rather than disappear behind a one-line truncation.
    var allowsWrapping = false
    /// How big the pill is drawn (`E41-01`). Everything else about the chip — the consumed
    /// strike, the selected fill, the accessibility value `docs/12` §3 requires — is identical
    /// across both, which is the whole reason this is a size and not a second component.
    var size: Size = .regular

    /// The two scales a name is offered at.
    enum Size: Equatable {
        /// The call sheet's pool: apparatus under a flight (`docs/07` §5).
        case regular
        /// The quick pass's pool: the screen's one action (`E41-01`).
        case large

        var height: CGFloat {
            switch self {
            case .regular: Layout.chipHeight
            case .large: Layout.chipHeightLarge
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .regular: Space.md
            case .large: Space.xl
            }
        }

        /// Whether the pill takes the width it is offered.
        ///
        /// The call sheet's row is scrolled and ragged on purpose — a pill sized to its own name,
        /// with `nameChipMinimumWidth` as the floor that keeps *Jo* from drawing a target half
        /// the size of *Hana*'s. The quick pass's pool is a grid, and a grid of pills that each
        /// stop at their own word is not a grid: it is a scatter of ellipses with the column
        /// gutters showing through. Filling the column is what makes it read as one set of
        /// targets, and it is what makes the pill a stadium rather than an oval.
        var fillsColumn: Bool { self == .large }
    }

    /// `Layout.nameChipMinimumWidth`, scaled with the body text it sits behind (`E26-02`).
    ///
    /// Scaled rather than constant because the floor is expressed in characters — *about six* —
    /// and a character is not a fixed number of points. A 72-point floor against 17-point text is
    /// a comfortable pill; the same 72 against `accessibility2`'s 28-point text is narrower than
    /// the word inside it, which puts the floor below the natural width and makes it do nothing
    /// at exactly the sizes where an even row of targets matters most.
    @ScaledMetric(relativeTo: .body) private var minimumWidth = Layout.nameChipMinimumWidth

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
            Text(verbatim: name)
                .typeStyle(.bodyL)
                .foregroundStyle(labelColor)
                // A name already spent on another card is struck through as well as dimmed.
                // **Colour is never the only signal** (`docs/12` §3), and "used" is exactly the
                // kind of state that would otherwise be a shade of grey and nothing else.
                .strikethrough(state.assignedCardNumber != nil, color: Palette.inkQuiet)
                .lineLimit(allowsWrapping ? nil : 1)
                .multilineTextAlignment(.center)
                .padding(.horizontal, size.horizontalPadding)
                // The pill has a floor as well as a height (`E26-02`). Without it the row is as
                // ragged as the names in it — "Jo" draws a 40-point target next to a 90-point
                // one — and picking a name becomes an aiming problem rather than a reading one.
                //
                // **Only in the row.** `allowsWrapping` marks the accessibility-size grid, whose
                // two flexible columns already give every chip the same width — so the floor has
                // no evening-out left to do there, and it does harm: a 72-point floor scaled to
                // `accessibility5` is over 200, wider than half an SE, and the columns overlap
                // into each other rather than sitting side by side.
                .frame(
                    minWidth: allowsWrapping ? nil : minimumWidth,
                    maxWidth: size.fillsColumn ? .infinity : nil,
                    minHeight: size.height
                )
                .background(
                    RoundedRectangle(cornerRadius: Radius.pill, style: .continuous).fill(fill)
                )
                // `strokeBorder` so the outline sits exactly on the fill's edge instead of
                // straddling it — at `Radius.pill` the chip's ends are apexes, where a half-point
                // of line outside the bounds antialiases unevenly against the paper.
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                        .strokeBorder(border, lineWidth: Stroke.border)
                )
                .opacity(state == .unused || state == .selected ? 1 : 0.6)
                // 36pt drawn, 44pt tapped — the chip's spacing is part of its hit region
                // (`docs/12` §5), so a row of chips has no dead gaps between them.
                .frame(minHeight: Layout.minimumTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("nameChip.\(member.userID)")
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(state == .selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityRespondsToUserInteraction(unavailableReason == nil)
    }

    var accessibilityLabel: String {
        if let unavailableReason {
            return Copy.A11y.nameChip(name, unavailable: unavailableReason)
        }
        return name
    }

    var accessibilityValue: String {
        guard unavailableReason == nil else { return "" }
        return Copy.A11y.nameChipValue(assignedTo: state.assignedCardNumber)
    }

    private var name: String { displayName ?? member.displayName }

    private var fill: Color {
        switch state {
        case .unused, .consumed: Palette.surface
        case .selected: Palette.ultramarine
        }
    }

    private var border: Color {
        switch state {
        case .unused, .consumed: Palette.edge
        case .selected: Palette.ultramarine
        }
    }

    private var labelColor: Color {
        switch state {
        case .unused: Palette.ink
        case .consumed: Palette.inkQuiet
        case .selected: Color.white
        }
    }
}
