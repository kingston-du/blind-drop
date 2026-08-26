import SwiftUI

/// Everything on the share card, as a value (`docs/10` §2).
///
/// > Group name · date · a hero headline · up to 4 pieces of artwork · overflow count ·
/// > the Best Ear leader · the wordmark.
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
    /// night."* (`docs/10` §2) `E30-01` stopped printing their title and owner — the filmstrip
    /// draws only the artwork — but the selection and the order are unchanged.
    let rows: [ResultCardDTO]
    /// How many cards did not fit. Zero draws nothing.
    let overflow: Int
    /// The one headline (`ShareHeadline`) — the card's hero, now that `E30-01` gave it the
    /// dominant weight the table used to have.
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
        //
        // Ties go to the **first** person the server sent, not the last. `max(by:)` returns the
        // last of equal elements, which would let two people on 100% swap places between the
        // picker's thumbnail and the file it renders — the same card naming a different person
        // twice in one sitting.
        let leaders = results.people
            .compactMap { person in person.ear.map { Leader(name: person.displayName, rate: $0) } }
        bestEar = leaders.max { $0.rate < $1.rate }
            .flatMap { best in leaders.first { $0.rate == best.rate } }
    }
}

/// The share card itself — **one view, a `variant` parameter, two artifacts**, so a copy change
/// lands in both (`docs/10` §1).
///
/// `E30-01` rebuilt this view around one idea: the headline is the card's hero, not the song
/// table. What used to be up to four rows of number/artwork/title/owner is now a filmstrip of
/// bare artwork underneath a headline set at `displayXL` — the biggest the display face gets
/// (`docs/07` §3's "a results headline" is exactly this use). See `docs/10` §2 for the layout
/// this replaced and why; the design-critique rationale for this one is in `E30-01`'s slice
/// notes.
///
/// Three things make this view unlike every other view in the app:
///
/// 1. **It is an image, so it has no Dynamic Type.** The type size is pinned at `.large`.
///    Everything is a `TypeStyle`, because *"identical tokens to the app — the card must look
///    like it came from the app, because that is the entire distribution mechanism."* The one
///    literal size left is the Best Ear rate (`ShareCard.Variant.numberSize`), which `docs/10`
///    §3 gives two pixel values and no token for.
/// 2. **Ultramarine only. Amber must not appear** (`docs/10` §3). The card is a post-results
///    artifact and nothing on it is sealed — including the caller's own card, which was the one
///    amber exception the reveal screen made. `ShareCardSnapshotTests` asserts the pixels.
/// 3. **Nothing is laid over the artwork, ever** (`docs/16` §5). Bigger, bolder art is exactly
///    what this redesign asks for; a caption drawn on top of it is not on the table.
struct ShareCardView: View {
    let content: ShareCardContent
    let variant: ShareCard.Variant

    private let accent = PhaseAccent.revealed

    var body: some View {
        // The gaps are `Spacer`s with minimums rather than a stack spacing, so the card breathes
        // into whatever is left over and the wordmark sits on the bottom margin in both shapes.
        // A fixed spacing would make the story variant's extra height appear as one hole under
        // the headline instead of as air throughout.
        VStack(alignment: .leading, spacing: Space.none) {
            header
            Spacer(minLength: ShareCard.blockGap)
            heroHeadline
            Spacer(minLength: ShareCard.blockGap)
            if !content.rows.isEmpty {
                filmstrip
                Spacer(minLength: ShareCard.rowGap)
            }
            if content.bestEar != nil {
                bestEarFooter
                Spacer(minLength: ShareCard.rowGap)
            }
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

    /// *"THE COVE" ... "10 AUGUST"* — the group and the night, and nothing that identifies either
    /// to somebody outside the group (`docs/10` §5). Two ends of one row, not a middot — the
    /// `Spacer` between them is the separator, not a literal character. A masthead only now: the
    /// line that used to sit under it, naming the screen ("Tonight's drop"), moved into
    /// `heroHeadline` as a kicker — two big text blocks stacked back to back was two heroes
    /// competing for the one job the redesign gives the headline.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: ShareCard.rowGap) {
            Text(verbatim: content.groupName)
                .typeStyle(.displayS)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer(minLength: Space.sm)
            Text(verbatim: content.date)
                .typeStyle(.label)
                .foregroundStyle(Palette.inkDim)
        }
    }

    // MARK: - The hero headline

