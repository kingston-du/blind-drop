import SwiftUI

/// This round's top ranks by correct answers, beside the recent standings (`E29-01`,
/// `docs/08` §7.3) — a single night's ranking is not the group's whole history, and folding the
/// two together would blur exactly that distinction. A tie at the boundary can put more than
/// three rows here; it never splits one, the same rule the server's own ranking never breaks.
/// Never a readability counterpart, here or anywhere else (`docs/02` §4.5).
struct TonightTopEarView: View {
    let rows: [TonightEarDTO]
    let submitterCount: Int
    var isPastRound = false
    /// Opens the tapped member's profile. Defaults to a no-op so existing call sites and
    /// snapshots keep rendering the same table until they opt in.
    var select: (MemberDTO) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.itemGap) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(isPastRound ? "results.tonight.past.title" : "results.tonight.title")
                    .typeStyle(.displayM)
                    .foregroundStyle(Palette.ink)
                Text("results.tonight.scope")
                    .typeStyle(.bodyS)
                    .foregroundStyle(Palette.inkDim)
            }
            table
        }
    }

    private var table: some View {
        VStack(spacing: Space.none) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Rule() }
                TonightEarRow(row: row, correctCount: row.correctCount(submitterCount: submitterCount), select: select)
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

/// The server's rank, identity and correct count. At accessibility sizes the score sits
/// beneath the name so the longer unit never squeezes the identity out of the row.
private struct TonightEarRow: View {
    let row: TonightEarDTO
    let correctCount: Int
    let select: (MemberDTO) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button {
            select(MemberDTO(userID: row.userID, displayName: row.displayName, role: nil))
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                Text(verbatim: String(format: "%02lld", row.rank))
                    .typeStyle(.numberM)
                    .foregroundStyle(Palette.ultramarine)
                    .fixedSize()
                    .frame(minWidth: Space.xxl, alignment: .leading)
                    .accessibilityHidden(true)
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        name
                        score
                    }
                } else {
                    name
                    score
                }
            }
            .padding(.horizontal, Layout.rowInset + Space.xs)
            .padding(.vertical, Layout.rowInset)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim:
            Copy.format("results.tonight.a11y", row.rank, row.displayName, correctCount)
        ))
        .accessibilityHint(Copy.string("insights.profile.hint"))
        .accessibilityAddTraits(.isButton)
    }

    private var name: some View {
        Text(verbatim: row.displayName)
            .typeStyle(.bodyLStrong)
            .foregroundStyle(Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var score: some View {
        SectionLabel(
            verbatim: Copy.format("results.tonight.correct", correctCount),
            color: Palette.ultramarine
        )
        .fixedSize()
    }
}
