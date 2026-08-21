import SwiftUI

/// Everything `ResultsScreen` draws, as a value (`docs/13` §2).
///
/// The two sets are how far through `docs/09` §4's arrival each card is. They are sets rather
/// than a single "progress" number because the sequence has two tracks — a name, then its mark
/// 80ms later — and because a *set* is what both a running `ResolveAnimation` and a golden can
/// hand over. A snapshot of the middle of the sequence is otherwise unbuildable, and the middle
/// is the only place the no-layout rule can actually be checked.
struct ResultsViewState: Equatable, Sendable {

    /// The cards, **in the server's order** — which is `card_no`, the shuffle the whole group
    /// sees (`E03-04`). Not sorted here, for the same reason `RevealViewState` does not sort:
    /// the numbering is the game's spine and the client holds no second opinion about it.
    let cards: [ResultCardDTO]

    /// The caller's own two numbers, or `nil` while the answers are still on their way.
    ///
    /// Carried whole rather than unpacked into two `Double?`s: **`nil` means not applicable,
    /// never zero** (`docs/04` §4), and the counts beside a rate go `nil` with it — three
    /// optionals that have to agree are safer as one value that already does.
    let me: PersonalScoreDTO?

    /// The group's all-time lists, or `nil` while they are on their way — or if only that route
    /// failed. The answers are the screen; the standings are a section of it, and a section that
    /// did not load is a section that is not drawn rather than a screen that is not.
    let standings: StandingsDTO?

    /// The cards whose owner has arrived.
    let namedCards: Set<Int>
    /// The cards whose mark has arrived.
    let markedCards: Set<Int>
    let barredCards: Set<Int>

    init(
        cards: [ResultCardDTO],
        me: PersonalScoreDTO? = nil,
        standings: StandingsDTO? = nil,
        namedCards: Set<Int>? = nil,
        markedCards: Set<Int>? = nil,
        barredCards: Set<Int>? = nil
    ) {
        self.cards = cards
        self.me = me
        self.standings = standings
        // `nil` is "settled" — a round re-opened after its one run, and the state every golden
        // but one is a picture of.
        let all = Set(cards.map(\.cardNumber))
        self.namedCards = namedCards ?? all
        self.markedCards = markedCards ?? all
        self.barredCards = barredCards ?? all
    }
}

