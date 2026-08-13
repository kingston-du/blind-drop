import SwiftUI

/// Everything on the share card, as a value (`docs/10` §2).
///
/// > Group name · date · up to 4 flight rows (number, artwork, title, owner) · overflow count ·
/// > one headline stat · the Best Ear leader · the wordmark.
///
/// And, just as importantly, everything that is **not** on it: no QR code, no install link, no
/// store badge, no avatars, no user ids, no invite code, no group id, and no scores for anybody
/// who is not the headline. *"The card is a group artifact — it works because it looks like
/// something the group made, not like an ad."* There is nowhere in this type to put any of them,
/// which is the same trick `RoundDTO` plays on the blind window: a rule you cannot represent is
/// a rule nobody has to remember.
struct ShareCardContent: Equatable, Sendable {
    let groupName: String
    /// *"10 August"*, in the **group's** calendar (`docs/13` §5 rule 6).
    let date: String
    /// The first four cards **by `card_no`**, not by any ranking of how interesting they were.
    /// *"Numbering is the game's spine; resorting it for the share card would misrepresent the
    /// night."* (`docs/10` §2)
    let rows: [ResultCardDTO]
    /// How many cards did not fit. Zero draws nothing.
    let overflow: Int
    /// The one headline (`ShareHeadline`).
    let headline: String
    /// Tonight's best ear — the name and the rate — or `nil` on a night where nobody guessed.
    let bestEar: Leader?

    struct Leader: Equatable, Sendable {
        let name: String
        let rate: Double
    }

    init(results: ResultsDTO, groupName: String, date: String) {
        self.groupName = groupName
        self.date = date
        rows = Array(results.cards.prefix(ShareCard.maximumRows))
        overflow = max(0, results.cards.count - ShareCard.maximumRows)
        headline = ShareHeadline.line(for: results)
        // **Tonight's** leader, not the all-time one: the card is about one night, and
        // `docs/10` §2's own example prints *"Cal 100%"* — Cal's ear for the `docs/02` §4.4
        // round, where his all-time is 79%.
        bestEar = results.people
            .compactMap { person in person.ear.map { Leader(name: person.displayName, rate: $0) } }
            .max { $0.rate < $1.rate }
    }
}

/// The share card itself — **one view, a `variant` parameter, two artifacts**, so a copy change
/// lands in both (`docs/10` §1).
///
/// Two things make this view unlike every other view in the app:
///
/// 1. **It is an image, so it has no Dynamic Type.** The type size is pinned at `.large` and the
///    row number is the one place in the codebase a literal point size is legal — `docs/10` §3
///    gives it two, 96pt and 112pt in the artifact's space. Everything else is a `TypeStyle`,
///    because *"identical tokens to the app — the card must look like it came from the app,
///    because that is the entire distribution mechanism."*
/// 2. **Ultramarine only. Amber must not appear** (`docs/10` §3). The card is a post-results
///    artifact and nothing on it is sealed — including the caller's own card, which was the one
///    amber exception the reveal screen made. `ShareCardSnapshotTests` asserts the pixels.
struct ShareCardView: View {
    let content: ShareCardContent
    let variant: ShareCard.Variant

    private let accent = PhaseAccent.revealed

    var body: some View {
        // The gaps are `Spacer`s with minimums rather than a stack spacing, so the card breathes
        // into whatever is left over and the wordmark sits on the bottom margin in both shapes.
        // A fixed spacing would make the story variant's extra 570 points of height appear as
        // one hole under the flight instead of as air throughout.
        VStack(alignment: .leading, spacing: Space.none) {
            header
            Spacer(minLength: ShareCard.blockGap)
            flight
            Spacer(minLength: ShareCard.blockGap)
            headlinePair
            Spacer(minLength: ShareCard.rowGap)
            wordmark
        }
        .padding(variant.margin)
        // *"an extra 240pt of bottom safe space so the Instagram UI does not cover the
        // wordmark"* (`docs/10` §3).
        .padding(.bottom, variant.bottomSafeSpace)
        .frame(width: variant.size.width, height: variant.size.height, alignment: .topLeading)
        .background(Palette.paper)
        // An image has no Dynamic Type. Pinned rather than inherited so the artifact is the same
        // 1080 × 1350 whether the person sharing it reads at `.xSmall` or `.accessibility5` —
        // their setting is about their screen, and this is leaving the device.
        .dynamicTypeSize(.large)
    }

    // MARK: - Header

