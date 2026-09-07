import Foundation
import Testing
@testable import BlindDrop

@MainActor
@Suite(.serialized) struct GuessSaveTests {

    @Test func rapidEditsProduceOneWholeSheetRequest() async {
        let spy = GuessSaveSpy()
        let store = makeStore(spy: spy)

        store.tapCard(1)
        store.tapName("u0")
        store.tapName("u1")
        store.tapName("u2")

        // The debounce is 600ms, but a fixed 850ms sleep is not a reliable assertion when the
        // full Swift Testing target is running hundreds of tests in parallel: the main actor can
        // be ready to perform the save without having been scheduled yet. Wait for the observed
        // effect, with a real upper bound, so this still fails loudly if the debounce stalls.
        let deadline = ContinuousClock.now + .seconds(3)
        while await spy.requests.isEmpty, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        let requests = await spy.requests

        #expect(requests.count == 1)
        #expect(requests.first == [
            GuessAssignment(cardNumber: 1, guessedUserID: "u0"),
            GuessAssignment(cardNumber: 2, guessedUserID: "u1"),
            GuessAssignment(cardNumber: 3, guessedUserID: "u2"),
        ])
        #expect(!store.hasPendingSave)
    }

    @Test func clearingSendsAnExplicitNullRatherThanOmittingTheCard() async {
        let spy = GuessSaveSpy()
        let store = makeStore(spy: spy)
        store.tapCard(1)
        store.tapName("u0")
        store.clearGuess(on: 1)

        try? await Task.sleep(for: .milliseconds(850))
        let request = await spy.requests.last

        #expect(request?.first == GuessAssignment(cardNumber: 1, guessedUserID: nil))
        #expect(request?.count == 3)
    }

    /// **A guess made just before leaving is sent, not dropped.**
    ///
    /// This test used to assert the opposite — that `cancelPendingSave()` left `spy.requests`
    /// empty — and that assertion was pinning a bug rather than a guarantee. Every edit reaches
    /// the server only through the 600ms debounce, so cancelling it on `.onDisappear` meant a
    /// name placed within 600ms of leaving the reveal never left the phone. Nothing looked wrong
    /// at the time: the assignment is local state and stayed on screen, and the next refetch's
    /// `adopt(_:)` quietly replaced it with the server's copy, which had never been told. Tapping
    /// a chip and immediately opening the quick pass was enough to lose one.
    ///
    /// What "cleanly" is actually worth asserting about is below: the flush is a single request
    /// carrying the edit, and the store is left with nothing outstanding.
    @Test func disappearFlushesThePendingDebounceRatherThanDroppingIt() async {
        let spy = GuessSaveSpy()
        let store = makeStore(spy: spy)
        store.tapCard(1)
        store.tapName("u0")

        store.cancelPendingSave()
        try? await Task.sleep(for: .milliseconds(850))

        #expect(await spy.requests.count == 1)
        #expect(await spy.requests.last?.first(where: { $0.cardNumber == 1 })?.guessedUserID == "u0")
        #expect(!store.hasPendingSave)
        #expect(!store.isSaving)
    }

    /// The other half: with nothing pending there is nothing to flush, and leaving stays silent.
    @Test func disappearWithNothingPendingSendsNothing() async {
        let spy = GuessSaveSpy()
        let store = makeStore(spy: spy)

        store.cancelPendingSave()
        try? await Task.sleep(for: .milliseconds(850))

        #expect(await spy.requests.isEmpty)
        #expect(!store.hasPendingSave)
        #expect(!store.isSaving)
    }

    @Test func lockingFlushesImmediatelyAndChangeRestoresEditing() async {
        let spy = GuessSaveSpy()
        let store = makeStore(spy: spy)
        store.tapCard(1)
        store.tapName("u0")

        store.lockIn()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(store.isLocked)
        #expect(!store.isGuessable(2))
        #expect(await spy.requests.count == 1)

        store.changeAGuess()
        #expect(!store.isLocked)
        #expect(store.isGuessable(2))
    }

    @Test func failureStaysInlineAndLeavesTheSheetEditable() async {
        let spy = GuessSaveSpy(error: .offline)
        let store = makeStore(spy: spy)
        store.tapCard(1)
        store.tapName("u0")
        store.lockIn()

        try? await Task.sleep(for: .milliseconds(50))

        #expect(store.saveErrorKey == "error.offline")
        #expect(!store.isLocked)
        #expect(store.assignments == [1: "u0"])
        #expect(store.isGuessable(2))
    }

    /// **Change a guess must not arm a card that already carries a name** (owner, approved).
    ///
    /// It used to focus the first *assignable* card, which on a full sheet is No. 1 — already
    /// named, and silently armed. Reaching for a name next, which is the obvious move after
    /// tapping the affordance, overwrote No. 1 instead of the card the person came to correct.
    @Test func changeAGuessArmsTheFirstGapAndNothingElse() async {
        let spy = GuessSaveSpy()
        let store = makeStore(spy: spy)

        // No. 1 named, No. 2 left open, then locked in with a gap.
        store.tapCard(1)
        store.tapName("u0")
        store.lockIn()

        store.changeAGuess()
        #expect(store.focusedCard == 2, "the first card without a name is the only safe one to arm")
    }

    /// And with no gap left there is nothing safe to arm, so nothing is: the header falls back to
    /// the count and the person taps the card they actually mean.
    @Test func changeAGuessOnAFullSheetArmsNothing() async {
        let spy = GuessSaveSpy()
        let store = makeStore(spy: spy)

        store.tapCard(1)
        store.tapName("u0")
        store.tapName("u1")
        store.tapName("u2")
        store.lockIn()

        store.changeAGuess()
        #expect(store.focusedCard == nil,
                "no card may be armed when every one of them would be overwritten by the next tap")
    }

    private func makeStore(spy: GuessSaveSpy) -> RevealStore {
        RevealStore(
            cards: (1...3).map(RevealFixture.card(number:)),
            pool: Array(RevealFixture.members.prefix(3)),
            myCardNumber: nil,
            canGuess: true,
            me: nil,
            saveGuesses: { assignments in try await spy.save(assignments) }
        )
    }
}

private actor GuessSaveSpy {
    private(set) var requests: [[GuessAssignment]] = []
    private let error: APIError?

    init(error: APIError? = nil) {
        self.error = error
    }

    func save(_ assignments: [GuessAssignment]) throws -> GuessSheetDTO {
        requests.append(assignments)
        if let error { throw error }
        return GuessSheetDTO(
            assignments: assignments.compactMap { assignment in
                assignment.guessedUserID.map {
                    GuessDTO(cardNumber: assignment.cardNumber, guessedUserID: $0)
                }
            },
            assignedCount: assignments.compactMap(\.guessedUserID).count,
            assignableCount: assignments.count
        )
    }
}