/// `docs/08` §7 — the answers, card by card.
///
/// Accent **ultramarine**, decided once here and handed down (`CLAUDE.md` §2.5). Amber does not
/// appear on this screen at all: nothing is sealed any more, not even the caller's own card,
/// which was the single exception the reveal made.
///
/// `docs/08` §7 asks for *"three sections in one scroll"*. This is the first — `E12-02` adds
/// **You**, `E12-03` the standings and `E12-05` the share entry point — and they are assembled
/// in `content` so each lands as one addition to one list rather than as another screen.
struct ResultsScreen: View {
    let state: ResultsViewState
    /// Any scroll gesture completes the name-resolve (`docs/09` §4). `nil` once there is nothing
    /// left to skip, which is also what a golden passes.
    var skipResolve: (() -> Void)?
    /// The share card and the thing that renders it, or `nil` when there is nothing to share.
    ///
    /// **`docs/10` §5: *"nothing about a round that is not `scored` is ever renderable — the
    /// share entry point does not exist in any other phase."*** This screen is the only place
    /// the entry point is built and this screen only exists under `.scored`, so the rule is a
    /// property of where the code lives rather than a condition somebody has to keep true.
    /// `ShareRendererTests` scans `Features/` to keep it that way.
    var share: ShareEntry?
    /// The 30-second preview (`Core/Audio/PreviewPlayer.swift`). `nil` in every golden, which
    /// renders `snapshotContent` directly and never this `body` — the same shared instance
    /// `RevealScreen` and Submit's search sheet already play through, so dropping into an answer
    /// card here stops whatever the caller had going in either of those.
    var player: PreviewPlayer? = nil

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.blindDropForcesReducedMotion) private var forceReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || forceReduceMotion }

    @State private var isSharing = false

    private let accent = PhaseAccent.revealed

    var body: some View {
        // **A completed round is not a form to fill in; it is a page to arrive at.** A short
        // night — a small circle, nobody's all-time standings loaded yet — otherwise leaves the
        // whole `ScrollView` top-anchored against a screen of white, which reads as unfinished
        // rather than as done. `GeometryReader` hands the content the viewport's own height so it
        // can ask to be at least that tall; content that is genuinely taller than the screen
        // still scrolls exactly as before; `minHeight` never trims it.
        GeometryReader { proxy in
            ScrollView {
                // The inset belongs to the scroll container's *content*, not to the container
                // (`docs/07` §4) — which is what puts the scroll indicator at the screen's edge
                // where a thumb expects it. `RoundScreen` therefore does not inset this phase;
                // the two together are the one application of `Layout.screenInset` on this path.
                //
                // **`.top`, not `.center`** (`E28-05`). A short night — a small circle, nobody's
                // all-time standings loaded yet — used to centre inside `minHeight`, which is
                // also what centred *while it was still arriving*: `content` grows as personal
                // stats and standings land under it, so the whole page visibly slid downward
                // into place instead of holding still with the answers at the top, where every
                // other screen in the app starts. `minHeight` still keeps a short page from
                // reading as an abandoned scrap of a screen; it just no longer moves anything to
                // do it.
                content
                    .padding(.horizontal, Layout.screenInset)
                    .frame(minHeight: proxy.size.height, alignment: .top)
            }
            // **"Any scroll gesture completes the entire sequence immediately"** (`docs/09` §4).
            //
            // A *simultaneous* gesture, so the scroll still happens — the point is not to trade
            // one for the other but to stop making somebody who is already moving down the list
            // wait for names to arrive above them. The minimum distance keeps a tap from
            // counting: a tap on a card is not somebody scrolling past it.
            .simultaneousGesture(
                DragGesture(minimumDistance: Layout.scrollSkipDistance)
                    .onChanged { _ in skipResolve?() }
            )
        }
        // A preview left playing after the results are dismissed is a sound with no visible way
        // to stop it — the same rule `RevealScreen` and `SearchSheet` already hold.
        .onDisappear { player?.stop() }
    }

    /// The screen without its scroll container.
    ///
    /// Rendered directly by the snapshots, and not as a convenience: `ImageRenderer` does not
    /// draw a `ScrollView`'s content at all, so a golden of `body` is a picture of an empty
    /// rectangle. It carries no horizontal inset either — `RoundScreen` places the screen inside
    /// one, and the renderer applies its own.
    var snapshotContent: some View {
        content
    }

    private var content: some View {
        // A plain `VStack`. A group runs to twelve members (`docs/02`), so this list is twelve
        // cards at the very most — laziness would save nothing, and `LazyVStack` mis-reports its
        // height to `ImageRenderer`, which clips the first line off every golden.
        VStack(alignment: .leading, spacing: Layout.blockGap) {
            answers
            if let me = state.me {
                PersonalStats(me: me)
            }
            if let standings = state.standings {
                StandingsView(standings: standings)
            }
            shareAction
        }
        .padding(.bottom, Layout.blockGap)
    }

    // MARK: - §7.1 Answers, card by card

    private var answers: some View {
        VStack(alignment: .leading, spacing: Layout.itemGap) {
            Text("results.title")
                .typeStyle(.displayL)
                .foregroundStyle(Palette.ink)
                .padding(.bottom, Space.xs)

            ForEach(state.cards) { card in
                // The links used to be their own row under the card (`TrackLinkButtons`); they
                // now sit inside it, beside the title — `FlightCard`'s `metadataRow` docs why.
                FlightCard(
                    number: card.cardNumber,
                    track: card.track,
                    accent: accent,
                    // No `chooseGuess`, so the card carries `.staticText` and not `.isButton`
                    // (`docs/12` §2). Nothing on a results card is a control.
                    assignment: .resolved(card.resolution),
                    // The answers are the one place a song is shown on this screen and could not
                    // be heard (`docs/08` §7.1) — Submit's search sheet and the reveal flight
                    // both already play through the same shared player. No preview URL means no
                    // control at all, same as everywhere else `preview(for:)` is built.
                    preview: preview(for: card.track),
                    resolve: ResolvePresentation(
                        hasName: state.namedCards.contains(card.cardNumber),
                        hasMark: state.markedCards.contains(card.cardNumber),
                        hasBar: state.barredCards.contains(card.cardNumber),
                        reducedMotion: reduceMotion
                    )
                )
            }
        }
    }

    /// `RevealScreen.preview(for:)`, verbatim: a track with no `previewURL`, or a screen with no
    /// player at all — every golden — gets no control (`docs/06` §7), and a track already
    /// playing draws its stop glyph off the shared player's own state rather than a local flag.
    private func preview(for track: TrackDTO) -> TrackRow.Preview? {
        guard track.previewURL != nil, let player else { return nil }
        return TrackRow.Preview(isPlaying: player.playing == track.trackKey) {
            player.toggle(track)
        }
    }
}

// MARK: - §7.4 Share

