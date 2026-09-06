import Foundation

/// Which card the quick pass is on, and what happens when it is answered (`E41-01`).
///
/// A value, with no view and no store in it, because every rule worth getting right here is a
/// rule about ordering: where a re-entered run resumes, whether your own card appears, what the
/// last card advances to, and what a jump back from the recap does when it is answered. Those are
/// four sentences that a unit test can assert and a screenshot cannot.
///
/// **The run is every card you may name, in flight order** — not only the unfilled ones. Building
/// it from the unfilled set would make the run change shape under a finger: name No. 3, and No. 3
/// leaves the sequence you are standing in. The *cursor* starts at the first unfilled card
/// instead, which is the behaviour that wanted the filtered list, without the instability that
/// comes with it.
struct QuickPassSequence: Equatable, Sendable {
    /// The cards the caller may put a name on, ascending. Excludes their own card and — if they
    /// cannot guess at all — everything.
    let cardNumbers: [Int]
    /// The size of the whole flight, which is the denominator the screen shows. It is **not**
    /// `cardNumbers.count`: *"No. 4 of 8"* is the flight's own numbering, the thing two people in
    /// a circle say to each other, and it counts the card the caller dropped themselves.
    let flightSize: Int

    private(set) var index: Int
    /// Whether the cursor got here by jumping from the recap rather than by walking the run.
    ///
    /// A jump is a correction to one card, so answering it goes back to the recap instead of
    /// walking out the rest of the sequence from wherever the correction happened to be.
    private(set) var isExcursion: Bool

    /// - Parameters:
    ///   - cardNumbers: every card in the flight, ascending.
    ///   - isGuessable: whether the caller may name that card. `RevealStore.isGuessable(_:)`.
    ///   - isAssigned: whether it already carries a name, at the moment the run is built.
    init(
        cardNumbers: [Int],
        isGuessable: (Int) -> Bool,
        isAssigned: (Int) -> Bool
    ) {
        self.flightSize = cardNumbers.count
        let mine = cardNumbers.filter(isGuessable)
        self.cardNumbers = mine
        // Resume onto the first gap. A run with no gaps has nothing to walk and opens on the
        // recap — which is the right answer for somebody who filled the sheet on the flight and
        // then tapped into the quick pass to check it.
        self.index = mine.firstIndex(where: { !isAssigned($0) }) ?? mine.count
        self.isExcursion = false
    }

    /// The card on screen, or `nil` once the run is done.
    var current: Int? {
        cardNumbers.indices.contains(index) ? cardNumbers[index] : nil
    }

    var isComplete: Bool { current == nil }

    /// Nothing to name at all — a non-submitter, or a three-person round where the only other
    /// two cards are somehow not the caller's to name. The screen refuses to present on this.
    var isEmpty: Bool { cardNumbers.isEmpty }

    /// Whether there is a card behind this one to go back to.
    ///
    /// False on the first card of the run, false on the recap — where the rows are themselves the
    /// way back, and a better one, because they name the card you are going to — and false on an
    /// excursion, which is already a correction to one card and returns on its own.
    var canGoBack: Bool {
        !isExcursion && index > 0 && index < cardNumbers.count
    }

    /// One card back. Nothing is undone: a name already placed stays placed, and the chip that
    /// carries it comes back struck through, which is the sheet's own language for *this one is
    /// spent* — tap another name and it moves, exactly as it would on the flight.
    mutating func back() {
        guard canGoBack else { return }
        index -= 1
    }

    /// Answered, skipped, or moved past — all one motion as far as the cursor is concerned.
    ///
    /// A card reached by jumping from the recap returns to the recap rather than continuing, so
    /// a correction is a correction and not a second lap.
    mutating func advance() {
        if isExcursion {
            index = cardNumbers.count
            isExcursion = false
        } else {
            index += 1
        }
    }

    /// Go back to one card from the recap. A number not in the run is ignored — the recap lists
    /// the caller's own card too, and that row is not a control.
    mutating func jump(to cardNumber: Int) {
        guard let target = cardNumbers.firstIndex(of: cardNumber) else { return }
        index = target
        isExcursion = true
    }
}
