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
/// points wide and every geometric number the spec writes down — *"180pt filmstrip artwork"*,
/// *"72pt margins"*, *"240pt of bottom safe space"* — is divided once, here, by `canvas(_:)`.
/// Doing it anywhere else would mean a card designed at 1080 points and rendered at 3 240
/// pixels: a 12MB PNG where `docs/10` §1 asks for about 800KB.
///
/// Everything that is *type* rather than geometry comes from `TypeStyle` at a pinned `.large`,
/// because the card is an image and an image has no Dynamic Type. `E30-01` left one literal-size
/// exception here (the old standalone Best Ear rate); `E36-01` retired it along with the footer
/// it lived on — the podium that replaced it sets its rate from the same `TypeStyle` as its rank
/// and its name, so there is no literal size left on this card at all.
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
        /// 1080 × 1350, and the one the share sheet draws — iMessage is where this actually gets
        /// pasted.
        case squareTall
        /// 1080 × 1920, for Stories. Rendered on demand; not offered by the UI.
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
    }

    /// *"Bigger, bolder album-art treatment is fine"* (`E30-01`, `docs/17` §4). Roughly twice
    /// the pre-redesign 96px thumbnail — the largest that still lets four of them sit in one
    /// row inside the **story** variant's narrower content width, which is the binding
    /// constraint (`docs/10` §3's margins are more generous there, but the canvas itself is the
    /// same 1080px wide as square-tall). Drawn only on the no-personal-night fallback card
    /// (`E36-01`) — a fixed-height canvas has no room for full artwork *and* the personal bands
    /// at once (`ShareCardFitTests`), so a member with a night of their own gets the room tally
    /// and the podium instead, and a member with nothing personal to show gets this back.
    static let artwork = canvas(180)

    /// *"up to 4 flight rows"* (`docs/10` §2), taken **by `card_no`** and never re-sorted. The
    /// redesign keeps the count and drops everything each row used to say — the filmstrip is
    /// four pictures, not four sentences.
    static let maximumRows = 4

    /// The room tally's own overflow rule (`E36-01`, `docs/10` §2): at most this many distinct
    /// names before the line folds the rest into "+N more", the same shape `maximumRows`/
    /// `share.overflow` already gives the filmstrip. A circle can hold up to seven other
    /// guessers, and a one-line tally of seven names is exactly the kind of run that pushes the
    /// wordmark off a fixed-height card if nothing caps it.
    static let maximumRoomTallyNames = 4

    /// The share card's own display cap on tonight's Ear top 3 (`E36-01`, `docs/10` §2) —
    /// **not** the same thing as the server's own "never split a tie" rule. `TonightEarDTO`'s
    /// own contract already keeps a boundary tie together (`ResultsDTO.tonightTopEar`'s doc
    /// comment); this cap is what a *fixed-height artifact* does with a list that ties can make
    /// longer than the card can hold — the same trade the filmstrip already makes (first four
    /// by `card_no`, `share.overflow` naming the rest) rather than growing the card. A wide tie
    /// past this cap loses rows to the overflow caption, not to a rule violation.
    static let maximumPodiumRows = 3

    /// The gap between the card's blocks, and between two frames inside the filmstrip. Both are
    /// the app's own rhythm scaled into the card's space, so the artifact looks like the app.
    static let blockGap = canvas(48)
    static let rowGap = canvas(36)

    /// The gap between vertically stacked bands **below** the hero headline (`E36-01`) — one
    /// step tighter than `rowGap`, which stays in use for `rowGap`'s other, horizontal jobs
    /// (the header's two ends, the gap between filmstrip tiles). The podium sits on every card
    /// now, where only the group fallback used to carry a footer this small; `blockGap`'s
    /// original generosity and `rowGap`'s own value both measured out too tall once there were
    /// five and six bands to fit rather than four (`ShareCardFitTests` is where this was found).
    static let stackGap = canvas(24)
}
