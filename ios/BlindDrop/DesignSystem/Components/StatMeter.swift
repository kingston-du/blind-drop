import SwiftUI

/// The readability spectrum (`docs/07` §5).
///
/// A horizontal `paperSunk` track with a **single `ultramarine` marker** at the position.
///
/// > **No fill from the left** — filling implies more is better, and readability has no better.
///
/// That is the whole design of this component and the reason it is not a progress bar. Five
/// band labels sit below in `caption` `inkFaint`, the active one in `ink`. No arrow, no rank,
/// no delta, no comparison to yesterday. `docs/02` §4.5 makes the same point in the data model:
/// the readability list is sorted but **unranked**, and rendering a rank position here is a
/// spec violation.
///
/// The marker is `ultramarine` rather than a phase accent: the meter only ever appears on the
/// results screen, which is ultramarine, so an accent parameter would be a knob whose only
/// legal setting is the default.
struct StatMeter: View {
    /// 0…1. Clamped, because a rate arriving out of range is a bug that should not become a
    /// marker drawn off the end of its track.
    let value: Double
    let band: ReadabilityBand

    private var position: Double { min(1, max(0, value)) }

    private let trackHeight: CGFloat = 4
    private let markerWidth: CGFloat = 3
    private let markerHeight: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            track
            bandLabels
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Copy.A11y.readability(percent: Int((position * 100).rounded()), band: band)
        )
        .accessibilityAddTraits(.isStaticText)
    }

    private var track: some View {
        GeometryReader { proxy in
            let usable = max(0, proxy.size.width - markerWidth)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Palette.paperSunk)
                    .frame(height: trackHeight)
                    .frame(maxHeight: .infinity, alignment: .center)
                Capsule()
                    .fill(Palette.ultramarine)
                    .frame(width: markerWidth, height: markerHeight)
                    .offset(x: usable * position)
            }
        }
        .frame(height: markerHeight)
    }

    /// Five labels if they fit, otherwise the active one alone.
    ///
    /// **On an iPhone SE they do not fit, at any text size.** The five strings measure 320pt at
    /// `caption`'s 12pt, and 335pt is the whole content width — before spacing. `docs/07` §5
    /// asks for five and `docs/08` §7.2 draws exactly one (*"open book"*, under the marker), so
    /// this renders whichever the width allows: five on a device wide enough, the active band
    /// alone otherwise. See the open question in `tasks/E08-ios-foundation.md`.
    ///
    /// `ViewThatFits` rather than a Dynamic Type threshold (`docs/12` §1 asks for exactly that,
    /// and for it not to be a width check): whether five labels fit depends on how wide the
    /// meter is, which the meter does not know and should not have to.
    ///
    /// Each label is `fixedSize`, so the row either fits at its natural width or does not fit at
    /// all. Without it the labels get equal-width columns narrower than the word "Unreadable"
    /// and break *mid-word*, which is a layout that technically fits and is unreadable.
    private var bandLabels: some View {
        ViewThatFits(in: .horizontal) {
            // No `Spacer`s between the labels. A `Spacer`'s ideal width is unbounded, so a row
            // containing one never reports a size that fits and `ViewThatFits` would drop
            // straight through to the fallback at every Dynamic Type size — including the ones
            // where all five fit comfortably. Fixed spacing costs a little distribution and is
            // the difference between the spectrum being drawn and not.
            HStack(spacing: Space.sm) {
                ForEach(ReadabilityBand.ordered, id: \.self) { candidate in
                    label(candidate).fixedSize()
                }
            }
            label(band)
        }
    }

    private func label(_ candidate: ReadabilityBand) -> some View {
        Text(verbatim: Copy.band(candidate))
            .typeStyle(.caption)
            .foregroundStyle(candidate == band ? Palette.ink : Palette.inkFaint)
    }
}

extension ReadabilityBand {
    /// Low to high, which is the order the track runs in. `CaseIterable`'s order is the
    /// declaration order and runs the other way; relying on it would put *Open book* at the
    /// left end of a meter whose marker moves right as readability rises.
    static let ordered: [ReadabilityBand] = [
        .unreadable, .hardToPlace, .mixedSignals, .legible, .openBook,
    ]

    /// The band a rate falls in.
    ///
    /// **These thresholds mirror `server/supabase/migrations/0005_scoring.sql`.** The server
    /// sends a band with the standings but not with a member's own results (`docs/04` §4), so
    /// the client has to be able to derive one, and two copies of a rule is two chances to
    /// disagree. `ComponentTests` pins every boundary — including 0.80 and 0.60 exactly, where
    /// a `>` written for a `>=` moves somebody a band down and nothing else looks wrong.
    init(readability: Double) {
        self = switch readability {
        case 0.80...: .openBook
        case 0.60..<0.80: .legible
        case 0.40..<0.60: .mixedSignals
        case 0.20..<0.40: .hardToPlace
        default: .unreadable
        }
    }
}
