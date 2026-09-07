import SwiftUI

/// A **row-scale** affirmative: filled, pill-shaped, sized to its own words rather than to the
/// screen (`E38-01`).
///
/// The app already had three buttons and a text link, and every one of them is full width.
/// That is right for `docs/07` §4's *"one primary action per screen"* and wrong inside a card
/// that is one of several — the switcher's invitation used a full-bleed `PrimaryButton` and
/// became the loudest thing on a sheet whose job is switching between circles. This is the
/// missing size: an action that belongs to a row, sitting beside a `SecondaryButton` on the
/// same line.
///
/// It takes `PrimaryButton.Fill` rather than reading `Palette`, for that type's own reason —
/// *"exactly one accent per screen" is a decision the screen makes once* (`CLAUDE.md` §2.5).
///
/// Drawn at the full 44pt touch target rather than at `Layout.chipHeight` with a larger hit
/// region behind it. A chip is a label you may tap; this is a button, and a button that is
/// smaller than the region that answers for it is how two adjacent actions end up overlapping
/// each other's targets.
struct PillButton: View {
    /// Filled or outlined, and the difference is **how many of it there are**.
    ///
    /// A filled pill is right when the row it sits in is the thing to act on — the switcher's
    /// one pending invitation. It is wrong repeated: the invite panel's shortlist can be a dozen
    /// names, and a dozen black lozenges down one card is a column of shouting, with the
    /// screen's actual primary action (**Share invite**) drowned by the list beneath it. So the
    /// repeated one outlines, and the emphasis stays with whatever there is only one of.
    enum Style: Equatable {
        case filled(PrimaryButton.Fill)
        case outlined

        static var filled: Style { .filled(.neutral) }
    }

    private let title: LocalizedStringKey
    private let style: Style
    private let isEnabled: Bool
    private let fillsWidth: Bool
    private let action: () -> Void

    /// - Parameter fillsWidth: takes all the width offered instead of sizing to its own words.
    ///   Off by default, because sizing to its words is the whole reason this control exists —
    ///   an action that belongs to a row, not to a screen. On for a **pair** sharing a row
    ///   (`CircleSwitcherSheet`'s footer), where two pills sized to their own words leave a
    ///   ragged right edge and make the shorter label look like the lesser action rather than
    ///   the shorter one.
    init(
        _ title: LocalizedStringKey,
        style: Style = .filled(.neutral),
        isEnabled: Bool = true,
        fillsWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.style = style
        self.isEnabled = isEnabled
        self.fillsWidth = fillsWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .typeStyle(.bodyLStrong)
                // Two lines rather than one at accessibility sizes: a filled pill that is
                // exactly as wide as its neighbour cannot also be as wide as its longest word.
                .multilineTextAlignment(.center)
                .padding(.horizontal, fillsWidth ? Space.md : Space.xl)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                // A minimum, not a frame: at `.accessibility5` the label makes the pill taller
                // rather than being clipped by it (`docs/12` §1).
                .frame(minHeight: Layout.minimumTouchTarget)
        }
        .buttonStyle(PillButtonStyle(style: style, isEnabled: isEnabled))
        .disabled(!isEnabled)
        .accessibilityAddTraits(.isButton)
    }
}

/// `PrimaryButtonStyle`'s press behaviour (`docs/07` §5, `docs/09` §1) at pill radius. It is a
/// separate type rather than a parameter on that one because that one is `private` to its file
/// and because the two differ in exactly one token; sharing them would mean exporting a style
/// so a radius could be passed through it.
private struct PillButtonStyle: ButtonStyle {
    let style: PillButton.Style
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed && isEnabled
        let shape = RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
        return configuration.label
            .foregroundStyle(label)
            .background(shape.fill(background(isPressed: isPressed)))
            .overlay(border.map { shape.stroke($0, lineWidth: Stroke.border) })
            .scaleEffect(isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: isPressed)
            .contentShape(shape)
    }

    private var label: Color {
        guard isEnabled else { return Palette.inkFaint }
        switch style {
        case .filled(let fill): return fill.label
        case .outlined: return Palette.ink
        }
    }

    /// Only the outlined one has an edge; a fill needs no border to be seen.
    private var border: Color? {
        guard case .outlined = style else { return nil }
        return isEnabled ? Palette.edgeStrong : Palette.edge
    }

    private func background(isPressed: Bool) -> Color {
        guard isEnabled else { return Palette.paperSunk }
        switch style {
        case .filled(let fill):
            return isPressed ? fill.backgroundPressed : fill.background
        case .outlined:
            // White sinks to `paperSunk` on press, the same way `OutlineButton` does — there is
            // nothing darker for white to become that is not simply grey.
            return isPressed ? Palette.paperSunk : Palette.surface
        }
    }
}
