import SwiftUI

/// A number worth looking at, drawn the way this app already draws numbers it wants read
/// (`E28-08`).
///
/// Group, Profile and Insights shipped as a settings list wearing the app's colours rather than
/// as the flight sheet the round and results screens already are — every rule that makes those
/// screens interesting (`CLAUDE.md` §2.5's two accents, §2.7's ban on badges and streaks,
/// `docs/07` §2's ban on shadows) is still binding here, so the fix isn't a new visual language,
/// it's spending the one this app already has: an oversized tabular numeral, a mono micro-label,
/// and a hairline proportion bar instead of a sentence. One `StatFigure` replaces what used to be
/// a `SectionLabel` plus a plain `Text` plus a second `Text` underneath explaining the count.
struct StatFigure: View {
    let label: LocalizedStringKey
    /// The number to print, already formatted — `ScoringFormat.percent(_:)`, a plain count, or
    /// `ScoringFormat.unavailable`. A `String` rather than a `Double?` because not every figure
    /// this draws is a rate; a drop count is a `StatFigure` too, with `progress` at `1`.
    let value: String
    /// One line under the number — a sample count, a rounds count, or `nil` for a figure that
    /// carries no further detail (a drop count needs no unit spelled out under it).
    var detail: String?
    /// The proportion bar's fill, `0...1`, or `nil` to omit the bar entirely — an unavailable
    /// figure (`—`) has nothing to show a fraction of.
    var progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionLabel(label)
            Text(verbatim: value)
                .typeStyle(.numberL)
                .foregroundStyle(Palette.ink)
            if let progress {
                // Neutral, on purpose: a coloured bar on a screen with no accent to spend would
                // read as a third accent nobody named (`CLAUDE.md` §2.5).
                ProportionTrack(progress: progress)
            }
            if let detail {
                Text(verbatim: detail)
                    .typeStyle(.bodyS).foregroundStyle(Palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The bare bar `StatFigure` draws under a number — `ProportionBar` without its own trailing
/// tally, since the number is already printed above it here rather than beside the bar.
private struct ProportionTrack: View {
    let progress: Double
    private let height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track)
                Capsule()
                    .fill(Palette.inkDim)
                    .frame(width: proxy.size.width * min(1, max(0, progress)))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// The one mono line under a screen's title — `12 MEMBERS · 144 ROUNDS` — over a rule (`E28-08`).
/// It replaces a deleted subtitle sentence with a fact instead, in the same apparatus voice
/// `SectionLabel` already speaks.
struct SheetMeta: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(verbatim: text)
                .typeStyle(.label)
                .foregroundStyle(Palette.inkDim)
            Rule()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text))
        .accessibilityAddTraits(.isStaticText)
    }
}
