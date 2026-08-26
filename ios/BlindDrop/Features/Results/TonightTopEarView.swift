import SwiftUI

/// This round's top 3 by Ear, beside the all-time table but never merged into it (`E29-01`,
/// `docs/08` §7.3) — a single night's ranking is not the group's whole history, and folding the
/// two together would blur exactly that distinction. A tie at the boundary can put more than
/// three rows here; it never splits one, the same rule the server's own ranking never breaks.
/// Never a readability counterpart, here or anywhere else (`docs/02` §4.5).
struct TonightTopEarView: View {
    let rows: [TonightEarDTO]

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.itemGap) {
            Text("results.tonight.title")
                .typeStyle(.displayM)
                .foregroundStyle(Palette.ink)
            table
        }
    }

    private var table: some View {
        VStack(spacing: Space.none) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Rule() }
                TonightEarRow(row: row)
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

/// One row: the rank, the name, the ear — all three in the revealed-data accent, because unlike
/// the all-time table this module has nothing neutral to say beside it (no readability rides
/// along here; there is no per-round readability ranking to carry, `docs/02` §4.5).
private struct TonightEarRow: View {
    let row: TonightEarDTO

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.md) {
            Text(verbatim: String(format: "%02lld", row.rank))
                .typeStyle(.numberM)
                .foregroundStyle(Palette.ultramarine)
                .fixedSize()
                .frame(minWidth: Space.xxl, alignment: .leading)
                .accessibilityHidden(true)
            Text(verbatim: row.displayName)
                .typeStyle(.bodyLStrong)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            SectionLabel(
                verbatim: Copy.format("results.standings.ear.row", ScoringFormat.percentValue(row.ear)),
                color: Palette.ultramarine
            )
            .fixedSize()
        }
        .padding(.horizontal, Layout.rowInset + Space.xs)
        .padding(.vertical, Layout.rowInset)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim:
            "\(row.displayName). \(Copy.format("results.standings.ear.row", ScoringFormat.percentValue(row.ear)))"
        ))
    }
}
