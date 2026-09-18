import Foundation
import Testing
@testable import BlindDrop

/// Marking, on the client (`E46-02`, `docs/19-REACTIONS.md`).
///
/// The two halves `docs/19` §3 makes into one rule — *a reaction behaves exactly like a guess* —
/// land differently here than on the server. The server's job is that no count exists before
/// `scored`; the client's is that a tap is never lost and never lies. So this suite is mostly
/// about the second: optimistic state that reverts when the write fails, ordering when somebody
/// changes their mind twice, and a refetch that cannot undo a tap it arrived in the middle of.
@MainActor
@Suite(.serialized) struct ReactionTests {

    // MARK: - Placing

    @Test func markingACardSendsItAndKeepsIt() async {
        let spy = ReactionSpy()
        let store = makeStore(spy: spy)

        store.mark(.loved, on: 2)

        #expect(store.reaction(on: 2) == .loved, "the mark is on screen before the write returns")
        await settle(spy)
        #expect(await spy.requests == [Request(cardNumber: 2, kind: .loved)])
    }

    @Test func markingIsOfferedOnACardTheCallerCannotGuess() async {
        // `docs/19` §4: `docs/02` §3.3 restricts *guessing* because guessing is scored, and a
        // mark is scored by nothing. A non-submitter may mark, and the store must not be
        // stricter than the route — which has no submitter check either.
        let spy = ReactionSpy()
        let store = RevealStore(
            cards: (1...3).map(RevealFixture.card(number:)),
            pool: Array(RevealFixture.members.prefix(3)),
            myCardNumber: nil,
            canGuess: false,
            cannotGuessReason: .notASubmitter,
            me: nil,
            saveReaction: { card, kind in try await spy.save(card, kind) }
        )

        store.mark(.interesting, on: 1)

        #expect(store.reaction(on: 1) == .interesting)
        #expect(!store.isGuessable(1), "and they still cannot guess it")
        await settle(spy)
        #expect(await spy.requests.count == 1)
    }

    @Test func aCardOutsideTheRoundIsIgnored() async {
        let spy = ReactionSpy()
        let store = makeStore(spy: spy)

        store.mark(.loved, on: 0)
        store.mark(.loved, on: 99)

        #expect(store.reactions.isEmpty)
        #expect(await spy.requests.isEmpty, "nothing was sent for a card that is not in the round")
    }

    @Test func markingTheSameKindTwiceSendsOneRequest() async {
        // The bar passes the kind it was tapped with, and a second tap on an already-chosen mark
        // arrives as `nil` (the clear below). A repeat of the same kind is therefore a duplicate
        // event — a double-tap, a replayed gesture — and must not become a second write.
        let spy = ReactionSpy()
        let store = makeStore(spy: spy)

        store.mark(.loved, on: 2)
        store.mark(.loved, on: 2)

        await settle(spy)
        #expect(await spy.requests.count == 1)
    }

    // MARK: - Changing and clearing

