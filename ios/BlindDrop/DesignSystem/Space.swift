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
    /// The big subject card: a confirm screen's song, a results answer.
    static let card:    CGFloat = 20
    /// A panel of supporting information — a stat tile, a spectrum, a standings table.
    static let panel:   CGFloat = 16
    /// One row of a list, drawn as its own surface.
    static let row:     CGFloat = 14
    /// A button, a field, a small container.
    static let control: CGFloat = 14
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
    /// The bar that marks a selected row down its leading edge (`E42-01`).
    ///
    /// Wider than `mark` because it is read at a glance from the far end of a list rather than
    /// looked at, and because it is the only thing distinguishing the row you are in — the
    /// previous answer, a `paperSunk` fill, was four percent of value and said "disabled".
    static let rail: CGFloat = 3
}

/// The layout law of `docs/07` §4, named so that a screen states it rather than re-deriving it:
/// **single column, one primary action per screen, generous vertical rhythm.**
enum Layout {
    /// Horizontal inset on every screen.
    static let screenInset = Space.xxl
    /// Top breathing room for screen chrome inside the safe area.
    static let chromeTop = Space.sm
    /// Vertical gap between distinct blocks.
    static let blockGap = Space.x3
    /// Vertical gap within a block.
    static let itemGap = Space.md
    /// The padding inside a card or a panel.
    static let cardInset = Space.xl
    /// The padding inside one row of a list.
    static let rowInset = Space.md

    /// The minimum hit region for anything interactive (`docs/12` §5).
    ///
    /// Several controls are deliberately smaller than this visually — the preview control is
    /// 28pt, a name chip is 36pt tall — and every one of them carries a `contentShape` this
    /// size. `ComponentTests` asserts it for each, because a 32pt tap target is invisible in a
    /// screenshot and obvious in the hand.
    static let minimumTouchTarget: CGFloat = 44

    /// `PrimaryButton`'s height (`docs/07` §5).
    static let buttonHeight: CGFloat = 56
    /// A field's height. One point shy of the button so a stacked pair reads as a field and then
    /// an action rather than as two halves of the same control.
    static let fieldHeight: CGFloat = 54
    /// The preview control's drawn size; its hit region is `minimumTouchTarget`.
    static let previewControl: CGFloat = 28
    /// A name chip's drawn height; its hit region is `minimumTouchTarget`.
    static let chipHeight: CGFloat = 38

    /// One row of the circle switcher (`E42-01`).
    ///
    /// Not `minimumTouchTarget`, which is what it was and which is a *floor* rather than a
    /// rhythm — 44pt around a 24pt name leaves ten points top and bottom, and a list of those
    /// reads as a menu somebody compressed. Not `buttonHeight` either: a row is not a control,
    /// and borrowing that token would make the two move together the next time one of them
    /// wants to change. 64 is the number, written down once.
    static let switcherRowHeight: CGFloat = 64

    /// The phase mark on a switcher row (`E42-01`).
    ///
    /// `Space.sm` rather than a new number, and it scales with the label beside it at the call
    /// site. Filled it is a dot; hollow it is a ring at `Stroke.mark`, which leaves a 4pt hole —
    /// the smallest ring that still reads as *not filled* rather than as a slightly soft dot.
    static let switcherPip: CGFloat = Space.sm

    /// A name chip's drawn height in the quick pass (`E41-01`).
    ///
    /// 38 is right for the call sheet, where the pool is apparatus pinned under a flight somebody
    /// is reading, and wrong for the quick pass, where the pool **is** the screen's one action.
    /// 52 is `fieldHeight`'s neighbour rather than a new number: a row of these reads as a set of
    /// things to press, which is exactly what 38 refuses to read as when it is the only thing on
    /// the lower half of the screen.
    static let chipHeightLarge: CGFloat = 52

    /// The floor on a quick-pass pool column (`E41-01`).
    ///
    /// Three columns on a 393pt phone, two on an SE, and one once the type is large enough that
    /// two would overlap — the count falls out of the scaled floor at the call site rather than
    /// out of a device check, the same way `nameChipMinimumWidth` already works.
    static let quickPassPoolColumn: CGFloat = 104

    /// Everything on the quick pass that is neither the artwork nor the name pool (`E41-01`).
    ///
    /// The close row, the numeral, the track row, Skip, and the gaps between all of them, added
    /// up at `.large`: 44 + 20 + 62 + 20 + 62 + 32 + 56 + 32. Subtracting this and a computed pool
    /// height from the viewport is what leaves the artwork its share.
    ///
    /// A written-down sum rather than a measured one, and that is a real trade taken with its
    /// eyes open. Measuring is tidier to read and wrong in practice: a preference arrives after
    /// the first layout, so the artwork drew at its maximum and jumped down on the frame after —
    /// on every card of every run. A number that can drift beats a jump that always happens. It
    /// scales with nothing on purpose: at accessibility sizes the real chrome outgrows this, the
    /// artwork lands on `Artwork.quickPassRange`'s floor, and the page scrolls, which is the
    /// right answer there anyway.
    static let quickPassFixedChrome: CGFloat = 328

    /// How far a finger travels before a swipe means *the card behind this one* (`E41-03`).
    ///
    /// Generous, because the gesture shares a screen with a vertical scroll at accessibility
    /// sizes and losing a scroll to a mis-read swipe is worse than losing a swipe to a
    /// deliberate second try. The chevron is the mechanism; this is the shortcut.
    static let quickPassBackSwipe: CGFloat = 44

