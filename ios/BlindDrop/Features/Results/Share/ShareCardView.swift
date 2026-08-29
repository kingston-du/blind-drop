import SwiftUI

/// Everything on the share card, as a value (`docs/10` §2).
///
/// > Group name · date · tonight's numbered flight · a one-line headline · **the caller's own
/// > ear and readability, and what the room guessed for their card** · the wordmark.
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
    /// One row of the room's tally (`E36-01`).
    struct RoomGuess: Equatable, Sendable, Identifiable {
        let id: String
        let name: String
        let count: Int
        /// Whether this row is the caller's own name — the one thing the tally is allowed to
        /// mark, and it marks it with the accent, never a word (`docs/16` §5).
        let isMe: Bool
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
                    id: id,
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
/// The card combines the original numbered song table with the sharer's own ear, readability,
/// and the room's tally. See `docs/10` §2 for the exact hierarchy.
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
            // Story keeps extra bottom safe space so sharing chrome does not cover the
            // wordmark (`docs/10` §3).
            .padding(.bottom, variant.bottomSafeSpace)
            .frame(width: variant.size.width, height: variant.size.height, alignment: .topLeading)
            .background(Palette.paper)
            // An image has no Dynamic Type. Pinned rather than inherited so the artifact is the
            // same fixed artifact whether the person sharing it reads at `.xSmall` or
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
        VStack(alignment: .leading, spacing: Space.none) {
            header
            Spacer(minLength: ShareCard.blockGap)
            if !content.rows.isEmpty {
                flight
                Spacer(minLength: ShareCard.blockGap)
            }
            headline
            if content.hasPersonalNight {
                Spacer(minLength: ShareCard.stackGap)
                personalStats
                Spacer(minLength: ShareCard.stackGap)
                roomTally
            }
            Spacer(minLength: ShareCard.stackGap)
            wordmark
        }
    }

    // MARK: - Header

    /// *"THE COVE" ... "10 AUGUST"* — the group and the night, and nothing that identifies either
    /// to somebody outside the group (`docs/10` §5). Two ends of one row, not a middot — the
    /// `Spacer` between them is the separator, not a literal character.
    private var header: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
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
            Text("reveal.title")
                .typeStyle(.displayS)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
        }
    }

    // MARK: - The hero headline

    /// A confident one-line summary between the flight and the personal details. It is larger
    /// than body copy, but no longer competes with the table for most of the canvas. Long legal
    /// display names scale down rather than wrap or clip the rest of the fixed artifact.
    private var headline: some View {
        Text(verbatim: content.headline)
            .typeStyle(.displayS)
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    // MARK: - Tonight's drop

    private var flight: some View {
        // `Space.xs`, not `Space.sm`, between the table and its overflow caption — the caption is
        // attached to the table it annotates, and the card is a fixed height (`theCardFits`).
        VStack(alignment: .leading, spacing: Space.xs) {
            VStack(spacing: Space.none) {
                ForEach(content.rows, id: \.cardNumber) { card in
                    flightRow(card)
                    if card.cardNumber != content.rows.last?.cardNumber {
                        Rule(color: Palette.edge)
                    }
                }
            }
            .background(Palette.surface)
            .compositingGroup()
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Palette.edge, lineWidth: Stroke.border)
            }

            if content.overflow > 0 {
                Text(verbatim: Copy.format("share.overflow", content.overflow))
                    .typeStyle(.caption)
                    .foregroundStyle(Palette.inkDim)
            }
        }
    }

    private func flightRow(_ card: ResultCardDTO) -> some View {
        HStack(spacing: ShareCard.rowGap) {
            Text(verbatim: String(format: "%02lld", card.cardNumber))
                .font(Font(Typography.fixed(.display, size: variant.numberSize, weight: .heavy)))
                .foregroundStyle(accent.mark)
                .fixedSize()

            ArtworkView(card.track, size: ShareCard.artwork)

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
                .layoutPriority(1)
        }
        .padding(.horizontal, ShareCard.rowGap)
        .padding(.vertical, ShareCard.rowPadding)
    }

    // MARK: - Your numbers

    /// The caller's two scores use the same meter language as Results and Insights: Ear fills
    /// from the left; Readability is a neutral spectrum with one ultramarine position marker.
    /// Each sits on its own `surface` panel — the same card treatment Results' two `StatTile`s
    /// wear — so the two numbers read as cards rather than as floating text (`docs/10` §3). The
    /// inset is `Space.md`, the app's row inset, rather than the results screen's stat-tile inset
    /// (`Space.lg`): the card is a fixed-height image, and every point of panel chrome is one the
    /// flight and the room tally have to give up (`theCardFits` measures exactly this).
    private var personalStats: some View {
        HStack(alignment: .top, spacing: ShareCard.rowGap) {
            VStack(alignment: .leading, spacing: Space.xs) {
                SectionLabel("share.ear.label")
                Text(verbatim: ScoringFormat.percent(content.ear))
                    .typeStyle(.numberM)
                    .foregroundStyle(accent.text)
                    .lineLimit(1)
                    .fixedSize()
                ProportionTrack(progress: content.ear ?? 0, fill: accent.text)
            }
            .cardSurface(radius: Radius.panel, inset: Space.md)

            VStack(alignment: .leading, spacing: Space.xs) {
                SectionLabel("share.read.label")
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    Text(verbatim: ScoringFormat.percent(content.readability))
                        .typeStyle(.numberM)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: Space.xxs)
                    readabilityDetail
                        .typeStyle(.bodyS)
                        .foregroundStyle(Palette.inkDim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                if let readability = content.readability,
                   let band = content.readabilityBand {
                    StatMeter(
                        value: readability,
                        band: band,
                        showsBand: false,
                        usesSolidTrack: true
                    )
                }
            }
            .cardSurface(radius: Radius.panel, inset: Space.md)
        }
    }

    private var readabilityLine: Text {
        guard let correct = content.readabilityCorrect,
              let possible = content.readabilityPossible,
              let band = content.readabilityBand else {
            return Text(verbatim: ScoringFormat.unavailable)
        }
        return Text(verbatim: Copy.format("share.read.fraction", correct, possible))
            + Text(verbatim: " · ")
            + Text(verbatim: Copy.band(band))
    }

    /// Keep the ordinary, information-rich line when it fits. At the longest band name, the
    /// band itself wins over a clipped sentence: the percentage already carries the rate and
    /// "Unreadable" is more meaningful than a trailing ellipsis after the fraction.
    @ViewBuilder private var readabilityDetail: some View {
        ViewThatFits(in: .horizontal) {
            readabilityLine
            if let band = content.readabilityBand {
                Text(verbatim: Copy.band(band))
            } else {
                Text(verbatim: ScoringFormat.unavailable)
            }
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
            VStack(alignment: .leading, spacing: Space.xs) {
                SectionLabel("share.room.title")
                VStack(spacing: Space.none) {
                    ForEach(content.roomTally) { guess in
                        roomTallyRow(guess)
                        if guess.id != content.roomTally.last?.id {
                            Rule(color: Palette.edge)
                        }
                    }
                }
                .background(Palette.surface)
                .compositingGroup()
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(Palette.edge, lineWidth: Stroke.border)
                }
                if content.roomTallyOverflow > 0 {
                    Text(verbatim: Copy.format("share.overflow", content.roomTallyOverflow))
                        .typeStyle(.caption)
                        .foregroundStyle(Palette.inkDim)
                }
            }
        }
    }

    private func roomTallyRow(_ guess: ShareCardContent.RoomGuess) -> some View {
        // `.center`, not `.firstTextBaseline`: the name is `bodyLStrong` and the count is the
        // display face's `numberM` — two sizes that share a baseline fine on the results screen
        // (where every guesser row is the same size) but not here, where a 17pt name beside a
        // 26pt numeral would sit low against its row. Centring the pair keeps the name in the
        // middle of its own row.
        HStack(alignment: .center, spacing: Space.sm) {
            Text(verbatim: guess.name)
                .typeStyle(.bodyLStrong)
                .foregroundStyle(guess.isMe ? accent.text : Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: Space.sm)
            Text(verbatim: "\(guess.count)")
                .font(Font(Typography.fixed(.display, size: ShareCard.tallyCountSize, weight: .heavy)))
                .foregroundStyle(guess.isMe ? accent.text : Palette.ink)
                .fixedSize()
        }
        .padding(.horizontal, ShareCard.rowGap)
        .padding(.vertical, ShareCard.tallyRowPadding)
    }

    // MARK: - The wordmark

    /// *"The name at the bottom is the whole marketing"* (`docs/10` §2). No badge, no link, no
    /// QR code, and nothing else after it.
    private var wordmark: some View {
        SectionLabel("share.wordmark")
    }
}
