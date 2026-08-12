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

    /// What is legible **on** `fill`. `ink` on amber is 6.74:1; white on ultramarine is 7.26:1.
    /// Both are in the `PaletteContrastTests` table, which is why this is a lookup rather than a
    /// judgement call at the call site.
    var onFill: Color {
        switch self {
        case .sealed: Palette.ink
        case .revealed: Color.white
        }
    }

    /// The drawing tier — marks, borders, icons, a card number. `amberDeep` clears 3.0:1 on
    /// `surface`; `amber` does not, which is the whole reason the amber is split in three.
    var mark: Color {
        switch self {
        case .sealed: Palette.amberDeep
        case .revealed: Palette.ultramarine
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