    /// A name chip's minimum drawn width (`E26-02`).
    ///
    /// Not strict equality, which is the obvious answer and the wrong one: twelve pills all sized
    /// to the longest name in the circle waste the row, and at accessibility sizes a fixed width
    /// either truncates a name or overflows. A floor instead. Every name up to about six
    /// characters — which is most first names, and all eleven of the fixture's — comes out the
    /// same width, so the row reads as one set of targets; anything genuinely longer grows past
    /// it rather than being cut. 72 also keeps four whole pills plus the edge of a fifth on an
    /// SE's 327 points of content width, which is what stops the row from looking finished when
    /// it is not. It scales with Dynamic Type at the call site (`NameChip`).
    static let nameChipMinimumWidth: CGFloat = Space.x6
    /// The grab bar on a pinned panel. A mark that the panel is its own surface, not a control.
    static let grabber = (width: CGFloat(38), height: CGFloat(4))
    /// A status badge's drawn height. It is a label, never a control, so it has no hit region.
    static let badgeHeight: CGFloat = 28

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

    /// The card, drawn small, on the share sheet (`docs/10` §4).
    ///
    /// This was `shareThumbnailWidth`, and it was 112 points because *two* of them plus the screen
    /// inset and the gap between had to fit inside an SE's 375 — the picker's job was letting
    /// somebody compare two shapes at a glance. There is no picker any more (`ShareSheet`), so that
    /// reason is gone and the constraint with it: one preview only has to fit once, and the point
    /// of it is no longer comparison but recognition — *this is the thing you are about to send*.
    /// 184 is a little over half the SE's content width, which is large enough to recognise the
    /// taller card and still leaves the sheet shorter than its detent.
    static let sharePreviewWidth: CGFloat = Space.x6 * 2 + Space.x4

    /// The share sheet's own detent (`docs/10` §4).
    ///
    /// A fixed height rather than `.medium`, because `.medium` is half of whatever screen it is
    /// shown on and this sheet is the same size on every screen: a 307-point preview, one caption
    /// line and one button, all of them fixed. Half of an SE is 333 points, which the preview no
    /// longer fits; half of a 15 Pro Max is 466, which is two hundred points of nothing under the
    /// button. The number is the content, added up: `screenInset` 24, preview 307, `Space.sm` 8,
    /// an 18-point caption line, `blockGap` 32, `buttonHeight` 56, `screenInset` 24 — 469, with the
    /// remainder as slack. `ShareCardSnapshots.theSheetFitsItsDetent` measures the real render
    /// against this, so the arithmetic cannot quietly stop being true.
    static let shareSheetHeight: CGFloat = 480

    /// The reveal call sheet's collapsed status row (`docs/08` §6).
    ///
    /// **A fallback, not the number.** `GuessSheet` measures its own peek header and publishes the
    /// real height as a `CallSheetMetrics`; this is what a snapshot with no enclosing
    /// screen gets, and what the flight reserves for one layout pass before the measurement
    /// arrives. The constant used to be the whole answer and it was wrong by about a chip: 108
    /// points is roughly two dozen more than the header actually occupies, so the collapsed sheet
    /// showed the top quarter of the name row — and a pool visible while collapsed is exactly what
    /// `E17-06` set out to remove, because it gives nobody a reason to raise the sheet.
    static let callSheetPeekHeight: CGFloat = Space.x6 + Space.xxl + Space.md

    /// How far a finger travels before it counts as *scrolling past* rather than as a tap
    /// (`docs/09` §4: *"any scroll gesture completes the entire sequence immediately"*).
    ///
    /// Small on purpose — the rule is about intent, not about distance — but not zero, because
    /// a zero-distance drag fires on every tap and would end the results animation on a touch
    /// that never moved.
    static let scrollSkipDistance: CGFloat = Space.xs

    /// Artwork at the four sizes `docs/06` §2.1 names.
    enum Artwork {
        static let searchRow: CGFloat = 52
        /// The archive's thumbnail. Smaller than a search row's, because the archive is a list
        /// somebody scrolls and the search is a list somebody chooses from.
        static let recordRow: CGFloat = 44
        static let flightCard: CGFloat = 48
        /// The answer card's thumbnail, which sits beside a 44pt number rather than a 26pt one.
        static let resultCard: CGFloat = 76
        /// `docs/08` §3.2 draws the confirm screen's artwork at **280pt**, and `docs/06` §2.1
        /// fetches that spot at 600×600 — which 280 at 2× very nearly is and 240 was not. The
        /// sealed card fetches at this size too and draws at its container's width, so the number
        /// is the fetch for both and the drawn size for one.
        static let confirm: CGFloat = 280

        /// The quick pass's artwork — **the largest in the app**, and the only one whose drawn
        /// size is decided at layout time rather than written down.
        ///
        /// This number is the *fetch*, taken once at the maximum so the URL never changes as the
        /// clamp below moves. `quickPassRange` is what it is actually drawn at: whatever vertical
        /// room the numeral, the track row, the pool and Skip have not already claimed, clamped
        /// into that range. Five names leave enough for the top of it; eleven names leave the
        /// bottom. Neither layout breaks, and neither has to be predicted from a device model.
        static let quickPass: CGFloat = 360
        static let quickPassRange: ClosedRange<CGFloat> = 140...360
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
