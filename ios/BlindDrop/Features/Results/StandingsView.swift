import SwiftUI

/// `docs/08` §7.3 — two lists that deliberately do not have the same shape.
///
/// > **Best Ear** — ranked 1..N.
/// > **Readability** — sorted but **unranked**, no numbers in front of names. Rendering a rank
/// > position here is a spec violation (`docs/02` §4.5).
///
/// That asymmetry is the product, not a layout preference. Guessing well is a scoreboard;
/// being hard to read is a trait, and *"low readability is its own kind of win"*. So the two
/// lists are two views rather than one generic list with a `showsRank` flag — a flag is a thing
/// somebody eventually passes `true` to, and `ReadabilityRow` has nowhere to put a rank even if
/// it wanted one, exactly as `ReadabilityStandingDTO` has nowhere to decode one from.
struct StandingsView: View {
    let standings: StandingsDTO

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Above `.accessibility1` every row is two lines instead of one, so the gap *between*
    /// people has to grow past the gap *inside* one. At the same spacing a stacked list reads
    /// as one long column of unrelated lines, which is the failure mode `docs/12` §1 is really
    /// asking about when it says nothing may overlap: legibility, not collision.
    private var rowSpacing: CGFloat {
        dynamicTypeSize >= .accessibility1 ? Layout.blockGap : Layout.itemGap
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.blockGap) {
            Text("results.standings.title")
                .typeStyle(.displayM)
                .foregroundStyle(Palette.ink)

            list("results.standings.ear") {
                ForEach(standings.bestEar) { EarRow(standing: $0) }
            }

            list("results.standings.readability") {
                ForEach(standings.readability) { ReadabilityRow(standing: $0) }
            }
        }
    }

    private func list(
        _ title: LocalizedStringKey,
        @ViewBuilder rows: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            Text(title)
                .typeStyle(.label)
                .foregroundStyle(Palette.inkDim)
            rows()
        }
    }
}

/// One line of **Best Ear**: the rank, the name, the percentage, and how many that was.
///
/// The rank is **printed, never computed**. `docs/04` §4 has the server share a rank on a tie
/// and skip the next one, so two people on 0.68 are both second and nobody is third — an index
/// into the array would quietly renumber them 2 and 3, which is a different claim about the
/// same night. `StandingsTests` holds a fixture with a tie in it for that reason.
private struct EarRow: View {
    let standing: EarStandingDTO

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isStacked: Bool { dynamicTypeSize >= .accessibility1 }

    var body: some View {
        row
            // One stop per person. The rank, the name and the two numbers are one fact about
            // one member, and four swipes to hear it is three too many (`docs/12` §2).
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var row: some View {
        if isStacked {
            // Two lines, not three: who, then how they did. The two numbers belong together —
            // *"79%"* on its own line above *"77 correct"* reads as two separate scores.
            VStack(alignment: .leading, spacing: Space.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                    rank
                    name
                }
                HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                    percentage
                    correct
                }
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                rank
                name
                Spacer(minLength: Space.sm)
                percentage
                correct
            }
        }
    }

    /// `monoS` and tabular, so a two-digit rank does not shift the column of names beside it.
    private var rank: some View {
        Text(verbatim: standing.rank.formatted(.number.grouping(.never)))
            .typeStyle(.monoS)
            .foregroundStyle(Palette.inkDim)
    }

    private var name: some View {
        Text(verbatim: standing.displayName)
            .typeStyle(.bodyM)
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: isStacked ? .infinity : nil, alignment: .leading)
    }

    private var percentage: some View {
        Text(verbatim: ScoringFormat.percent(standing.earAllTime))
            .typeStyle(.monoM)
            .foregroundStyle(Palette.ink)
    }

    /// *"61 correct"* — the raw count behind the rate, so a 100% off two rounds cannot pass for
    /// a 100% off fourteen.
    private var correct: some View {
        Text(verbatim: Copy.format("results.standings.ear.detail", standing.earCorrectTotal))
            .typeStyle(.monoS)
            .foregroundStyle(Palette.inkDim)
    }
}

/// One line of **Readability**: a name, a position on the spectrum, and a word for it.
///
/// **No rank, no number in front of the name, and no percentage either.** The list is sorted so
/// it is stable between refreshes and for no other reason; printing the rate would turn the
/// spectrum back into a score with the digits hidden one row apart. What a reader gets is where
/// somebody sits and what that is called, which is what `docs/02` §4.5 asks for.
private struct ReadabilityRow: View {
    let standing: ReadabilityStandingDTO

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isStacked: Bool { dynamicTypeSize >= .accessibility1 }

    var body: some View {
        row
            // The meter announces the percentage and the band already; letting VoiceOver walk
            // into it *and* read the row would say the band twice. One element, one sentence,
            // built from the same two facts (`docs/12` §2).
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(standing.displayName). \(Copy.A11y.readability(percent: percent, band: standing.band))"
            )
            .accessibilityAddTraits(.isStaticText)
    }

    private var percent: Int {
        ScoringFormat.percentValue(standing.readabilityAllTime)
    }

    @ViewBuilder private var row: some View {
        if isStacked {
            // The word stays on the name's line and the track moves under both. Stacking all
            // three would put a band label directly above the next person's name, at which
            // point the list stops saying who is who.
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                    name
                    band
                }
                meter
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                name
                meter
                band
            }
        }
    }

    private var name: some View {
        Text(verbatim: standing.displayName)
            .typeStyle(.bodyM)
            .foregroundStyle(Palette.ink)
            .frame(
                maxWidth: isStacked ? .infinity : Layout.standingsNameColumn,
                alignment: .leading
            )
    }

    private var meter: some View {
        StatMeter(
            value: standing.readabilityAllTime,
            band: standing.band,
            // The row prints the word itself, beside the track rather than under it.
            showsBand: false
        )
    }

    /// The band the **server** sent, not one derived here. `docs/04` §4 sends it with the
    /// standings, and the client deriving a second opinion from the rate is how a boundary
    /// disagreement becomes a row that says *Legible* next to a marker in the Clear range.
    private var band: some View {
        Text(verbatim: Copy.band(standing.band))
            .typeStyle(.caption)
            .foregroundStyle(Palette.ink)
            .frame(
                maxWidth: isStacked ? .infinity : Layout.standingsBandColumn,
                alignment: .leading
            )
    }
}