/// What the results need in order to offer a share (`docs/10` §4).
///
/// The two halves arrive together or not at all: a button with content and no renderer would be
/// a control that cannot do its one thing, and a renderer with no content has nothing to draw.
struct ShareEntry {
    let content: ShareCardContent
    /// Owned by the host rather than made here, so the files it has written survive a body
    /// re-evaluation and can all be deleted when the sheet closes (`docs/10` §5).
    let renderer: ShareRenderer
}

extension ResultsScreen {
    /// *"One `PrimaryButton`: **Share tonight**. This is the app's distribution mechanism and one
    /// of its best-looking surfaces. It is not an afterthought and it is not buried in a menu."*
    /// (`docs/08` §7.4)
    @ViewBuilder fileprivate var shareAction: some View {
        if let share {
            PrimaryButton("results.share", accent: .revealed) { isSharing = true }
                .sheet(isPresented: $isSharing) {
                    ShareSheet(content: share.content, renderer: share.renderer)
                }
        }
    }
}

// MARK: - §7.2 You

/// The caller's own two numbers (`docs/08` §7.2).
///
/// Two facts about the same night that are deliberately **not** the same kind of thing. Ear is a
/// score: you guessed, and some of them were right. Readability is a trait: people either
/// recognised you or they did not, and `docs/02` §4.5 makes low readability its own kind of win.
/// So the ear gets a number and the readability gets a number **and a position on a spectrum**,
/// with no rank, no arrow and no comparison to yesterday anywhere near either of them.
///
/// Internal rather than private only so `ResultsSnapshots` can point at the pair on its own —
/// the `null` ear and the absent readability each deserve a golden that is a picture of them
/// and not of a whole screen.
struct PersonalStats: View {
    let me: PersonalScoreDTO

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// `docs/12` §1 names this pair explicitly: *"Results §7.2: the Readability / Ear pair
    /// stacks"* above `.accessibility1`. Decided from the type size, never from a width check.
    private var isStacked: Bool { dynamicTypeSize >= .accessibility1 }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.itemGap) {
            Text("results.you.title")
                .typeStyle(.displayM)
                .foregroundStyle(Palette.ink)
            if isStacked {
                VStack(alignment: .leading, spacing: Layout.itemGap) {
                    readability
                    ear
                }
            } else {
                // Equal columns, aligned at the top. The two numbers are the same kind of thing
                // said about two different people — how well the room read you, and how well you
                // read the room — and side by side is the only arrangement that says so.
                HStack(alignment: .top, spacing: Layout.itemGap) {
                    readability
                    ear
                }
            }
            if let rate = me.readability {
                spectrum(rate)
            }
        }
    }

    private var readability: some View {
        StatTile(
            title: "results.readability.label",
            rate: me.readability,
            detail: detail(
                key: "results.readability.detail",
                absent: "results.readability.none",
                rate: me.readability,
                correct: me.readabilityCorrect,
                possible: me.readabilityPossible
            )
        )
    }

    private var ear: some View {
        StatTile(
            title: "results.ear.label",
            rate: me.ear,
            detail: detail(
                key: "results.ear.detail",
                absent: "results.ear.none",
                rate: me.ear,
                correct: me.earCorrect,
                possible: me.earPossible
            ),
            // The accent goes on the number that is about *the caller's own judgement*. Only
            // one of the two ever wears it — two accented numbers side by side is a scoreboard,
            // and `docs/16` rules the app out of having one.
            isAccented: true
        )
    }

    /// Where tonight put the caller on the scale, and the sentence for it.
    ///
    /// The scale runs from unreadable to easy to read with **no better end** (`docs/08` §7.2).
    /// The marker is a position, not a rank, which is why the panel names both ends and why
    /// nothing on it is sorted against anybody else.
    private func spectrum(_ rate: Double) -> some View {
        VStack(alignment: .leading, spacing: Layout.itemGap) {
            StatMeter(
                value: rate,
                band: ReadabilityBand(readability: rate),
                showsBand: false,
                showsEnds: true
            )
            Text(verbatim: Copy.band(ReadabilityBand(readability: rate)))
                .typeStyle(.bodyM)
                .foregroundStyle(Palette.ink)
        }
        .cardSurface(radius: Radius.panel)
    }

    /// The sentence under a number: the counts it came from, or the reason there are none.
    ///
    /// **`nil` is not zero** (`docs/04` §4) — the two possibilities are different situations and
    /// they get different sentences, which is why the choice is made here rather than by a
    /// formatter that would have to guess.
    private func detail(
        key: String,
        absent: LocalizedStringKey,
        rate: Double?,
        correct: Int?,
        possible: Int?
    ) -> StatTile.DetailText {
        guard rate != nil, let correct, let possible else { return .absent(absent) }
        return .counts(Copy.format(key, correct, possible))
    }
}