    @Test func changingAMarkReplacesIt() async {
        let spy = ReactionSpy()
        let store = makeStore(spy: spy)

        store.mark(.loved, on: 2)
        store.mark(.notForMe, on: 2)

        #expect(store.reaction(on: 2) == .notForMe)
        await settle(spy, until: 2)
        #expect(await spy.requests == [
            Request(cardNumber: 2, kind: .loved),
            Request(cardNumber: 2, kind: .notForMe),
        ], "both went out, in the order they were tapped")
    }

    @Test func clearingSendsAnExplicitNil() async {
        let spy = ReactionSpy()
        let store = makeStore(spy: spy)

        store.mark(.loved, on: 2)
        await settle(spy)
        store.mark(nil, on: 2)

        #expect(store.reaction(on: 2) == nil)
        await settle(spy, until: 2)
        #expect(await spy.requests.last == Request(cardNumber: 2, kind: nil))
    }

    @Test func clearingACardWithNoMarkSendsNothing() async {
        let spy = ReactionSpy()
        let store = makeStore(spy: spy)

        store.mark(nil, on: 2)

        #expect(await spy.requests.isEmpty)
    }

    @Test func twoCardsAreIndependent() async {
        let spy = ReactionSpy()
        let store = makeStore(spy: spy)

        store.mark(.loved, on: 1)
        store.mark(.interesting, on: 3)

        #expect(store.reaction(on: 1) == .loved)
        #expect(store.reaction(on: 3) == .interesting)
        #expect(store.reaction(on: 2) == nil)
        await settle(spy, until: 2)
    }

    // MARK: - When the write fails

    @Test func aFailedWriteRevertsTheMarkAndSaysSo() async {
        // Unlike the guess sheet, which keeps a failed assignment and retries on the next edit,
        // there is no later write to carry a mark — the next tap sends only its own card. A mark
        // left lit would be a claim nobody recorded.
        let spy = ReactionSpy(error: .offline)
        let store = makeStore(spy: spy)

        store.mark(.loved, on: 2)
        #expect(store.reaction(on: 2) == .loved, "optimistic first")

        await settle(spy)
        await waitUntil { store.reaction(on: 2) == nil }
        #expect(store.reaction(on: 2) == nil, "and reverted when the write failed")
        #expect(store.reactionErrorKey == APIError.offline.copyKey)
    }

    @Test func aFailedChangeRevertsToWhatTheServerConfirmed() async {
        let spy = ReactionSpy()
        let store = makeStore(spy: spy)

        store.mark(.loved, on: 2)
        await settle(spy)
        await waitUntil { store.reactionErrorKey == nil && store.reaction(on: 2) == .loved }

        await spy.startFailing(.offline)
        store.mark(.notForMe, on: 2)
        await waitUntil { store.reaction(on: 2) == .loved }

        #expect(store.reaction(on: 2) == .loved, "back to the mark that actually landed")
    }

    @Test func aFailedMarkDoesNotTouchTheGuessSheetsOwnError() async {
        let spy = ReactionSpy(error: .offline)
        let store = makeStore(spy: spy)

        store.mark(.loved, on: 2)
        await waitUntil { store.reactionErrorKey != nil }

        #expect(store.saveErrorKey == nil, "two requests, two errors, one each")
    }

    // MARK: - Adopting the server's copy

    @Test func adoptingTheServersMarksFillsThem() {
        let store = makeStore(spy: ReactionSpy())

        store.adopt(reactions: [
            ReactionDTO(cardNumber: 1, kind: .loved),
            ReactionDTO(cardNumber: 3, kind: .notForMe),
        ])

        #expect(store.reaction(on: 1) == .loved)
        #expect(store.reaction(on: 3) == .notForMe)
        #expect(store.reaction(on: 2) == nil)
    }

    @Test func aRefetchBetweenTwoTapsOnOneCardDoesNotUndoTheSecond() async {
        // The race a reviewer found, and the reason writes carry a generation. Two taps on one
        // card make two tasks, the second chained behind the first. The first's completion used
        // to release the card unconditionally — but by then the entry holds the *second* task,
        // which has not sent its request yet. The card looked idle while a write was in flight,
        // and an `adopt` landing in that window put the server's older mark back permanently:
        // the second write updates `confirmedReactions` and never touches `reactions` again.
        let spy = ReactionSpy()
        let store = makeStore(spy: spy)

        store.mark(.loved, on: 2)
        await settle(spy)                 // the first write is out and has landed
        await spy.hold()                  // the second will block inside the saver
        store.mark(.notForMe, on: 2)
        await settle(spy, until: 2)       // it is in flight, and the card must not look idle

        store.adopt(reactions: [ReactionDTO(cardNumber: 2, kind: .loved)])
        #expect(store.reaction(on: 2) == .notForMe, "the refetch undid a tap that was in flight")

        await spy.release()
        await waitUntil { store.reaction(on: 2) == .notForMe }
        #expect(store.reaction(on: 2) == .notForMe)
    }

    @Test func aRefetchAdoptsEveryCardThatIsNotItselfMidWrite() async {
        // The guard used to be all-or-nothing: one in-flight tap on card 2 skipped the adopt for
        // every card. A write on one card says nothing about another.
        let spy = ReactionSpy(holds: true)
        let store = makeStore(spy: spy)

        store.mark(.loved, on: 2)
        store.adopt(reactions: [
            ReactionDTO(cardNumber: 2, kind: .notForMe),
            ReactionDTO(cardNumber: 3, kind: .interesting),
        ])

        #expect(store.reaction(on: 2) == .loved, "the in-flight card keeps the tap")
        #expect(store.reaction(on: 3) == .interesting, "every other card takes the server's copy")
        await spy.release()
        await settle(spy)
    }

    @Test func aRefetchMidTapDoesNotUndoTheTap() async {
        // The read-side half of the hazard `cancelPendingSave()` records for the sheet: a refetch
        // landing between a tap and its response carries the server's older set, and adopting it
        // would flip the mark the person is looking at back to what it was a moment ago.
        let spy = ReactionSpy(holds: true)
        let store = makeStore(spy: spy)

        store.mark(.loved, on: 2)
        store.adopt(reactions: [])

        #expect(store.reaction(on: 2) == .loved, "the tap wins over an in-flight refetch")
        await spy.release()
        await settle(spy)
    }

    // MARK: - What VoiceOver hears

    @Test func placingAndClearingAreBothAnnounced() {
        // `docs/12` §2: nothing changes state in silence. A mark is placed by a tap on a control
        // that does not move, so without this there is no announcement at all.
        let store = makeStore(spy: ReactionSpy())

        store.mark(.loved, on: 2)
        let placed = store.announcement
        store.consumeAnnouncement()
        store.mark(nil, on: 2)

        #expect(placed?.contains("Loved it") == true)
        #expect(placed?.contains("2") == true)
        #expect(store.announcement != placed)
        #expect(store.announcement?.isEmpty == false)
    }

    @Test func everyKindResolvesItsCopyAndBothSymbols() {
        // The set is closed (`docs/19` §5) and each kind owns its word and its two glyphs. A
        // kind added without them would render as the key itself, or as a blank square.
        for kind in ReactionKind.allCases {
            #expect(!Copy.string(kind.copyKey).isEmpty)
            #expect(Copy.string(kind.copyKey) != kind.copyKey, "\(kind) has no string in the deck")
            #expect(!kind.outlineSymbol.isEmpty)
            #expect(kind.filledSymbol != kind.outlineSymbol, "\(kind) carries no shape change")
        }
        #expect(ReactionKind.allCases.count == 3, "three kinds, and adding a fourth is the owner's")
    }

    @Test func theWireNamesAreTheContractsNames() {
        #expect(ReactionKind.loved.rawValue == "loved")
        #expect(ReactionKind.interesting.rawValue == "interesting")
        #expect(ReactionKind.notForMe.rawValue == "not_for_me")
    }

    // MARK: - Helpers

    private func makeStore(spy: ReactionSpy) -> RevealStore {
        RevealStore(
            cards: (1...3).map(RevealFixture.card(number:)),
            pool: Array(RevealFixture.members.prefix(3)),
            myCardNumber: nil,
            canGuess: true,
            me: nil,
            saveReaction: { card, kind in try await spy.save(card, kind) }
        )
    }

    /// Waits for the spy to have seen `until` requests, with a real upper bound — the same
    /// pattern `GuessSaveTests` uses, and for the same reason: the main actor can be ready to
    /// perform the write without having been scheduled yet.
    private func settle(_ spy: ReactionSpy, until count: Int = 1) async {
        let deadline = ContinuousClock.now + .seconds(3)
        while await spy.requests.count < count, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}

private struct Request: Equatable {
    let cardNumber: Int
    let kind: ReactionKind?
}

private actor ReactionSpy {
    private(set) var requests: [Request] = []
    private var error: APIError?
    private var held: Bool
    private var marks: [Int: ReactionKind] = [:]

    init(error: APIError? = nil, holds: Bool = false) {
        self.error = error
        self.held = holds
    }

    func startFailing(_ error: APIError) {
        self.error = error
    }

    func release() {
        held = false
    }

    /// Makes the *next* write block until `release()`. Distinct from `init(holds:)`, which holds
    /// from the first write onward.
    func hold() {
        held = true
    }

    func save(_ cardNumber: Int, _ kind: ReactionKind?) async throws -> MyReactionsDTO {
        requests.append(Request(cardNumber: cardNumber, kind: kind))
        while held {
            try? await Task.sleep(for: .milliseconds(10))
        }
        if let error { throw error }
        if let kind {
            marks[cardNumber] = kind
        } else {
            marks.removeValue(forKey: cardNumber)
        }
        return MyReactionsDTO(
            myReactions: marks
                .map { ReactionDTO(cardNumber: $0.key, kind: $0.value) }
                .sorted { $0.cardNumber < $1.cardNumber }
        )
    }
}
