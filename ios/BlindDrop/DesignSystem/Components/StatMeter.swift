import SwiftUI

/// The readability spectrum (`docs/07` §5).
///
/// A horizontal `paperSunk` track with a **single `ultramarine` marker** at the position.
///
/// > **No fill from the left** — filling implies more is better, and readability has no better.
///
/// That is the whole design of this component and the reason it is not a progress bar. The
/// active band label sits below in `caption` `ink`. No arrow, no rank, no delta, no comparison
/// to yesterday. `docs/02` §4.5 makes the same point in the data model:
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
    /// Whether the meter prints its own band label beneath the track.
    ///
    /// `false` is the standings row (`docs/08` §7.3: *"each row a compact `StatMeter` and a band
    /// label"*), where the label sits beside the track instead of under it and the row owns both
    /// the layout and the announcement. The band is never *dropped* — a marker with no word next
    /// to it would be a position on a scale nobody named, which is the rank this component
    /// exists to not be.
    var showsBand = true

    private var position: Double { min(1, max(0, value)) }

    private let trackHeight: CGFloat = 4
    private let markerWidth: CGFloat = 3
    private let markerHeight: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            track
            if showsBand { bandLabels }
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

    /// The owner-approved rule is one active, one-word label only. It keeps the meter readable
    /// on small phones at every Dynamic Type size and matches the results-screen specification.
    private var bandLabels: some View {
        Text(verbatim: Copy.band(band))
            .typeStyle(.caption)
            .foregroundStyle(Palette.ink)
    }
}

extension ReadabilityBand {
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
