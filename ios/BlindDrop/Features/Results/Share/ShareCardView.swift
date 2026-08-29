import SwiftUI

/// Everything on the share card, as a value (`docs/10` §2, revised by `E36-01`).
///
/// > Group name · date · a hero headline · **the caller's own ear and readability, and what
/// > the room guessed for their card** · tonight's Ear top 3 · the wordmark. On a night the
/// > caller has nothing personal to report, the card falls back to `E30-01`'s shape: the group
/// > headline and the full-size filmstrip.
///
/// And, just as importantly, everything that is **not** on it: no QR code, no install link, no
/// store badge, no avatars, no user ids, no invite code, no group id, no all-time number for
/// anybody, no readability for anybody but the caller, and no guesser is ever named — a tally of
/// *"Cal ×3"* goes on the card, *"Maya thought you were Cal"* does not (`E36-01`'s epic file has
/// the reasoning). *"The card is the sharer's account of the night — it still works because it
/// looks like something the group made, not like an ad."* There is nowhere in this type to put
/// any of the banned things, which is the same trick `RoundDTO` plays on the blind window: a
/// rule you cannot represent is a rule nobody has to remember.
struct ShareCardContent: Equatable, Sendable {
    let groupName: String
    /// *"10 August"*, in the **group's** calendar (`docs/13` §5 rule 6).
    let date: String
    /// The first four cards **by `card_no`**, not by any ranking of how interesting they were.
    /// *"Numbering is the game's spine; resorting it for the share card would misrepresent the
    /// night."* (`docs/10` §2) Always populated; only the **view** draws it conditionally — on
    /// the no-personal-night fallback (`E36-01`, see `hasPersonalNight`).
    let rows: [ResultCardDTO]
    /// How many cards did not fit. Zero draws nothing.
    let overflow: Int
    /// The one headline (`ShareHeadline`) — the card's hero.
    let headline: String

    /// Whether the caller has a night of their own to report: their own card was in the room
    /// (`ShareHeadline.ownCard(in:)`). `false` for anybody who did not submit — every personal
    /// band below is empty for exactly that reason (`docs/02` §4.1), so this flag, not a second
    /// check per band, is what the view branches on.
    let hasPersonalNight: Bool
    /// The caller's own ear, `nil` if they never guessed (`docs/04` §4 — "never guessing is not
    /// the same as guessing badly").
    let ear: Double?
    /// The caller's own readability, its fraction, and its band — all three or none, since a
    /// submitter who was read by nobody still has `0/N`, not `nil` (`PersonalScoreDTO`).
    let readability: Double?
    let readabilityCorrect: Int?
    let readabilityPossible: Int?
    let readabilityBand: ReadabilityBand?
    /// What the room guessed for the caller's own card, descending by how many people named
    /// that person — the caller's own entry among them, never a guesser's name (`E36-01`).
    let roomTally: [RoomGuess]
    /// Distinct names guessed that did not fit (`ShareCard.maximumRoomTallyNames`).
    let roomTallyOverflow: Int
    /// Tonight's Ear top 3, ties sharing a rank and never split (`E29-01`, `docs/02` §4.5 —
    /// there is no readability counterpart and never will be). Replaces the old standalone Best
    /// Ear footer, which was exactly rank 1 of this same ranking said a second time.
    let tonightTop: [TonightEarDTO]
    /// Rows a boundary tie pushed past `ShareCard.maximumPodiumRows`.
    let tonightTopOverflow: Int

    /// One row of the room's tally (`E36-01`).
    struct RoomGuess: Equatable, Sendable, Identifiable {
        let name: String
        let count: Int
        /// Whether this row is the caller's own name — the one thing the tally is allowed to
        /// mark, and it marks it with the accent, never a word (`docs/16` §5).
        let isMe: Bool
        var id: String { name }
    }

    init(results: ResultsDTO, groupName: String, date: String) {
        self.groupName = groupName
        self.date = date
        headline = ShareHeadline.line(for: results)

        let ownCard = ShareHeadline.ownCard(in: results)
        hasPersonalNight = ownCard != nil

        // Selection and order are the same regardless of which night this is — only the view
        // decides whether to draw them at all (see `ShareCardStack.body`).
        rows = Array(results.cards.prefix(ShareCard.maximumRows))
        overflow = max(0, results.cards.count - ShareCard.maximumRows)

        ear = results.me.ear
        readability = results.me.readability
        readabilityCorrect = results.me.readabilityCorrect
        readabilityPossible = results.me.readabilityPossible
        readabilityBand = results.me.readability.map(ReadabilityBand.init(readability:))

        let tally = Self.roomTally(ownCard: ownCard)
        roomTally = Array(tally.prefix(ShareCard.maximumRoomTallyNames))
        roomTallyOverflow = max(0, tally.count - roomTally.count)

        tonightTop = Array(results.tonightTopEar.prefix(ShareCard.maximumPodiumRows))
        tonightTopOverflow = max(0, results.tonightTopEar.count - tonightTop.count)
    }

