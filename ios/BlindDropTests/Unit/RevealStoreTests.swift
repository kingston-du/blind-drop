import Foundation
import Testing
@testable import BlindDrop

/// `E11-02`. Both directions of assigning a guess, the move, and what gets announced.
///
/// `docs/08` §6 supports two orders *"because 16-year-olds will try both"*, and several of these
/// are written in pairs for exactly that reason: the same assignment reached two ways must leave
/// the store in the same state, or one of the two orders is a second-class path that will drift.
///
/// This is where `E11-02`'s *"UI test covering both interaction directions"* actually lives —
/// see the note on the task. The interaction is a state machine with no view in it, and a state
/// machine is tested by driving it, not by tapping a simulator.
@MainActor
@Suite struct RevealStoreTests {

    // MARK: - Tap card → tap name

    @Test func tappingACardFocusesIt() {
        let store = RevealFixture.store()
        store.tapCard(1)
        #expect(store.focusedCard == 1)
        #expect(store.assignments.isEmpty)
    }

    /// A focus ring with no way out is a trap.
    @Test func tappingTheFocusedCardAgainReleasesIt() {
        let store = RevealFixture.store()
        store.tapCard(1)
        store.tapCard(1)
        #expect(store.focusedCard == nil)
    }

    @Test func cardThenNameAssigns() {
        let store = RevealFixture.store()
        store.tapCard(1)
        store.tapName("u0")
        #expect(store.assignments == [1: "u0"])
    }

    // MARK: - Tap name → tap card

    @Test func tappingANameSelectsIt() {
        let store = RevealFixture.store()
        store.tapName("u0")
        #expect(store.selectedMember == "u0")
        #expect(store.assignments.isEmpty)
    }

    @Test func tappingTheSelectedNameAgainDeselectsIt() {
        let store = RevealFixture.store()
        store.tapName("u0")
        store.tapName("u0")
        #expect(store.selectedMember == nil)
    }

    @Test func nameThenCardAssigns() {
        let store = RevealFixture.store()
        store.tapName("u0")
        store.tapCard(1)
        #expect(store.assignments == [1: "u0"])
    }

    /// The pair. Whichever order the two taps arrive in, the store must end up identical —
    /// otherwise one of `docs/08` §6's two directions is quietly the lesser one.
    @Test func bothDirectionsLeaveTheSameState() {
        let forward = RevealFixture.store()
        forward.tapCard(1)
        forward.tapName("u0")

        let reverse = RevealFixture.store()
        reverse.tapName("u0")
        reverse.tapCard(1)

        #expect(forward.assignments == reverse.assignments)
        #expect(forward.focusedCard == reverse.focusedCard)
        #expect(forward.selectedMember == reverse.selectedMember)
    }

    // MARK: - The move

    /// *"Tapping a consumed name **moves** it and clears its previous card — the move is the
    /// default behaviour rather than a blocked action."*
    @Test func assigningAConsumedNameMovesItAndClearsThePreviousCard() {
        let store = RevealFixture.store()
        store.tapCard(1)
        store.tapName("u0")
        store.tapCard(3)
        store.tapName("u0")

        #expect(store.assignments == [3: "u0"])
    }

    @Test func aConsumedChipReportsWhichCardItIsOn() {
        let store = RevealFixture.store()
        store.tapCard(2)
        store.tapName("u1")
        #expect(store.chipState(for: RevealFixture.members[1]) == .consumed(cardNumber: 2))
    }

    @Test func anUnusedChipIsUnusedAndASelectedOneIsSelected() {
        let store = RevealFixture.store()
        #expect(store.chipState(for: RevealFixture.members[0]) == .unused)
        store.tapName("u0")
        #expect(store.chipState(for: RevealFixture.members[0]) == .selected)
    }

    // MARK: - Clearing

    @Test func clearingRemovesTheGuessAndTakesTheFocus() {
        let store = RevealFixture.store()
        store.tapCard(1)
        store.tapName("u0")
        store.clearGuess(on: 1)

        #expect(store.assignments.isEmpty)
        #expect(store.focusedCard == 1)
    }

    @Test func clearingAnEmptyCardDoesNothing() {
        let store = RevealFixture.store()
        store.clearGuess(on: 1)
        #expect(store.focusedCard == nil)
    }

    // MARK: - Focus advance

    /// *"Assignment advances focus to the next unassigned card"* — the sheet fills top to bottom
    /// without a tap in between. No. 2 is the caller's own and is skipped.
    @Test func assigningAdvancesToTheNextUnassignedCard() {
        let store = RevealFixture.store(myCardNumber: 2)
        store.tapCard(1)
        store.tapName("u0")
        #expect(store.focusedCard == 3)
    }

