import SwiftUI

/// The share card's two shapes, and the one conversion that makes `docs/10` readable as code.
///
/// > | Variant | Size | Scale |
/// > |---|---|---|
/// > | Square-tall | 1080 × 1350 (4:5) | 3× |
/// > | Story | 1080 × 1920 (9:16) | 3× |
///
/// **`docs/10`'s numbers are in the artifact's own pixel space; a SwiftUI view is laid out in
/// points.** With `ImageRenderer.scale = 3` those differ by exactly three, so the view is 360
/// points wide and every geometric number the spec writes down — *"96pt artwork"*, *"72pt
/// margins"*, *"240pt of bottom safe space"* — is divided once, here, by `canvas(_:)`. Doing it
/// anywhere else would mean a card designed at 1080 points and rendered at 3 240 pixels: a 12MB
/// PNG where `docs/10` §1 asks for about 800KB.
///
/// Everything that is *type* rather than geometry comes from `TypeStyle` at a pinned
/// `.large`, because the card is an image and an image has no Dynamic Type. The row number is
/// the single exception, and it is why `numberSize` exists: `docs/10` §3 gives it two literal
/// sizes and no token.
enum ShareCard {

    /// `ImageRenderer.scale` (`docs/10` §1, §4). The one number that ties the two spaces
    /// together, so a test can assert the output dimensions from the view's own size.
    static let scale: CGFloat = 3

    /// A length `docs/10` writes in the artifact's 1080-wide space, as view points.
    static func canvas(_ pixels: CGFloat) -> CGFloat { pixels / scale }

    /// The two artifacts (`docs/10` §1).
    enum Variant: String, CaseIterable, Identifiable, Sendable {
        /// 1080 × 1350. **The default** — iMessage is where this actually gets pasted.
        case squareTall
        /// 1080 × 1920, for Stories.
        case story

        var id: String { rawValue }

        /// The artifact's pixel size — what a golden's dimensions are asserted against.
        var pixelSize: CGSize {
            switch self {
            case .squareTall: CGSize(width: 1080, height: 1350)
            case .story: CGSize(width: 1080, height: 1920)
            }
        }

        /// The view's size in points: the artifact divided by the render scale.
        var size: CGSize {
            CGSize(width: canvas(pixelSize.width), height: canvas(pixelSize.height))
        }

        /// *"Generous margins: 72pt square-tall, 96pt story"* (`docs/10` §3).
        var margin: CGFloat {
            switch self {
            case .squareTall: canvas(72)
            case .story: canvas(96)
            }
        }

        /// *"an extra 240pt of bottom safe space so the Instagram UI does not cover the
        /// wordmark"* (`docs/10` §3). Zero on the square-tall, which nothing overlays.
        var bottomSafeSpace: CGFloat {
            switch self {
            case .squareTall: 0
            case .story: canvas(240)
            }
        }

        /// *"Numbers in Bricolage Grotesque at 96pt (square-tall) / 112pt (story)"*
        /// (`docs/10` §3).
        var numberSize: CGFloat {
            switch self {
            case .squareTall: canvas(96)
            case .story: canvas(112)
            }
        }

        /// *"The headline pair stacks instead of sitting side by side"* in the story
        /// (`docs/10` §3), which is also what `docs/12` §1 asks of the square-tall at
        /// accessibility sizes — except that a rendered image has no type size, so here it is a
        /// property of the shape and nothing else.
        var stacksHeadline: Bool { self == .story }

        /// The picker's label for this thumbnail (`docs/11` — `results.share.*`).
        var pickerLabel: LocalizedStringKey {
            switch self {
            case .squareTall: "results.share.square"
            case .story: "results.share.story"
            }
        }
    }

    /// *"Artwork at 96pt, `Radius.artwork`, unmodified"* (`docs/10` §3).
    static let artwork = canvas(96)

    /// *"up to 4 flight rows"* (`docs/10` §2), taken **by `card_no`** and never re-sorted.
    static let maximumRows = 4

    /// The most of a row an owner's name may take.
    ///
    /// `docs/10` §3 says *"owner names never truncate before the title does"*, and a cap is what
    /// keeps that from being read as *"the owner takes whatever it wants"*: an unbounded
    /// 24-character display name eats the row and leaves the title as a single ellipsis, which
    /// satisfies the sentence and defeats it. With the cap the title gives way first — the
    /// order the rule is about — and only a genuinely extreme name is trimmed at all.
    static let ownerColumn = canvas(240)

    /// The gap between the card's blocks, and between two rows inside the flight. Both are the
    /// app's own rhythm scaled into the card's space, so the artifact looks like the app.
    static let blockGap = canvas(48)
    static let rowGap = canvas(36)
    /// The vertical breathing room inside one flight row, either side of its 96pt artwork.
    ///
    /// Tight on purpose: four rows plus a headline, a stat pair and a wordmark have to fit
    /// inside 1350 pixels with the *"generous margins"* §3 asks for, and the row is the one
    /// block of the card that is repeated four times.
    static let rowPadding = canvas(18)
}
