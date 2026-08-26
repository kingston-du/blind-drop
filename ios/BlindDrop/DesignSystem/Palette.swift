import SwiftUI

/// The colour tokens of `docs/07` §2, transcribed exactly.
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
        static let paper: UInt32       = 0xEFF1F5
        static let paperSunk: UInt32   = 0xE7EAEF
        static let surface: UInt32     = 0xFFFFFF
        static let edge: UInt32        = 0xDCE0E7
        static let edgeStrong: UInt32  = 0xD3D8E0
        /// The rule *inside* a card, a step lighter than the rule around it.
        static let hairline: UInt32    = 0xEAEDF1
        /// The unfilled part of a meter, a bar, a spectrum.
        static let track: UInt32       = 0xEEF0F4

        static let ink: UInt32         = 0x14161A
        static let inkDim: UInt32      = 0x454B55
        static let inkSubtle: UInt32   = 0x6E7480
        static let inkFaint: UInt32    = 0x767C88
        static let inkQuiet: UInt32    = 0xB9BEC7

        // Amber — four tiers, each with a job. Do not interchange them.
        static let amber: UInt32       = 0xB26A06
        static let amberDeep: UInt32   = 0x96590A
        static let amberText: UInt32   = 0x8A5205
        static let amberWash: UInt32   = 0xF6EAD6
        static let amberEdge: UInt32   = 0xE6CFA6

        // Ultramarine — one token does text, fill, and graphics.
        static let ultramarine: UInt32     = 0x2233C4
        static let ultramarineDeep: UInt32 = 0x1B29A0
        static let ultramarineWash: UInt32 = 0xE3E6FA
        static let ultramarineWashLight: UInt32 = 0xF4F6FD
        static let ultramarineEdge: UInt32 = 0xC3C9F2

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
    /// The rule between two rows of the same card. Lighter than `edge`, which draws the card.
    static let hairline    = Color(hex: Hex.hairline)
    /// The empty part of a meter, a blame bar, a spectrum.
    static let track       = Color(hex: Hex.track)

    /// Primary text. 16.02:1 on `paper`.
    static let ink         = Color(hex: Hex.ink)
    /// Secondary text, labels. 7.77:1 on `paper` — comfortably over the 4.5 body bar.
    static let inkDim      = Color(hex: Hex.inkDim)
    /// A de-emphasised **data figure** — a low number on an insights or standings screen that is
    /// still the data, not decoration. `#6E7480` on white (4.9:1), darker than `inkFaint` so a
    /// muted figure does not read as absent.
    static let inkSubtle   = Color(hex: Hex.inkSubtle)
    /// The quietest tier that still carries a word. 3.71:1 on `paper`, which clears the 3.0 bar
    /// for large text (≥ 24pt) and UI — **never body text, and never a micro-label**. A label is
    /// small text however quiet it is meant to look, so labels take `inkDim`.
    static let inkFaint    = Color(hex: Hex.inkFaint)
    /// Disabled labels, a spent chip, the incorrect-answer strike. 1.65:1, which is why it is
    /// only ever a *mark* on something else and never carries meaning alone.
    static let inkQuiet    = Color(hex: Hex.inkQuiet)

    // MARK: - Amber — sealed
    //
    // Four tiers, each with a job. Do not interchange them. `docs/07` §2: a single warm amber
    // cannot be both a satisfying fill and an accessible label, so the one colour is split by
    // what it is being asked to do — and the wash needs an edge of its own, which is the fourth.

    /// **`amber` fills and draws.** The button fill under a white label (4.24:1, which clears
    /// the 3.0 bar for the 17pt semibold label it carries and nothing smaller), and the mark
    /// tier: borders, the seal stamp, a card number. 4.24:1 on `surface`, over the 3.0 bar for
    /// non-text graphics. It is never set as body copy — that is what `amberText` is for.
    static let amber       = Color(hex: Hex.amber)
    /// The pressed fill (`docs/07` §5).
    static let amberDeep   = Color(hex: Hex.amberDeep)
    /// **`amberText` writes.** Text and labels on `paper`, `surface`, or `amberWash`. 5.65:1 on
    /// `paper`, clearing the 4.5 body bar. Reach for this whenever the amber is a word.
    static let amberText   = Color(hex: Hex.amberText)
    /// Tinted surface behind sealed content. A wash, not a fill — nothing is read off it.
    static let amberWash   = Color(hex: Hex.amberWash)
    /// The border that closes the wash. A wash with no edge floats; a wash edged in `amber`
    /// shouts. This is the step between.
    static let amberEdge   = Color(hex: Hex.amberEdge)

    // MARK: - Ultramarine — revealed
    //
    // One token does text, fill, and graphics; it is dark enough for all three.

    /// Text (7.94:1 on `paper`), fill (8.98:1 under a `white` label), and graphics.
    static let ultramarine     = Color(hex: Hex.ultramarine)
    /// Pressed state, and the deeper cut for words set on `ultramarineWash`.
    static let ultramarineDeep = Color(hex: Hex.ultramarineDeep)
    /// Tinted surface.
    static let ultramarineWash = Color(hex: Hex.ultramarineWash)
    /// A lighter tinted surface — the "you" row's highlight on the group screen. A softer step
    /// than `ultramarineWash`, so a highlighted card reads as *selected* rather than *coloured*.
    static let ultramarineWashLight = Color(hex: Hex.ultramarineWashLight)
    /// The border that closes the wash.
    static let ultramarineEdge = Color(hex: Hex.ultramarineEdge)

    // MARK: - Alert

    /// **Errors ONLY. Never a game state.** `docs/07` §2: correct/incorrect is ultramarine
    /// against neutral, not green against red — the incorrect-answer mark is an `inkQuiet`
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