    /// A user who starts in the middle and runs off the end is taken back to the gap near the
    /// top rather than dropped out of the flow.
    ///
    /// Only the first card is tapped: after that the focus advances on its own, so tapping three
    /// names in a row fills Nos. 2, 3 and 4 and then has to wrap to No. 1. That chain is the
    /// behaviour `docs/08` §6 is asking for — *"the sheet fills without a tap in between"* — so
    /// the test drives it rather than re-focusing by hand between each name.
    @Test func focusWrapsPastTheEndOfTheFlight() {
        let store = RevealFixture.store(cardCount: 4)
        store.tapCard(2)
        store.tapName("u0")
        store.tapName("u1")
        store.tapName("u2")

        #expect(store.assignments == [2: "u0", 3: "u1", 4: "u2"])
        #expect(store.focusedCard == 1)
    }

    @Test func focusIsNilWhenTheSheetIsFull() {
        let store = RevealFixture.store(cardCount: 2)
        store.tapCard(1)
        store.tapName("u0")
        store.tapName("u1")

        #expect(store.assignments == [1: "u0", 2: "u1"])
        #expect(store.focusedCard == nil)
    }

    // MARK: - What cannot happen

    @Test func theCallersOwnCardCannotBeAssigned() {
        let store = RevealFixture.store(myCardNumber: 1)
        store.tapCard(1)
        #expect(store.focusedCard == nil)

        store.tapName("u0")
        store.tapCard(1)
        #expect(store.assignments.isEmpty)
    }

    /// *"The client trusts `can_guess` from the server and never derives it locally."* A
    /// non-submitter can tap anything and nothing happens.
    @Test func aNonSubmitterCannotAssignAnything() {
        let store = RevealFixture.store(canGuess: false)
        store.tapCard(1)
        store.tapName("u0")
        store.tapCard(1)
        #expect(store.assignments.isEmpty)
        #expect(store.focusedCard == nil)
        #expect(store.selectedMember == nil)
    }

    /// A name that is not in the pool is not assignable. The pool is the round's submitters, and
    /// a guess against anybody else is one the server would reject (`docs/04` §4 rule 5).
    @Test func aNameOutsideThePoolCannotBeAssigned() {
        let store = RevealFixture.store()
        store.tapCard(1)
        store.tapName("nobody")
        #expect(store.assignments.isEmpty)
    }

    /// The caller is in the pool the server sends (`docs/04` §4 returns it whole so `S` stays
    /// derivable) and the client is what takes them out of it.
    @Test func theCallerIsNotInTheirOwnNamePool() {
        let store = RevealFixture.store()
        #expect(!store.pool.contains { $0.userID == RevealFixture.me.userID })
        #expect(store.pool.count == RevealFixture.members.count)
    }

    // MARK: - Names (E11-03)

    @Test func sharedFirstNamesUseTheNextWordInitialOnThePoolAndTheCard() {
        let samBrown = MemberDTO(userID: "sam-b", displayName: "Sam Brown")
        let samKwan = MemberDTO(userID: "sam-k", displayName: "Sam Kwan")
        let store = RevealStore(
            cards: [RevealFixture.card(number: 1)],
            pool: [samBrown, samKwan],
            myCardNumber: nil,
            canGuess: true,
            me: nil
        )
        store.adopt([GuessDTO(cardNumber: 1, guessedUserID: "sam-k")])

        #expect(store.displayNames == ["sam-b": "Sam B.", "sam-k": "Sam K."])
        #expect(store.viewState.assignment(for: 1) == .guessed(name: "Sam K."))
    }

    @Test func identicalNamesFallBackToAnOrdinalRatherThanExposingMoreData() {
        let first = MemberDTO(userID: "sam-1", displayName: "Sam")
        let second = MemberDTO(userID: "sam-2", displayName: "Sam")
        let labels = NameDisambiguator.labels(for: [first, second])

        #expect(labels["sam-1"] == "Sam")
        #expect(labels["sam-2"] == "Sam (2)")
    }

    @Test func collidingSurnameInitialsAlsoFallBackToOrdinals() {
        let first = MemberDTO(userID: "sam-brown", displayName: "Sam Brown")
        let second = MemberDTO(userID: "sam-baker", displayName: "Sam Baker")
        let labels = NameDisambiguator.labels(for: [first, second])

        #expect(labels["sam-brown"] == "Sam")
        #expect(labels["sam-baker"] == "Sam (2)")
    }

    @Test func consumedChipExposesAssignmentAsItsAccessibilityValue() {
        let chip = NameChip(
            member: MemberDTO(userID: "cal", displayName: "Cal"),
            state: .consumed(cardNumber: 3),
            action: {}
        )

        #expect(chip.accessibilityLabel == "Cal")
        #expect(chip.accessibilityValue == "Assigned to No. 3")
    }

    // MARK: - Announcements and progress

