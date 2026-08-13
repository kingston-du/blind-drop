import SwiftUI

/// The spacing ramp of `docs/07` §4, and the only place a gap is written down.
///
/// Every number in `Features/` comes from here. `ios/scripts/lint.sh` rule 2 fails the build on
/// a bare numeric `padding`/`spacing`/`cornerRadius` in a feature file, because a screen built
/// from arbitrary numbers is a screen whose rhythm nobody can hold in their head — and the
/// rhythm is most of what makes the app look like one thing rather than eleven.
enum Space {
    /// No gap, named so it can be written down.
    ///
    /// Not a placeholder for "I did not think about it" — the opposite. Two blocks that must
    /// *meet*, like the reveal's flight and the guess sheet pinned under it, are a deliberate
    /// zero: the sheet draws its own hairline at the join (`docs/07` §2, Elevation), and any gap
    /// there would show `paper` through a seam that is supposed to be an edge.
    static let none: CGFloat = 0
    static let xxs: CGFloat = 2
    static let xs:  CGFloat = 4
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 12
    static let lg:  CGFloat = 16
    static let xl:  CGFloat = 20
    static let xxl: CGFloat = 24
    static let x3:  CGFloat = 32
    static let x4:  CGFloat = 40
    static let x5:  CGFloat = 56
    static let x6:  CGFloat = 72
}

/// Corner radii (`docs/07` §4). Artwork is *softened*, never a circle and never square.
enum Radius {
    /// Album art. The one radius that is about a photograph rather than about a control.
    static let artwork: CGFloat = 8
    static let card:    CGFloat = 16
    static let control: CGFloat = 12
    static let sheet:   CGFloat = 24
    /// A capsule, expressed as a number so `RoundedRectangle` can take it.
    static let pill:    CGFloat = 999
}

/// Line widths (`docs/07` §4).
enum Stroke {
    /// List separators — one device pixel, whatever the device's scale is.
    ///
    /// A function of the scale rather than a constant, because `UIScreen.main` is not a thing a
    /// view should reach for and because a snapshot rendered at 3× has to draw the same hairline
    /// a 3× device draws. Views pass `@Environment(\.displayScale)`.
    static func hairline(atScale scale: CGFloat) -> CGFloat { 1.0 / max(1, scale) }
    /// Card and control borders. The app's only elevation, together with the value step from
    /// `paper` to `surface` — there is no shadow anywhere (`docs/07` §2).
    static let border: CGFloat = 1
    /// The seal stamp outline (`docs/09` §2, phase D).
    static let mark: CGFloat = 2
}

/// The layout law of `docs/07` §4, named so that a screen states it rather than re-deriving it:
/// **single column, one primary action per screen, generous vertical rhythm.**
enum Layout {
    /// Horizontal inset on every screen.
    static let screenInset = Space.xl
    /// Vertical gap between distinct blocks.
    static let blockGap = Space.x3
    /// Vertical gap within a block.
    static let itemGap = Space.md

    /// The minimum hit region for anything interactive (`docs/12` §5).
    ///
    /// Several controls are deliberately smaller than this visually — the preview control is
    /// 28pt, a name chip is 36pt tall — and every one of them carries a `contentShape` this
    /// size. `ComponentTests` asserts it for each, because a 32pt tap target is invisible in a
    /// screenshot and obvious in the hand.
    static let minimumTouchTarget: CGFloat = 44

    /// `PrimaryButton`'s height (`docs/07` §5).
    static let buttonHeight: CGFloat = 52
    /// The preview control's drawn size; its hit region is `minimumTouchTarget`.
    static let previewControl: CGFloat = 28
    /// A name chip's drawn height; its hit region is `minimumTouchTarget`.
    static let chipHeight: CGFloat = 36

    /// The trailing gradient that says a normal-size name pool keeps scrolling. It is an
    /// affordance, not decoration: without it a row ending at the screen edge reads as though
    /// the five visible names are the entire pool (`docs/08` §6).
    static let namePoolOverflowFadeWidth: CGFloat = Space.x3

    /// At accessibility sizes the pool becomes its own vertical scroll region. It may use no
    /// more than 40% of the available screen height, leaving the flight independently readable
    /// above it (`docs/08` §6, `docs/12` §6).
    static let namePoolMaximumHeightFraction: CGFloat = 0.4
    /// Used only by standalone snapshots, which deliberately have no enclosing screen from
    /// which to measure the fraction. Production always receives the measured screen height.
    static let namePoolSnapshotMaximumHeight: CGFloat = 320

    /// The readability list's two fixed columns (`docs/08` §7.3).
    ///
    /// Fixed so that the meters line up down the list: a meter that started wherever its
    /// neighbour's name happened to end would give the column a ragged left edge and — worse —
    /// make two markers at the same position sit at different x, which is the one thing a
    /// spectrum must not do. Only below `.accessibility1`; above it the row stacks and the
    /// columns stop existing.
    static let standingsNameColumn: CGFloat = Space.x6
    static let standingsBandColumn: CGFloat = Space.x5 + Space.lg

    /// One thumbnail in the share picker (`docs/10` §4).
    ///
    /// Two of them plus the screen inset and the gap between fit inside an SE's 375 points,
    /// which is what decides the number: the picker's whole job is letting somebody compare the
    /// two shapes at a glance, and a picker that scrolls is one they compare in two glances.
    static let shareThumbnailWidth: CGFloat = Space.x6 + Space.x4

    /// How far a finger travels before it counts as *scrolling past* rather than as a tap
    /// (`docs/09` §4: *"any scroll gesture completes the entire sequence immediately"*).
    ///
    /// Small on purpose — the rule is about intent, not about distance — but not zero, because
    /// a zero-distance drag fires on every tap and would end the results animation on a touch
    /// that never moved.
    static let scrollSkipDistance: CGFloat = Space.xs

    /// Artwork at the four sizes `docs/06` §2.1 names.
    enum Artwork {
        static let searchRow: CGFloat = 56
        static let flightCard: CGFloat = 88
        /// `docs/08` §3.2 draws the confirm screen's artwork at **280pt**, and `docs/06` §2.1
        /// fetches that spot at 600×600 — which 280 at 2× very nearly is and 240 was not. The
        /// sealed card fetches at this size too and draws at its container's width, so the number
        /// is the fetch for both and the drawn size for one.
        static let confirm: CGFloat = 280
        static let shareCard: CGFloat = 300
    }
}

/// Where a `contentShape` is larger than the thing drawn inside it.
extension View {
    /// Guarantees a hit region of at least 44 × 44 around a control that is drawn smaller
    /// (`docs/12` §5). The frame is applied before the shape so the region is centred on the
    /// control rather than hanging off one corner of it.
    func minimumTouchTarget() -> some View {
        frame(minWidth: Layout.minimumTouchTarget, minHeight: Layout.minimumTouchTarget)
            .contentShape(Rectangle())
    }
}
