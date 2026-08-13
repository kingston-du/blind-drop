import SwiftUI

/// One number, on its own panel, with the word for what it counts above it and the count it was
/// derived from underneath.
///
/// The three lines are deliberate. A percentage alone is a claim; a percentage over *"1 of 7
/// pinned you"* is a fact somebody can check. `docs/04` §4's rule that **`nil` is not zero**
/// lives in `ScoringFormat`, so a tile handed nothing prints a dash and the sentence underneath
/// changes to say why — it never quietly renders 0%.
struct StatTile: View {
    /// The word above the number.
    let title: LocalizedStringKey
    /// The rate, or `nil` when it does not apply to this person tonight.
    let rate: Double?
    /// The sentence under the number.
    let detail: DetailText
    /// Ultramarine on the number when it is the one being celebrated, `ink` otherwise. Only one
    /// tile in a pair ever takes the accent — two accented numbers side by side is a scoreboard.
    var isAccented = false

    /// Either a sentence built from counts, or the one that replaces it when there are none.
    enum DetailText: Equatable {
        case counts(String)
        case absent(LocalizedStringKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionLabel(title)
            Text(verbatim: ScoringFormat.percent(rate))
                .typeStyle(.displayXL)
                .foregroundStyle(isAccented ? Palette.ultramarine : Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            detailText
        }
        .cardSurface(radius: Radius.panel, inset: Layout.rowInset + Space.xs)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var detailText: some View {
        switch detail {
        case let .counts(sentence):
            Text(verbatim: sentence)
                .typeStyle(.bodyS)
                .foregroundStyle(Palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)
        case let .absent(key):
            Text(key)
                .typeStyle(.bodyS)
                .foregroundStyle(Palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
