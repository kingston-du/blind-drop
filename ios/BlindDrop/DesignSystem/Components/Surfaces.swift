import SwiftUI

/// The four pieces of chrome every screen in the app is assembled from.
///
/// They are here rather than repeated down twelve feature files because they are the parts a
/// reader recognises before they read anything: a white card on `paper`, a rule inside it, a
/// monospaced micro-label above it, and a badge in the corner saying what the round is doing.
/// Getting one of the four subtly wrong in one place is the difference between an app that
/// looks made and an app that looks assembled.

// MARK: - Card

/// A white surface with a hairline border, and the app's **only** elevation.
///
/// There is no shadow anywhere (`docs/07` §2). Depth comes from the value step between `paper`
/// and `surface` plus a one-point `edge`, which is why the border is not optional and why the
/// radius is a token rather than a number.
struct CardSurface: ViewModifier {
    var radius: CGFloat = Radius.card
    var fill: Color = Palette.surface
    var border: Color = Palette.edge
    var inset: CGFloat = Layout.cardInset

    func body(content: Content) -> some View {
        content
            .padding(inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(border, lineWidth: Stroke.border)
            )
    }
}

extension View {
    /// The subject card: a song being confirmed, an answer, a panel of numbers.
    func cardSurface(
        radius: CGFloat = Radius.card,
        fill: Color = Palette.surface,
        border: Color = Palette.edge,
        inset: CGFloat = Layout.cardInset
    ) -> some View {
        modifier(CardSurface(radius: radius, fill: fill, border: border, inset: inset))
    }

    /// One row of a list, drawn as its own surface. Tighter radius, tighter padding — a row is
    /// a card that has been asked to be one of many.
    func rowSurface(
        fill: Color = Palette.surface,
        border: Color = Palette.edge
    ) -> some View {
        modifier(CardSurface(
            radius: Radius.row, fill: fill, border: border, inset: Layout.rowInset
        ))
    }
}

// MARK: - Rule

/// A hairline across a card, between two things that belong to the same card.
///
/// One device pixel, not one point: at 3× a 1pt rule is three pixels of grey where the design
/// wants the thinnest line the screen can draw.
struct Rule: View {
    var color: Color = Palette.hairline
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: Stroke.hairline(atScale: displayScale))
            .accessibilityHidden(true)
    }
}

// MARK: - Micro-label

/// The monospaced, widely tracked, uppercase line that runs above a block.
///
/// It is apparatus, not prose: it names what is underneath and is never a sentence. Because it
/// is set in `label` it is also the one style in the app whose *tracking* is doing the work —
/// which is why it is a component rather than a modifier somebody has to remember to pair with
/// a colour.
struct SectionLabel: View {
    private let text: Text
    var color: Color = Palette.inkDim
    /// `.label` by default. `.labelSmall` is for the two or three places `label` itself is the
    /// thing crowding the row — a sealed card's corner links, sharing a corner with the stamp.
    var style: TypeStyle = .label

    init(_ key: LocalizedStringKey, color: Color = Palette.inkDim, style: TypeStyle = .label) {
        text = Text(key)
        self.color = color
        self.style = style
    }

    init(verbatim: String, color: Color = Palette.inkDim, style: TypeStyle = .label) {
        text = Text(verbatim: verbatim)
        self.color = color
        self.style = style
    }

    var body: some View {
        text
            .typeStyle(style)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Status badge

/// The pill in the top-right corner that says what the round is doing.
///
/// It wears the phase's wash and the phase's edge, and its words are the phase's own. It is
/// **not** a control and carries no hit region: tapping it would do nothing, so it must not
/// look like it would.
struct StatusBadge: View {
    private let text: Text
    let accent: PhaseAccent
    /// Read out as one phrase. The visible text is uppercase and abbreviated; a screen reader
    /// gets the sentence instead.
    var announcement: String?

    init(_ key: LocalizedStringKey, accent: PhaseAccent, announcement: String? = nil) {
        text = Text(key)
        self.accent = accent
        self.announcement = announcement
    }

    init(verbatim: String, accent: PhaseAccent, announcement: String? = nil) {
        text = Text(verbatim: verbatim)
        self.accent = accent
        self.announcement = announcement
    }

    var body: some View {
        text
            .typeStyle(.label)
            .foregroundStyle(accent.text)
            .padding(.horizontal, Space.md)
            .frame(minHeight: Layout.badgeHeight)
            .background(
                RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                    .fill(accent.wash)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                    .stroke(accent.washEdge, lineWidth: Stroke.border)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(announcement.map { Text(verbatim: $0) } ?? text)
            .accessibilityAddTraits(.isStaticText)
    }
}