    /// The room's read on the caller's own card, descending by count, ties keeping the order the
    /// guesses arrived in (`docs/04` §4's own order) so two names on the same count do not swap
    /// between renders. Grouped by `guessedUserID`, not by name — two members can share a
    /// display name, and the tally must not fold them into one row because they happen to.
    private static func roomTally(ownCard: ResultCardDTO?) -> [RoomGuess] {
        guard let ownCard, let guesses = ownCard.guesses, !guesses.isEmpty else { return [] }

        var order: [String] = []
        var counts: [String: Int] = [:]
        var names: [String: String] = [:]
        for guess in guesses {
            if counts[guess.guessedUserID] == nil { order.append(guess.guessedUserID) }
            counts[guess.guessedUserID, default: 0] += 1
            names[guess.guessedUserID] = guess.guessedName
        }

        return order.enumerated()
            .map { offset, id in
                (offset: offset, row: RoomGuess(
                    name: names[id] ?? "",
                    count: counts[id] ?? 0,
                    isMe: id == ownCard.owner.userID
                ))
            }
            .sorted { lhs, rhs in
                lhs.row.count != rhs.row.count
                    ? lhs.row.count > rhs.row.count
                    : lhs.offset < rhs.offset
            }
            .map(\.row)
    }
}

/// The share card itself — **one view, a `variant` parameter, two artifacts**, so a copy change
/// lands in both (`docs/10` §1).
///
/// `E36-01` made the card the sharer's account of the night: their own ear and readability, what
/// the room guessed for their card, and tonight's Ear top 3, ahead of the `E30-01` hero headline
/// this view keeps unchanged. See `docs/10` §2 for the layout this replaced and why; the
/// design-critique rationale for this one is in `E36-01`'s slice notes.
///
/// Three things make this view unlike every other view in the app:
///
/// 1. **It is an image, so it has no Dynamic Type.** The type size is pinned at `.large`.
///    Everything is a `TypeStyle`, because *"identical tokens to the app — the card must look
///    like it came from the app, because that is the entire distribution mechanism."*
/// 2. **Ultramarine only. Amber must not appear** (`docs/10` §3). The card is a post-results
///    artifact and nothing on it is sealed — including the caller's own card, which was the one
///    amber exception the reveal screen made. `ShareCardSnapshotTests` asserts the pixels.
/// 3. **Nothing is laid over the artwork, ever** (`docs/16` §5).
struct ShareCardView: View {
    let content: ShareCardContent
    let variant: ShareCard.Variant

    var body: some View {
        ShareCardStack(content: content, variant: variant)
            .padding(variant.margin)
            // *"an extra 240pt of bottom safe space so the Instagram UI does not cover the
            // wordmark"* (`docs/10` §3).
            .padding(.bottom, variant.bottomSafeSpace)
            .frame(width: variant.size.width, height: variant.size.height, alignment: .topLeading)
            .background(Palette.paper)
            // An image has no Dynamic Type. Pinned rather than inherited so the artifact is the
            // same 1080 × 1350 whether the person sharing it reads at `.xSmall` or
            // `.accessibility5` — their setting is about their screen, and this is leaving the
            // device.
            .dynamicTypeSize(.large)
    }
}

