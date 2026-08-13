import SwiftUI

/// The group's all-time lists (`docs/08` §7.3), drawn as one table rather than two.
///
/// **The table is sorted on ear only.** Readability rides along in the same row as a trait, not
/// as a second ranking — there is no better end of the readability scale, so a list ordered by
/// it would be a leaderboard for something that is not a competition (`docs/16`). Putting both
/// numbers on one row is what makes that legible: one column is a rank, the other is a fact
/// about a person, and they are read together the way you would read them out loud.
struct StandingsView: View {
    let standings: StandingsDTO

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale

    /// The caller's own row, matched by name against the readability list, which is the only
    /// place both numbers meet.
    private var readabilityByUser: [String: ReadabilityStandingDTO] {
        Dictionary(uniqueKeysWithValues: standings.readability.map { ($0.userID, $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.itemGap) {
            HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                Text("results.standings.title")
                    .typeStyle(.displayM)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: Space.sm)
                SectionLabel(
                    verbatim: Copy.format("results.standings.rounds", standings.roundsPlayed)
                )
            }
            table
        }
    }

    /// One surface with rules between the rows, rather than a card each. A list of eight cards
    /// is eight things; a list of eight rows is one table, which is what this is.
    private var table: some View {
        VStack(spacing: Space.none) {
            ForEach(Array(standings.bestEar.enumerated()), id: \.element.id) { index, standing in
                if index > 0 { Rule() }
                StandingRow(
                    standing: standing,
                    readability: readabilityByUser[standing.userID]
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                .stroke(Palette.edge, lineWidth: Stroke.border)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
    }
}

/// One person: where they sit on ear, what they are called, and the two numbers.
private struct StandingRow: View {
    let standing: EarStandingDTO
    /// `nil` when the readability list does not carry this person — someone who has never had a
    /// song of theirs in a round has an ear and no readability, and a zero would be a lie.
    let readability: ReadabilityStandingDTO?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isStacked: Bool { dynamicTypeSize >= .accessibility1 }

    var body: some View {
        row
            .padding(.horizontal, Layout.rowInset + Space.xs)
            .padding(.vertical, Layout.rowInset)
            // One stop per person. The rank, the name and the numbers are one fact about one
            // member, and four swipes to hear it is three too many (`docs/12` §2).
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: announcement))
            .accessibilityAddTraits(.isStaticText)
    }

    @ViewBuilder private var row: some View {
        if isStacked {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                    rank
                    name
                }
                numbers
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                rank
                name
                Spacer(minLength: Space.sm)
                numbers
            }
        }
    }

    /// Tabular and monospaced, so a two-digit rank does not shift the column of names beside it.
    private var rank: some View {
        Text(verbatim: standing.rank.formatted(.number.grouping(.never)))
            .typeStyle(.monoS)
            .foregroundStyle(Palette.inkDim)
            .frame(minWidth: Space.lg, alignment: .leading)
    }

    /// One truncating line while the row is a row, wrapping once it has stacked.
    ///
    /// A display name runs to 24 characters, which at `.large` is most of an SE's width, so an
    /// unbounded name would wrap and leave the numbers floating beside its third line.
    private var name: some View {
        Text(verbatim: standing.displayName)
            .typeStyle(.bodyLStrong)
            .foregroundStyle(Palette.ink)
            .lineLimit(isStacked ? nil : 1)
            .truncationMode(.tail)
            .frame(maxWidth: isStacked ? .infinity : nil, alignment: .leading)
    }

    /// *"EAR 78 · READ 62"* — both numbers, in the apparatus voice, so neither reads as the
    /// score. The middot is a separator, not copy.
    private var numbers: some View {
        SectionLabel(verbatim: Copy.format(
            "results.standings.row",
            ScoringFormat.percentValue(standing.earAllTime),
            ScoringFormat.percentValue(readability?.readabilityAllTime ?? 0)
        ))
        .fixedSize()
    }

    private var announcement: String {
        let ear = "\(standing.displayName). \(Copy.format("results.standings.ear.detail", standing.earCorrectTotal))"
        guard let readability else { return ear }
        return "\(ear) \(Copy.A11y.readability(percent: ScoringFormat.percentValue(readability.readabilityAllTime), band: readability.band))"
    }
}
