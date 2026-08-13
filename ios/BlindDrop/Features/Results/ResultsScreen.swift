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

    /// The cards whose owner has arrived.
    let namedCards: Set<Int>
    /// The cards whose mark has arrived.
    let markedCards: Set<Int>

    init(cards: [ResultCardDTO], namedCards: Set<Int>? = nil, markedCards: Set<Int>? = nil) {
        self.cards = cards
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
