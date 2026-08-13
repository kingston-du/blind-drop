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

    /// The cards whose owner has arrived.
    let namedCards: Set<Int>
    /// The cards whose mark has arrived.
    let markedCards: Set<Int>

    init(
        cards: [ResultCardDTO],
        me: PersonalScoreDTO? = nil,
        namedCards: Set<Int>? = nil,
        markedCards: Set<Int>? = nil
    ) {
        self.cards = cards
        self.me = me
        // `nil` is "settled" — a round re-opened after its one run, and the state every golden
        // but one is a picture of.
        let all = Set(cards.map(\.cardNumber))
        self.namedCards = namedCards ?? all
        self.markedCards = markedCards ?? all
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let accent = PhaseAccent.revealed

    var body: some View {
        ScrollView {
            content
        }
        // **"Any scroll gesture completes the entire sequence immediately"** (`docs/09` §4).
        //
        // A *simultaneous* gesture, so the scroll still happens — the point is not to trade one
        // for the other but to stop making somebody who is already moving down the list wait for
        // names to arrive above them. The minimum distance keeps a tap from counting: a tap on a
        // card is not somebody scrolling past it.
        .simultaneousGesture(
            DragGesture(minimumDistance: Layout.scrollSkipDistance)
                .onChanged { _ in skipResolve?() }
        )
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
        }
        .padding(.bottom, Layout.blockGap)
    }

    // MARK: - §7.1 Answers, card by card

    private var answers: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text("results.title")
                .typeStyle(.displayM)
                .foregroundStyle(Palette.ink)

            ForEach(state.cards) { card in
                FlightCard(
                    number: card.cardNumber,
                    track: card.track,
                    accent: accent,
                    // No `chooseGuess`, so the card carries `.staticText` and not `.isButton`
                    // (`docs/12` §2). Nothing on a results card is a control.
                    assignment: .resolved(card.resolution),
                    resolve: ResolvePresentation(
                        hasName: state.namedCards.contains(card.cardNumber),
                        hasMark: state.markedCards.contains(card.cardNumber),
                        reducedMotion: reduceMotion
                    )
                )
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
                VStack(alignment: .leading, spacing: Layout.blockGap) {
                    readability
                    ear
                }
            } else {
                HStack(alignment: .top, spacing: Layout.blockGap) {
                    readability
                    ear
                }
            }
        }
    }

    private var readability: some View {
        StatBlock(
            kind: .readability,
            rate: me.readability,
            correct: me.readabilityCorrect,
            possible: me.readabilityPossible
        )
    }

    private var ear: some View {
        StatBlock(kind: .ear, rate: me.ear, correct: me.earCorrect, possible: me.earPossible)
    }
}

/// One of the two numbers, and the sentence under it.
private struct StatBlock: View {

    /// Which number this is. An enum rather than four parameters, so the pairing of a label with
    /// its detail format and its absent line is made once and cannot be mismatched at a call
    /// site — *"You sat this one out."* under **Readability** would be a lie about a person who
    /// dropped a song and was simply not recognised.
    enum Kind {
        case readability
        case ear

        var title: LocalizedStringKey {
            switch self {
            case .readability: "results.readability.label"
            case .ear: "results.ear.label"
            }
        }

        /// *"6 of 7 read you"* / *"5 of 7 correct"*.
        var detailKey: String {
            switch self {
            case .readability: "results.readability.detail"
            case .ear: "results.ear.detail"
            }
        }

        /// The line that replaces the detail when the rate does not apply. The two are
        /// different sentences because they are different situations: one person did not drop,
        /// the other dropped and never opened the sheet.
        var absent: LocalizedStringKey {
            switch self {
            case .readability: "results.readability.none"
            case .ear: "results.ear.none"
            }
        }

        /// Only readability sits on a spectrum. An ear is a score and a score has no band.
        var hasMeter: Bool { self == .readability }
    }

    let kind: Kind
    let rate: Double?
    let correct: Int?
    let possible: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(kind.title)
                    .typeStyle(.label)
                    .foregroundStyle(Palette.inkDim)

                // **`nil` renders as an em dash, never as `0%`** (`docs/04` §4). `ScoringFormat`
                // is where that is decided; this view cannot get it wrong because it never sees
                // the optional as a number.
                Text(verbatim: ScoringFormat.percent(rate))
                    .typeStyle(.monoXL)
                    .foregroundStyle(Palette.ink)

                detail
            }
            // One stop for the label, the number and its sentence — they are one fact, and
            // three swipes to hear it is two too many (`docs/12` §2). The meter below stays its
            // own element, because it announces the band and that is a second fact.
            .accessibilityElement(children: .combine)

            if kind.hasMeter, let rate {
                StatMeter(value: rate, band: ReadabilityBand(readability: rate))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var detail: some View {
        if let correct, let possible, rate != nil {
            Text(verbatim: Copy.format(kind.detailKey, correct, possible))
                .typeStyle(.caption)
                .foregroundStyle(Palette.inkDim)
        } else {
            Text(kind.absent)
                .typeStyle(.caption)
                .foregroundStyle(Palette.inkDim)
                // The sentence is the whole point of the dash above it; it must arrive whole
                // rather than truncate into "You sat this one…".
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
