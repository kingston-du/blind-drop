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
    /// Opens the tapped member's profile. Defaults to a no-op so every existing call site (and
    /// every snapshot) keeps rendering the same static table until it opts in.
    var select: (MemberDTO) -> Void = { _ in }

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
                    readability: readabilityByUser[standing.userID],
                    select: select
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
///
/// Tappable (`E35`) — reopens the question `E24-01`'s comment on `StandingRowContent` answers:
/// the same fact about the same person now opens their profile from *both* the all-time table
/// and `GroupScreen`'s roster, and it is still one shared layout doing it, just wrapped in a
/// `Button` here too instead of the old static `accessibilityAddTraits(.isStaticText)`.
private struct StandingRow: View {
    let standing: EarStandingDTO
    /// `nil` when the readability list does not carry this person — someone who has never had a
    /// song of theirs in a round has an ear and no readability, and a zero would be a lie.
    let readability: ReadabilityStandingDTO?
    let select: (MemberDTO) -> Void

    var body: some View {
        Button {
            select(MemberDTO(userID: standing.userID, displayName: standing.displayName, role: nil))
        } label: {
            StandingRowContent(standing: standing, readability: readability)
                .padding(.horizontal, Layout.rowInset + Space.xs)
                .padding(.vertical, Layout.rowInset)
        }
        .buttonStyle(.plain)
        // One stop per person. The rank, the name and the numbers are one fact about one
        // member, and four swipes to hear it is three too many (`docs/12` §2).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: StandingRowContent.announcement(
            standing: standing, readability: readability
        )))
        .accessibilityHint(Copy.string("insights.profile.hint"))
        .accessibilityAddTraits(.isButton)
    }
}

/// The rank, the name and the two numbers, undressed — no padding, no accessibility wrapper,
/// no trait. `StandingRow` above wraps this as static text for the all-time table; `GroupScreen`
/// (`E24-01`) wraps the identical layout in a `Button`, because the same fact about the same
/// person is a row to read in one place and a row to tap in the other, and the numbers, the
/// rank and the tie-break must not diverge between the two — there is exactly one place this
/// layout is drawn.
struct StandingRowContent: View {
    let standing: EarStandingDTO
    /// `nil` when the readability list does not carry this person — someone who has never had a
    /// song of theirs in a round has an ear and no readability, and a zero would be a lie.
    let readability: ReadabilityStandingDTO?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isStacked: Bool { dynamicTypeSize >= .accessibility1 }

    var body: some View {
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
    /// **The flight card's own numeral** (`E28-08`), not `StandingRow`'s old plain `monoS` —
    /// zero-padded and set in the display face, in neutral `ink` rather than an accent this
    /// screen has none of, so a rank reads as *the game's* number rather than a settings list's
    /// row index. `FlightCard.numberColumnWidth` is `private`; `Layout.standingsNameColumn`-style
    /// fixed width is approximated here with the same two-digit tabular-figure logic, kept small
    /// on purpose rather than duplicating that measurement.
    private var rank: some View {
        Text(verbatim: String(format: "%02lld", standing.rank))
            .typeStyle(.numberM)
            .foregroundStyle(Palette.ink)
            .fixedSize()
            .frame(minWidth: Space.xxl, alignment: .leading)
    }

    /// Two lines before truncating, so a reasonable-length name is read whole instead of cut to
    /// fit beside the stats. The stats moved to a stacked column (below) exactly so this name can
    /// spend the width on itself.
    ///
    /// **No `MonogramMark` here** (`E28-08`, reverted after measuring it). This row already
    /// carries a rank numeral, and on `GroupScreen`'s admin view it also shares its width with a
    /// fixed-size numbers block *and* a trailing action menu — on an SE that combination is
    /// already tighter than the mark's 36pt cost, and adding it there squeezed the name itself
    /// to nothing, which a snapshot golden caught before this shipped. `MemberRosterRow` and
    /// `InsightLeaderboardScreen` still carry the mark; both have room this row does not.
    private var name: some View {
        Text(verbatim: standing.displayName)
            .typeStyle(.bodyLStrong)
            .foregroundStyle(Palette.ink)
            .lineLimit(isStacked ? nil : 2)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// *"EAR 78"* over *"READ 62"* — the ear number and readability value (or an honest *"—"*
    /// when it does not apply), stacked in the apparatus voice so neither reads as the score and
    /// neither competes with the name for one line's width.
    private var numbers: some View {
        VStack(alignment: .trailing, spacing: Space.xxs) {
            SectionLabel(verbatim: Copy.format(
                "results.standings.ear.row",
                ScoringFormat.percentValue(standing.earAllTime)
            ))
            SectionLabel(verbatim: Copy.format(
                "results.standings.read.row",
                ScoringFormat.percent(readability?.readabilityAllTime)
            ))
        }
        .fixedSize()
    }

    /// The row's whole fact, in one sentence — what both wrapping views hand VoiceOver, whether
    /// as the entire label (`StandingRow`) or as the shared half of one (`GroupScreen`'s row
    /// adds its own hint, not a second label).
    static func announcement(standing: EarStandingDTO, readability: ReadabilityStandingDTO?) -> String {
        let ear = "\(standing.displayName). \(Copy.format("results.standings.ear.detail", standing.earCorrectTotal))"
        guard let readability else { return ear }
        return "\(ear) \(Copy.A11y.readability(percent: ScoringFormat.percentValue(readability.readabilityAllTime), band: readability.band))"
    }
}