    /// *"THE COVE · 10 AUGUST"* — the group and the night, and nothing that identifies either to
    /// somebody outside the group (`docs/10` §5).
    private var header: some View {
        VStack(alignment: .leading, spacing: ShareCard.rowGap) {
            dateline
            Text("reveal.title")
                .typeStyle(.displayL)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The middot is a separator, not copy — the same call `RevealScreen` makes for the one
    /// between its song count and its countdown. In the story variant *"the date moves under the
    /// group name"* (`docs/10` §3).
    @ViewBuilder private var dateline: some View {
        let label = { (text: String) in
            Text(verbatim: text)
                .typeStyle(.label)
                .foregroundStyle(Palette.inkDim)
        }
        if variant.stacksHeadline {
            VStack(alignment: .leading, spacing: Space.xxs) {
                label(content.groupName)
                label(content.date)
            }
        } else {
            label("\(content.groupName) · \(content.date)")
        }
    }

    // MARK: - The flight

    /// *"Background `paper`, rows on `surface` with `edge` hairlines"* (`docs/10` §3).
    private var flight: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            VStack(spacing: Space.none) {
                ForEach(Array(content.rows.enumerated()), id: \.element.cardNumber) { index, card in
                    if index > 0 {
                        Rectangle()
                            .fill(Palette.edge)
                            .frame(height: Stroke.border)
                    }
                    row(card)
                }
            }
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(Palette.edge, lineWidth: Stroke.border)
            )

            if content.overflow > 0 {
                Text(verbatim: Copy.format("share.overflow", content.overflow))
                    .typeStyle(.caption)
                    .foregroundStyle(Palette.inkFaint)
            }
        }
    }

    private func row(_ card: ResultCardDTO) -> some View {
        HStack(spacing: ShareCard.rowGap) {
            Text(verbatim: card.cardNumber.formatted(.number.grouping(.never)))
                .font(Font(Typography.fixed(.display, size: variant.numberSize)))
                .foregroundStyle(accent.mark)
                .fixedSize()

            ArtworkView(card.track, size: ShareCard.artwork)

            // **The title truncates before the owner does** (`docs/10` §3). Two mechanisms, both
            // needed: the owner's layout priority is what makes SwiftUI take the width out of the
            // title first, and the middle ellipsis is what keeps a 90-character title readable at
            // both ends rather than trailing off into nothing.
            Text(verbatim: card.track.title)
                .typeStyle(.bodyLStrong)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(verbatim: card.owner.displayName)
                .typeStyle(.bodyM)
                .foregroundStyle(Palette.inkDim)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: ShareCard.ownerColumn, alignment: .trailing)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
        .padding(.horizontal, ShareCard.rowGap)
        .padding(.vertical, ShareCard.rowPadding)
    }

    // MARK: - The headline pair

    /// The headline and the Best Ear leader. *"Never more than one headline"* (`docs/10` §2), and
    /// no scores for anybody who is not in this pair.
    @ViewBuilder private var headlinePair: some View {
        if variant.stacksHeadline {
            VStack(alignment: .leading, spacing: ShareCard.rowGap) {
                headline
                bestEar
            }
        } else {
            // Bottom-aligned, so the headline sits level with *"Cal 100%"* rather than with the
            // label above it — the two values line up and the label reads as a caption on one
            // of them instead of as a heading over both.
            HStack(alignment: .bottom, spacing: ShareCard.rowGap) {
                headline
                    .frame(maxWidth: .infinity, alignment: .leading)
                bestEar
            }
        }
    }

    /// Two lines at most, shrinking rather than clipping.
    ///
    /// The card is a **fixed rectangle**, so a third line does not push the wordmark down — it
    /// pushes it off the artifact. The longest headline the deck can produce is *"%@ read the
    /// whole room"* with a 24-character display name, which is the case this bounds. Shrinking a
    /// little is the least bad of the three options: truncating loses the sentence, clipping
    /// loses the wordmark, and both are worse than 15pt of mono.
    private var headline: some View {
        Text(verbatim: content.headline)
            .typeStyle(.monoM)
            .foregroundStyle(Palette.ink)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var bestEar: some View {
        if let leader = content.bestEar {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("share.bestear.label")
                    .typeStyle(.label)
                    .foregroundStyle(Palette.inkDim)
                HStack(spacing: Space.sm) {
                    Text(verbatim: leader.name)
                        .typeStyle(.monoM)
                        .foregroundStyle(Palette.ink)
                    Text(verbatim: ScoringFormat.percent(leader.rate))
                        .typeStyle(.monoM)
                        .foregroundStyle(accent.text)
                }
            }
        }
    }

    // MARK: - The wordmark

    /// *"The name at the bottom is the whole marketing"* (`docs/10` §2). No badge, no link, no
    /// QR code, and nothing else after it.
    private var wordmark: some View {
        Text("share.wordmark")
            .typeStyle(.caption)
            .foregroundStyle(Palette.inkFaint)
    }
}