    /// `docs/12` §2: *"Assigning a guess posts an `.announcement`: 'No. 3 assigned to Cal.'"*
    /// The literal, because the format is the contract.
    @Test func assigningAnnouncesTheCardAndTheName() {
        let store = RevealFixture.store()
        store.tapCard(3)
        store.tapName("u2")
        #expect(store.announcement == "No. 3 assigned to Cal.")
    }

    @Test func anAnnouncementIsSaidOnce() {
        let store = RevealFixture.store()
        store.tapCard(1)
        store.tapName("u0")
        store.consumeAnnouncement()
        #expect(store.announcement == nil)
    }

    /// `assignable_count` is `S − 1` (`docs/04` §4): every card except the caller's own.
    @Test func progressCountsEveryCardButTheCallersOwn() {
        let store = RevealFixture.store(cardCount: 8, myCardNumber: 4)
        #expect(store.assignableCount == 7)
        store.tapCard(1)
        store.tapName("u0")
        #expect(store.progress == "1 of 7 assigned")
    }

    /// A caller who did not submit has no card of their own, so every card is assignable — the
    /// arithmetic must not subtract a card that is not there.
    @Test func aNonSubmitterHasNoOwnCardToSubtract() {
        let store = RevealFixture.store(cardCount: 8, myCardNumber: nil, canGuess: false)
        #expect(store.assignableCount == 8)
    }

    // MARK: - Why the caller cannot play (E11-05)

    /// The two reasons get **distinct copy**, because telling someone who joined this afternoon
    /// that they *"didn't drop tonight"* blames them for a round they were never in.
    @Test func theTwoBlockedReasonsSayDifferentThings() {
        let notSubmitter = RevealFixture.store(canGuess: false, reason: .notASubmitter)
        let joinedLate = RevealFixture.store(canGuess: false, reason: .joinedLate)

        #expect(notSubmitter.blockedReason == "You didn't drop tonight, so you're sitting this one out.")
        #expect(joinedLate.blockedReason == "You joined after the reveal. You're in from tomorrow.")
        #expect(notSubmitter.blockedReason != joinedLate.blockedReason)
    }

    /// A caller who can play is not told why they can.
    @Test func aSubmitterHasNoBlockedLine() {
        #expect(RevealFixture.store().blockedReason == nil)
    }

    /// `can_guess: false` with no reason is a server the client does not argue with: it still
    /// withholds the apparatus rather than falling open.
    @Test func blockedWithoutAReasonStillBlocks() {
        let store = RevealFixture.store(canGuess: false, reason: nil)
        #expect(store.blockedReason == "You can still look.")
        store.tapCard(1)
        store.tapName("u0")
        #expect(store.assignments.isEmpty)
    }

    /// *"Cards and previews remain fully usable — they can look."* The flight keeps every card;
    /// what goes is the chip, not the song.
    @Test func aBlockedCallerStillSeesEveryCard() {
        let store = RevealFixture.store(cardCount: 6, canGuess: false, reason: .notASubmitter)
        #expect(store.viewState.cards.count == 6)
        for number in 1...6 {
            #expect(store.viewState.assignment(for: number) == .unavailable)
        }
    }

    // MARK: - Adopting a saved sheet

    /// A re-fetch must not reset the interaction: the sheet is replaced, the focus is not.
    @Test func adoptingASavedSheetFillsTheChipsAndKeepsTheFocus() {
        let store = RevealFixture.store()
        store.tapCard(3)
        store.adopt([GuessDTO(cardNumber: 2, guessedUserID: "u1")])

        #expect(store.assignments == [2: "u1"])
        #expect(store.viewState.assignment(for: 2) == .guessed(name: "Ben"))
        #expect(store.focusedCard == 3)
    }
}

// MARK: - Fixtures

extension RevealFixture {

    /// Eleven names plus the caller — the largest pool the product allows (`docs/02`).
    static let members = ["Ana", "Ben", "Cal", "Dee", "Eli", "Fay", "Gus", "Hal", "Ivy", "Jo", "Kit"]
        .enumerated()
        .map { MemberDTO(userID: "u\($0.offset)", displayName: $0.element) }

    /// The caller. Present in the pool the server sends and removed by the store, which is the
    /// behaviour worth exercising rather than stubbing around.
    static let me = MemberDTO(userID: "me", displayName: "You")

    @MainActor
    static func store(
        cardCount: Int = 6,
        myCardNumber: Int? = nil,
        canGuess: Bool = true,
        reason: CannotGuessReason? = nil
    ) -> RevealStore {
        RevealStore(
            cards: (1...cardCount).map(card(number:)),
            pool: members + [me],
            myCardNumber: myCardNumber,
            canGuess: canGuess,
            cannotGuessReason: reason,
            me: me.userID
        )
    }
}
