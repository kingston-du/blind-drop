import SwiftUI

/// The share card's two shapes, and the one conversion that makes `docs/10` readable as code.
///
/// > | Variant | Size | Scale |
/// > |---|---|---|
/// > | Square-tall | 1080 × 1800 (3:5) | 3× |
/// > | Story | 1080 × 1920 (9:16) | 3× |
///
/// **`docs/10`'s numbers are in the artifact's own pixel space; a SwiftUI view is laid out in
/// points.** With `ImageRenderer.scale = 3` those differ by exactly three, so the view is 360
/// points wide and every geometric number the spec writes down — *"84px table artwork"*,
/// *"72px margins"*, *"72px of bottom safe space"* — is divided once, here, by `canvas(_:)`.
/// Doing it anywhere else would mean a card designed at 1080 points and rendered at 3 240
/// pixels: a 12MB PNG where `docs/10` §1 asks for about 800KB.
///
/// Everything that is *type* rather than geometry comes from `TypeStyle` at a pinned `.large`,
/// because the card is an image and an image has no Dynamic Type. The numbered flight is the
/// one exception: it preserves the original share table's oversized Bricolage numerals.
enum ShareCard {

    /// `ImageRenderer.scale` (`docs/10` §1, §4). The one number that ties the two spaces
    /// together, so a test can assert the output dimensions from the view's own size.
    static let scale: CGFloat = 3

    /// A length `docs/10` writes in the artifact's 1080-wide space, as view points.
    static func canvas(_ pixels: CGFloat) -> CGFloat { pixels / scale }

    /// The two artifacts (`docs/10` §1).
    ///
    /// Both shapes stay in the model; only one of them has a way out of the app. `ShareSheet`
    /// renders `.squareTall` and offers no choice, so `.story` is currently drawn by the goldens
    /// and by nothing else — kept because `docs/10` §3 specifies it, because the share card is the
    /// surface most likely to want a second shape back, and because deleting a spec'd artifact to
    /// tidy up an enum is a product decision rather than a cleanup.
    enum Variant: String, CaseIterable, Identifiable, Sendable {
        /// 1080 × 1800, and the one the share sheet draws — the extra height carries the music,
        /// the caller's own results and the room tally without compressing any of them into a
        /// sentence.
        case squareTall
        /// 1080 × 1920, for Stories. Rendered on demand; not offered by the UI.
        case story

        var id: String { rawValue }

        /// The artifact's pixel size — what a golden's dimensions are asserted against.
        var pixelSize: CGSize {
            switch self {
            case .squareTall: CGSize(width: 1080, height: 1800)
            case .story: CGSize(width: 1080, height: 1920)
            }
        }

        /// The view's size in points: the artifact divided by the render scale.
        var size: CGSize {
            CGSize(width: canvas(pixelSize.width), height: canvas(pixelSize.height))
        }

        /// Both tall artifacts use the same 72px inset so their table columns stay aligned.
        var margin: CGFloat {
            canvas(72)
        }

        /// Story keeps a 72px footer reserve for sharing chrome. Square-tall has no overlay.
        var bottomSafeSpace: CGFloat {
            switch self {
            case .squareTall: 0
            case .story: canvas(72)
            }
        }

        /// The numbered music rows' oversized numeral. Kept larger than the body title beside it,
        /// but set a step under the 96px the original table used — the flight now shares the
        /// canvas with the personal stats and the room tally, and a fixed-height card pays for
        /// every point of numeral (`theCardFits` measures the worst case).
        var numberSize: CGFloat {
            switch self {
            case .squareTall: canvas(84)
            case .story: canvas(84)
            }
        }
    }

    /// Artwork inside one music-table row. It stays unmodified and large enough to read without
    /// competing with the row number or title.
    static let artwork = canvas(84)

    /// *"up to 4 flight rows"* (`docs/10` §2), taken **by `card_no`** and never re-sorted.
    static let maximumRows = 4

    /// The room tally is a surfaced table rather than one wrapped sentence. Three full rows are
    /// more useful than four cramped ones; additional distinct guesses keep the explicit
    /// `+ N more` overflow treatment.
    static let maximumRoomTallyNames = 3

    /// The most width an owner name may take before the song title starts yielding.
    static let ownerColumn = canvas(240)

    /// The gap between the card's blocks and between columns inside a row. Both are the app's
    /// own rhythm scaled into the card's space, so the artifact looks like the app.
    static let blockGap = canvas(18)
    static let rowGap = canvas(36)

    /// Tight vertical padding inside repeated table rows. The surfaced container provides the
    /// larger block boundary; rows only need enough air to remain individually scannable.
    static let rowPadding = canvas(3)
    static let tallyRowPadding = canvas(9)

    /// The gap between the compact personal bands below the headline.
    static let stackGap = canvas(12)

    /// The room tally's count numeral — one step under `TypeStyle.numberM`'s 26pt. The name
    /// beside it is the row's important part; the count only needs to read clearly, not to
    /// compete with it or with the personal stats' own numberM figures above.
    static let tallyCountSize = canvas(72)
}
