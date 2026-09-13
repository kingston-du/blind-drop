import SwiftUI

/// A person's face, in the one visual language the app already speaks (`E28-08`).
///
/// `SealStamp` (`DesignSystem/Components/SealedCard.swift`) is a circled initial too, and it was
/// tempting to just reuse it — but that mark means *sealed*, in `amber`, and borrowing it for an
/// avatar would put the sealed/hidden accent on a screen with nothing sealed on it, which
/// `CLAUDE.md` §2.5 rules out outright. `MonogramMark` draws the same geometry — a hairline ring,
/// an inset second ring, the display face's initial — in neutral ink instead, which is what makes
/// it safe on Group, Profile and Insights: a mark, not a signal.
struct MonogramMark: View {
    let name: String
    var diameter: CGFloat = MonogramMark.diameter

    static let diameter: CGFloat = 40
    /// The roster-row and pair-list size — a mark beside a line of text, not a header.
    static let compactDiameter: CGFloat = 28

    var body: some View {
        ZStack {
            // Both rings `strokeBorder`: `stroke` would hang half of the outer ring's 2pt
            // outside the mark's own diameter, so a 40pt monogram drew 41 and the gap to the
            // inner ring was half a point tighter than `Space.xs` says it is.
            Circle().strokeBorder(Palette.inkQuiet, lineWidth: Stroke.mark)
            Circle().strokeBorder(Palette.inkQuiet, lineWidth: Stroke.border).padding(Space.xs)
            Text(verbatim: initial)
                .font(Font(Typography.fixed(.display, size: diameter * 0.46, weight: .bold)))
                .foregroundStyle(Palette.inkDim)
        }
        .frame(width: diameter, height: diameter)
        // The name beside it already carries this in every place `MonogramMark` is used; a
        // second "letter X" from the mark itself would be a duplicate VoiceOver word, not a
        // second fact.
        .accessibilityHidden(true)
    }

    private var initial: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1).uppercased()
    }
}
