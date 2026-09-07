import SwiftUI

/// Which of the two accents a screen is wearing (`docs/07` §2, §6).
///
/// > **Amber = sealed. Information is hidden.**
/// > **Ultramarine = revealed. Information is open.**
///
/// It exists as a type so that no component ever picks an accent for itself. `PrimaryButton`
/// takes one as a parameter and never reaches into `Palette` for amber; `FlightCard` takes one
/// and colours its number from it. That is what makes **exactly one accent per screen**
/// (`CLAUDE.md` §2.5) something a screen decides once, at the top, rather than a rule eleven
/// views have to remember independently.
///
/// The reveal transition is the one place both appear, and it appears here as an animation
/// between two values of this type rather than as a third case.
///
/// > **Amended (`E42-01`, owner call).** "A screen decides once" is no longer quite true, and
/// > pretending otherwise in this comment would hide the exception rather than bound it. The
/// > circle switcher lists several circles that are genuinely in different phases at the same
/// > moment, and `init(_ state: CircleState)` below exists so it can ask **per row**. That is
/// > the third carve-out from §2.5, beside the reveal transition and How to play, and it is
/// > deliberately narrow: the switcher spends the accent on a 8pt **mark** (`mark`, never
/// > `text` and never `fill`), because a mark is a signal and four accent-coloured words would
/// > be a category colour. A screen that lists cross-circle state does **not** inherit this by
/// > precedent — it needs the owner, the same as this did.
enum PhaseAccent: Sendable, Equatable, CaseIterable {
    /// Amber. The blind window: `open`, and `voided`.
    case sealed
    /// Ultramarine. The information is out: `revealed`, and `scored`.
    case revealed

    /// The accent a round's state wears (`docs/07` §6), so that a screen holding a `RoundDTO`
    /// never has to remember which side `voided` falls on. It falls on amber: nothing was
    /// revealed, so nothing is open.
    init(_ state: RoundState) {
        self = switch state {
        case .open, .voided: .sealed
        case .revealed, .scored: .revealed
        }
    }

    /// The accent a **member's own next action** wears, for the one screen that shows several
    /// circles at once (`E42-01`; see the type's note).
    ///
    /// It mirrors `init(_ state: RoundState)` deliberately, including `voided` landing on
    /// amber — *nothing was revealed, so nothing is open*. `drop` and `sealed` are both inside
    /// the blind window; `guess` and `answers` are both past the reveal. That the two
    /// initialisers agree is the point: a circle's row and that circle's own screen must never
    /// disagree about which phase it is in.
    init(_ state: CircleState) {
        self = switch state {
        case .drop, .sealed, .voided: .sealed
        case .guess, .answers: .revealed
        }
    }

    /// The fill tier — behind something, never a word and never a lone mark.
    var fill: Color {
        switch self {
        case .sealed: Palette.amber
        case .revealed: Palette.ultramarine
        }
    }

    /// The pressed fill (`docs/07` §5: *"fill darkens to the `Deep` variant"*).
    var fillPressed: Color {
        switch self {
        case .sealed: Palette.amberDeep
        case .revealed: Palette.ultramarineDeep
        }
    }

    /// What is legible **on** `fill`. White on amber is 4.23:1 and white on ultramarine is
    /// 8.98:1. Both are in the `PaletteContrastTests` table, which is why this is a lookup
    /// rather than a judgement call at the call site — and why the amber row is pinned to the
    /// large-text bar: it carries a 17pt semibold button label and is never asked to carry
    /// anything smaller.
    var onFill: Color {
        switch self {
        case .sealed: Color.white
        case .revealed: Color.white
        }
    }

    /// The drawing tier — marks, borders, icons, a card number. Both clear 3.0:1 on `surface`,
    /// which is the bar a non-text graphic has to meet.
    var mark: Color {
        switch self {
        case .sealed: Palette.amber
        case .revealed: Palette.ultramarine
        }
    }

    /// The border that closes `wash` — a badge's outline, a sealed card's edge.
    var washEdge: Color {
        switch self {
        case .sealed: Palette.amberEdge
        case .revealed: Palette.ultramarineEdge
        }
    }

    /// The writing tier — accent-coloured words on `paper` or `surface`, both above 4.5:1.
    var text: Color {
        switch self {
        case .sealed: Palette.amberText
        case .revealed: Palette.ultramarine
        }
    }

    /// The tinted surface behind accented content.
    var wash: Color {
        switch self {
        case .sealed: Palette.amberWash
        case .revealed: Palette.ultramarineWash
        }
    }
}
