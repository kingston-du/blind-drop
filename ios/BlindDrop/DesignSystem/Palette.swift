import SwiftUI

/// The sixteen colour tokens of `docs/07` §2, transcribed exactly.
///
/// Two accents carry meaning and appear nowhere decoratively (`CLAUDE.md` §2.5):
///
/// - **Amber = sealed.** Information is hidden.
/// - **Ultramarine = revealed.** Information is open.
///
/// Exactly one accent per screen, except during the reveal transition where amber gives way
/// to ultramarine. A user should be able to tell what phase the round is in from across the
/// room, which only works if neither accent is ever used to decorate.
///
/// Light mode only (`CLAUDE.md` §2.4). Every token is one value. There is no `Color(light:dark:)`
/// here and there is no `colorScheme` branch anywhere in the app — `PaletteContrastTests`
/// scans the source tree to keep that true rather than trusting it.
enum Palette {

    /// The raw sRGB literals, and the only place a hex is written down.
    ///
    /// `Palette`'s `Color` values and `PaletteContrastTests` both read from here. That is the
    /// point: a second copy of a hex in the test would make the test agree with itself rather
    /// than with the palette, and a wrong hex would ship. With one source of truth, editing a
    /// token moves the computed contrast ratio and the test fails with the row that broke.
    enum Hex {
        // Neutrals — cool, never warm. No cream, no oat, no beige.
        static let paper: UInt32       = 0xF3F4F7
        static let paperSunk: UInt32   = 0xE8EAEF
        static let surface: UInt32     = 0xFFFFFF
        static let edge: UInt32        = 0xDEE1E9
        static let edgeStrong: UInt32  = 0xC4C9D6

        static let ink: UInt32         = 0x14161C
        static let inkDim: UInt32      = 0x5A6072
        static let inkFaint: UInt32    = 0x7C8294

        // Amber — three tiers, each with a job. Do not interchange them.
        static let amber: UInt32       = 0xE08A1E
        static let amberDeep: UInt32   = 0xB96D0C
        static let amberText: UInt32   = 0x8F5411
        static let amberWash: UInt32   = 0xFDF3E3

        // Ultramarine — one token does text, fill, and graphics.
        static let ultramarine: UInt32     = 0x2C3FE0
        static let ultramarineDeep: UInt32 = 0x1E2CA8
        static let ultramarineWash: UInt32 = 0xEEF0FE

        static let alert: UInt32       = 0xB3261E
    }

    // MARK: - Neutrals
    // Cool, never warm. No cream, no oat, no beige.

    /// Base background. Every screen sits on this.
    static let paper       = Color(hex: Hex.paper)
    /// Inset fields, search bar. Also the disabled-control fill (`docs/07` §2 usage table).
    static let paperSunk   = Color(hex: Hex.paperSunk)
    /// Cards. `surface` on `paper` plus a 1pt `edge` border is the app's only elevation —
    /// there is no shadow anywhere (`docs/07` §2, Elevation).
    static let surface     = Color(hex: Hex.surface)
    /// Hairline borders.
    static let edge        = Color(hex: Hex.edge)
    /// Emphasised borders, dividers.
    static let edgeStrong  = Color(hex: Hex.edgeStrong)

    /// Primary text. 16.44:1 on `paper`.
    static let ink         = Color(hex: Hex.ink)
    /// Secondary text, labels. 5.70:1 on `paper` — still clears the 4.5 body bar.
    static let inkDim      = Color(hex: Hex.inkDim)
    /// Tertiary, disabled, and the incorrect-answer strike. 3.49:1 on `paper`, which clears
    /// the 3.0 bar for large text (≥ 24pt) and UI only — **never body text**.
    static let inkFaint    = Color(hex: Hex.inkFaint)

    // MARK: - Amber — sealed
    //
    // Three tiers, each with a job. Do not interchange them. `docs/07` §2: a single warm amber
    // cannot be both a satisfying fill and an accessible label, so the one colour is split by
    // what it is being asked to do.

    /// **`amber` fills.** Fill only, with `ink` text on top (6.74:1). Never text, never a lone
    /// graphical mark: it is 2.68:1 on `surface`, below every threshold, deliberately. That is
    /// why it only ever sits *behind* something. `amber` alone on white carries no meaning.
    static let amber       = Color(hex: Hex.amber)
    /// **`amberDeep` draws.** Marks, borders, icons, the seal stamp. 4.00:1 on `surface`,
    /// clearing the 3.0 bar for non-text graphics.
    static let amberDeep   = Color(hex: Hex.amberDeep)
    /// **`amberText` writes.** Text and labels on `paper` or `surface`. 5.54:1 on `paper`,
    /// clearing the 4.5 body bar. Reach for this whenever the amber is a word.
    static let amberText   = Color(hex: Hex.amberText)
    /// Tinted surface behind sealed content. A wash, not a fill — nothing is read off it.
    static let amberWash   = Color(hex: Hex.amberWash)

    // MARK: - Ultramarine — revealed
    //
    // One token does text, fill, and graphics; it is dark enough for all three.

    /// Text (6.60:1 on `paper`), fill (7.26:1 under a `white` label), and graphics.
    static let ultramarine     = Color(hex: Hex.ultramarine)
    /// Pressed state.
    static let ultramarineDeep = Color(hex: Hex.ultramarineDeep)
    /// Tinted surface.
    static let ultramarineWash = Color(hex: Hex.ultramarineWash)

    // MARK: - Alert

    /// **Errors ONLY. Never a game state.** `docs/07` §2: correct/incorrect is ultramarine
    /// against neutral, not green against red — the incorrect-answer mark is an `inkFaint`
    /// strike, never red. Red is reserved so that when it appears it means something is
    /// broken. A wrong guess is not broken.
    static let alert       = Color(hex: Hex.alert)
}

extension Color {
    /// Builds a colour from a 24-bit `0xRRGGBB` literal in **explicit sRGB**.
    ///
    /// The colour space is named on purpose. An asset-catalog colour can carry an Any/Dark
    /// pair, which is exactly the shape `CLAUDE.md` §2.4 forbids, and `UIColor(red:green:blue:)`
    /// is device RGB, which would shift the computed contrast ratios in the third decimal and
    /// make `PaletteContrastTests` argue with `docs/07` §2 over rounding rather than over hexes.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:     Double((hex >> 16) & 0xFF) / 255.0,
            green:   Double((hex >>  8) & 0xFF) / 255.0,
            blue:    Double( hex        & 0xFF) / 255.0,
            opacity: 1
        )
    }
}