/// The card's content, **unconstrained in height**.
///
/// `ShareCardView` wraps this in the fixed `variant.size` frame that makes it an artifact;
/// `ShareCardFitTests` renders this type **on its own**, at the variant's content width and an
/// unbounded height, to measure whether the content actually fits inside that frame.
/// `ImageRenderer` does not clip a view that overflows its frame — it draws past the canvas and
/// the pixels are simply gone — so "fits" has to be something a test proves, not something the
/// layout is merely expected to do (`docs/10` §3, §6).
struct ShareCardStack: View {
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
            // `stackGap`, not `blockGap`, below the hero (`E36-01`) — the header-to-hero gap
            // stays the card's one generous breath, and every seam after it tightens by one
            // step now that the podium sits on every card, measured against `ShareCardFitTests`
            // rather than assumed.
            Spacer(minLength: ShareCard.stackGap)
            if content.hasPersonalNight {
                personalStats
                Spacer(minLength: ShareCard.stackGap)
                roomTally
                Spacer(minLength: ShareCard.stackGap)
            }
            if !content.tonightTop.isEmpty {
                podium
                Spacer(minLength: ShareCard.stackGap)
            }
            // The filmstrip only draws on the no-personal-night fallback (`E36-01`) — a fixed
            // 402pt-tall canvas does not have room for it *and* four personal/group bands at
            // once, measured by `ShareCardFitTests` rather than assumed. On a personal night the
            // filmstrip's job — "this is what got shared tonight" — is already done by the room
            // tally and the podium naming actual songs' outcomes; on the fallback it is the only
            // texture the card has, so it keeps its full `E30-01` size there.
            if !content.hasPersonalNight, !content.rows.isEmpty {
                filmstrip
                Spacer(minLength: ShareCard.stackGap)
            }
            wordmark
        }
    }

    // MARK: - Header

    /// *"THE COVE" ... "10 AUGUST"* — the group and the night, and nothing that identifies either
    /// to somebody outside the group (`docs/10` §5). Two ends of one row, not a middot — the
    /// `Spacer` between them is the separator, not a literal character.
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

    /// **The dominant visual weight on the card** (`E30-01`'s whole point, unchanged by
    /// `E36-01`). A small mono kicker sits above it at `label` size — *"Your night"* on a night
    /// the caller has one, *"Tonight's drop"* on the group fallback — and the headline sentence
    /// itself is set at `displayXL`, the largest step in the display face.
    ///
    /// Shrinks rather than clips on its worst case — a `DisplayName.maximumLength` name in
    /// either a personal or a group headline — for the same reason it always has: the card is a
    /// **fixed rectangle**, so a line this cannot fit does not grow the card, it pushes
    /// everything under it off. `0.4` is the floor `E30-01` measured and documented; unchanged
    /// here because the personal headlines (*"Nobody got you"*, etc.) are all shorter than the
    /// group sentence this floor was tuned against.
    private var heroHeadline: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(LocalizedStringKey(content.hasPersonalNight ? "share.kicker" : "reveal.title"))
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

    // MARK: - Your numbers

    /// The caller's own ear and readability (`E36-01`) — the first of the two personal bands,
    /// and the reason `docs/10` §2's *"no scores for anyone but the headline"* needed an owner
    /// amendment. One row, an inline label ahead of each value, rather than the two
    /// label-over-value columns an early draft used: `ShareCardFitTests` is what settled it —
    /// a fixed-height card with two new list bands to make room for cannot also afford a second
    /// label row here, and the two numbers read together either way.
    private var personalStats: some View {
        HStack(alignment: .firstTextBaseline, spacing: ShareCard.blockGap) {
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Text("share.ear.label")
                    .typeStyle(.bodyS)
                    .foregroundStyle(Palette.inkDim)
                Text(verbatim: ScoringFormat.percent(content.ear))
                    .typeStyle(.bodyLStrong)
                    .foregroundStyle(accent.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Text("share.read.label")
                    .typeStyle(.bodyS)
                    .foregroundStyle(Palette.inkDim)
                readabilityLine
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }

    /// *"4 of 7 · Legible"* — the fraction and the band, never a rank (`docs/02` §4.5 forbids
    /// ranking readability at any scope, including this one-line summary of the caller's own).
    /// Two `Text` runs rather than one formatted string, the same reason `bestEarFooter` used to
    /// be two: the fraction and the band read at different weights.
    @ViewBuilder private var readabilityLine: some View {
        if let correct = content.readabilityCorrect,
           let possible = content.readabilityPossible,
           let band = content.readabilityBand {
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Text(verbatim: Copy.format("share.read.fraction", correct, possible))
                    .typeStyle(.bodyLStrong)
                    .foregroundStyle(Palette.ink)
                Text(verbatim: Copy.band(band))
                    .typeStyle(.bodyS)
                    .foregroundStyle(Palette.inkDim)
            }
        } else {
            Text(verbatim: ScoringFormat.unavailable)
                .typeStyle(.bodyLStrong)
                .foregroundStyle(Palette.inkDim)
        }
    }

    // MARK: - The room's read on you

    /// What the room guessed for the caller's own card (`E36-01`) — a tally, never an
    /// attribution. *"Cal ×3"* is on the card; *"Maya thought you were Cal"* is not, because
    /// publishing a named person's wrong guess outside the circle is not something the guesser
    /// agreed to (the epic file's open question has the full reasoning).
    ///
    /// The caller's own name is the one row set in `accent.text` rather than `ink` — the whole
    /// legend this line needs, and the only one `docs/16` §5 leaves room for: no tick, no cross,
    /// no colour pair, just the same accent that already means "revealed" everywhere else on
    /// this card.
    @ViewBuilder private var roomTally: some View {
        if !content.roomTally.isEmpty {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("share.room.title")
                    .typeStyle(.label)
                    .foregroundStyle(Palette.inkDim)
                roomTallyLine
                    .typeStyle(.bodyS)
                    .lineLimit(2)
                    .minimumScaleFactor(0.55)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var roomTallyLine: Text {
        joinedLine(
            content.roomTally.map { guess in
                (
                    text: guess.count > 1
                        ? Copy.format("share.room.tally.multiple", guess.name, guess.count)
                        : Copy.format("share.room.tally.single", guess.name),
                    highlighted: guess.isMe
                )
            },
            overflow: content.roomTallyOverflow
        )
    }

    // MARK: - Tonight's Ear

    /// Tonight's Ear top 3 (`E29-01`, ties sharing a rank and never split), replacing the old
    /// standalone Best Ear footer — that line was always rank 1 of this same ranking, said a
    /// second time (`E36-01`). A compact row per person rather than one joined sentence: at up
    /// to `ShareCard.maximumPodiumRows` entries, each carrying a rank, a name and a rate, one
    /// line reliably ran past the card's content width and needed two — a fixed-height card can
    /// afford four short rows more easily than it can afford one wide one wrapping twice
    /// (`ShareCardFitTests` is where this was actually measured, not guessed).
    private var podium: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text("share.tonight.title")
                .typeStyle(.label)
                .foregroundStyle(Palette.inkDim)
            VStack(alignment: .leading, spacing: Space.xxs) {
                ForEach(content.tonightTop) { row in
                    podiumRow(row)
                }
                if content.tonightTopOverflow > 0 {
                    Text(verbatim: Copy.format("share.overflow", content.tonightTopOverflow))
                        .typeStyle(.caption)
                        .foregroundStyle(Palette.inkDim)
                }
            }
        }
    }

    private func podiumRow(_ row: TonightEarDTO) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            Text(verbatim: "\(row.rank)")
                .typeStyle(.bodyS)
                .foregroundStyle(Palette.inkDim)
                .lineLimit(1)
                .fixedSize()
            Text(verbatim: row.displayName)
                .typeStyle(.bodyS)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .layoutPriority(0)
            Spacer(minLength: Space.xs)
            Text(verbatim: ScoringFormat.percent(row.ear))
                .typeStyle(.bodyS)
                .foregroundStyle(accent.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)
        }
    }

    /// Joins a run of parts with " · ", each part carrying its own colour, plus an optional
    /// overflow suffix in `inkDim` (`share.overflow`, the same shape the filmstrip's own
    /// overflow caption uses). Shared by the room tally and the podium — the only two places on
    /// this card that draw a list as one line rather than one block.
    private func joinedLine(_ parts: [(text: String, highlighted: Bool)], overflow: Int) -> Text {
        var combined: Text?
        for part in parts {
            let piece = Text(verbatim: part.text)
                .foregroundStyle(part.highlighted ? accent.text : Palette.ink)
            combined = combined.map { $0 + Text(verbatim: " · ") + piece } ?? piece
        }
        if overflow > 0 {
            let suffix = Text(verbatim: Copy.format("share.overflow", overflow))
                .foregroundStyle(Palette.inkDim)
            combined = combined.map { $0 + Text(verbatim: " · ") + suffix } ?? suffix
        }
        return combined ?? Text(verbatim: "")
    }

    // MARK: - The filmstrip

    /// Bare artwork, in `card_no` order, with no title, no owner, and no card number — texture,
    /// not a second thing competing to be read. `E30-01` full size, unchanged: this band draws
    /// only on the no-personal-night fallback (`E36-01`), where it is still the card's
    /// second-biggest idea and nothing else is competing with it for the canvas. The overflow
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

    // MARK: - The wordmark

    /// *"The name at the bottom is the whole marketing"* (`docs/10` §2). No badge, no link, no
    /// QR code, and nothing else after it.
    private var wordmark: some View {
        SectionLabel("share.wordmark")
    }
}
