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

        try? await Task.sleep(for: .milliseconds(850))
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

    @Test func disappearCancelsThePendingDebounceCleanly() async {
        let spy = GuessSaveSpy()
        let store = makeStore(spy: spy)
        store.tapCard(1)
        store.tapName("u0")

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