    /// **The dominant visual weight on the card** (`E30-01`'s whole point). A small mono kicker
    /// — the same *"Tonight's drop"* string the old header carried at `displayM` — sits above it
    /// at `label` size, so the string is not lost, only demoted to apparatus; the headline
    /// sentence itself is set at `displayXL`, the largest step in the display face and a size
    /// this card had never used before. Everything under it in the layout is deliberately
    /// smaller than this block.
    ///
    /// Shrinks rather than clips on its worst case — `"%@ read the whole room"` with a
    /// `DisplayName.maximumLength` name — for the same reason the old headline did: the card is
    /// a **fixed rectangle**, so a line this cannot fit does not grow the card, it pushes the
    /// wordmark off it.
    ///
    /// `0.4`, not a rounder-looking number, because greedy line-wrapping is not balanced
    /// wrapping: at `0.45` the worst case measured out to *"Bartholomew"* alone on line one
    /// (the pair doesn't fit at that scale) and *"Winterbornei read the whole room"* orphaned
    /// on line two, which is what actually clipped — the fix is not "shrink a little more", it
    /// is dropping below the scale where `"Bartholomew Winterbornei"` first fits as one line,
    /// so the wrap point lands between the two words instead of after just the first. Verified
    /// against the render (settles around `0.445`), not derived from a font metrics table that
    /// could drift from the bundled font file.
    ///
    /// The floor stops at `0.4` rather than going lower for margin: `docs/07` §"The display
    /// face" says *"do not use the display face below 20pt"*, and `displayXL` is 56pt, so
    /// anything under `20/56 ≈ 0.357` would let some future, longer headline (or a raised
    /// `DisplayName.maximumLength`) silently render under that floor with no test to catch it —
    /// a smaller-but-still-fitting golden looks identical to a rule violation. `0.4` clears that
    /// boundary with room to spare while sitting comfortably below the `~0.445` this case
    /// actually needs.
    private var heroHeadline: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("reveal.title")
                .typeStyle(.label)
                .foregroundStyle(Palette.inkDim)
            Text(verbatim: content.headline)
                .typeStyle(.displayXL)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - The filmstrip

    /// What the four-row data table shrank to: bare artwork, bigger than the old 96px thumbnail
    /// (`ShareCard.artwork`), in `card_no` order, with no title, no owner, and no card number —
    /// texture under the headline rather than a second thing competing to be read. The overflow
    /// caption is the one piece of text here, and it sits below the pictures, never on them.
    private var filmstrip: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: ShareCard.rowGap) {
                ForEach(content.rows, id: \.cardNumber) { card in
                    ArtworkView(card.track, size: ShareCard.artwork)
                }
            }
            if content.overflow > 0 {
                Text(verbatim: Copy.format("share.overflow", content.overflow))
                    .typeStyle(.caption)
                    .foregroundStyle(Palette.inkDim)
            }
        }
    }

    // MARK: - The Best Ear footer

    /// The night's one other figure (`docs/10` §2): nobody but the headline and this leader get
    /// a score on the card. No longer paired beside the headline sentence — the headline stands
    /// alone as the hero, and this is its own quiet line above the wordmark.
    @ViewBuilder private var bestEarFooter: some View {
        if let leader = content.bestEar {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("share.bestear.label")
                    .typeStyle(.label)
                    .foregroundStyle(Palette.inkDim)
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    // `DisplayName.maximumLength` beside the rate's own widest string is this
                    // pair's documented worst case (`docs/10` §6) — the story variant's narrower
                    // content width plus its larger `numberSize` (112 vs 96) leaves this line the
                    // tighter of the two shapes, so the name needs its own floor, not just the
                    // rate's.
                    Text(verbatim: leader.name)
                        .typeStyle(.bodyL)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .layoutPriority(0)
                    // **100% is the widest this string ever gets** — a third digit nobody laid
                    // out for. `heroHeadline` already shrinks rather than clips for the same
                    // reason; this is that same rule applied to the number the layout never gave
                    // a ceiling. Without it the extra digit pushes past the card's fixed edge,
                    // which `ImageRenderer` does not clip — it draws past the canvas and the
                    // glyph is simply gone. `layoutPriority(1)` so a long name gives way first —
                    // the rate is the number this line exists to show.
                    Text(verbatim: ScoringFormat.percent(leader.rate))
                        .font(Font(Typography.fixed(
                            .display, size: variant.numberSize, weight: .heavy
                        )))
                        .foregroundStyle(accent.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .layoutPriority(1)
                }
            }
        }
    }

    // MARK: - The wordmark

    /// *"The name at the bottom is the whole marketing"* (`docs/10` §2). No badge, no link, no
    /// QR code, and nothing else after it.
    private var wordmark: some View {
        SectionLabel("share.wordmark")
    }
}
