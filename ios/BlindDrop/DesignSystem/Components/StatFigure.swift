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
    /// Ultramarine on the number and its bar when this is the one figure being celebrated — the
    /// profile's Ear. Only one figure in a set ever takes it, so it never reads as a scoreboard.
    var isAccented = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionLabel(label)
            Text(verbatim: value)
                .typeStyle(.numberL)
                .foregroundStyle(isAccented ? Palette.ultramarine : Palette.ink)
            if let progress {
                ProportionTrack(progress: progress, fill: isAccented ? Palette.ultramarine : Palette.inkDim)
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

/// The bare proportion bar — `ProportionBar` without its own trailing tally, since the number is
/// already printed above it rather than beside the bar. `StatFigure` draws it under a number at
/// its default height; `InsightsScreen` reuses the same bar at a smaller height for its compact
/// mutual-read rows, which is why it is not `private`.
struct ProportionTrack: View {
    let progress: Double
    var height: CGFloat = ProportionTrack.regularHeight
    /// The bar's fill. Neutral by default — a profile stat has no accent to spend — but Insights
    /// passes the revealed-data accent, or the muted figure grey for a low number.
    var fill: Color = Palette.inkDim

    /// The bar under a profile stat's `.numberL` numeral.
    static let regularHeight: CGFloat = 6
    /// The shorter bar under Insights' compact mutual-read `.numberM` numeral, so it does not
    /// crowd the pair of names above it.
    static let compactHeight: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track)
                Capsule()
                    .fill(fill)
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
///
/// A trailing control can sit on the same line, to the right of the fact — the Group screen's
/// Record chip — which is why the fact and the trailing control are separate accessibility
/// elements rather than one combined phrase: the fact is a static label, the control is a button,
/// and a button folded into a static text element could not be reached.
struct SheetMeta<Trailing: View>: View {
    let text: String
    @ViewBuilder let trailing: Trailing

    init(text: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.text = text
        self.trailing = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .center, spacing: Space.md) {
                Text(verbatim: text)
                    .typeStyle(.label)
                    .foregroundStyle(Palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.sm)
                trailing
            }
            Rule()
        }
    }
}
