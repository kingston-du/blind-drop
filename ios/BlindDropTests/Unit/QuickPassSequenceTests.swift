import Foundation
import Testing
@testable import BlindDrop

/// `E41-01`. Where the quick pass starts, what it skips, and where a correction goes back to.
///
/// The whole reason `QuickPassSequence` is a value with no view in it: every rule that matters
/// here is a rule about ordering, and ordering is a thing a test can assert exactly. A screenshot
/// of card four proves nothing about what happens after card four.
@Suite struct QuickPassSequenceTests {

    /// Six-person circle, No. 3 is the caller's own, nothing named yet.
    private func sequence(
        flight: Int = 6,
        mine: Int? = 3,
        assigned: Set<Int> = []
    ) -> QuickPassSequence {
        QuickPassSequence(
            cardNumbers: Array(1...flight),
            isGuessable: { $0 != mine },
            isAssigned: assigned.contains
        )
    }

    // MARK: - What the run contains

    /// The caller's own card is not in the run and is not named — it is passed over, silently, so
    /// the numeral jumps. The epic argues that trade; this is where it is pinned down.
    @Test func theRunExcludesTheCallersOwnCard() {
        let run = sequence()
        #expect(run.cardNumbers == [1, 2, 4, 5, 6])
        #expect(run.current == 1)
    }

    /// *"04 / 08"* counts the flight, not the run. The denominator includes the card the caller
    /// dropped themselves, because it is the flight's numbering and not a to-do list.
    @Test func theDenominatorIsTheFlightNotTheRun() {
        let run = sequence(flight: 8, mine: 4)
        #expect(run.flightSize == 8)
        #expect(run.cardNumbers.count == 7)
    }

    /// A three-person round: two other cards, both nameable. The smallest legal flight
    /// (`docs/02` §3) must not come out absurd.
    @Test func aThreePersonRoundHasTwoCardsToName() {
        let run = sequence(flight: 3, mine: 2)
        #expect(run.cardNumbers == [1, 3])
        #expect(!run.isEmpty)
    }

    /// A twelve-person round, the other end of `docs/08` §6's stress case.
    @Test func aTwelvePersonRoundHasElevenCardsToName() {
        #expect(sequence(flight: 12, mine: 7).cardNumbers.count == 11)
    }

    /// A non-submitter has nothing to name. The screen leaves rather than draw an empty pool.
    @Test func aCallerWhoCannotGuessHasAnEmptyRun() {
        let run = QuickPassSequence(
            cardNumbers: [1, 2, 3],
            isGuessable: { _ in false },
            isAssigned: { _ in false }
        )
        #expect(run.isEmpty)
        #expect(run.isComplete)
    }

    // MARK: - Where it resumes

    /// Re-entered half-finished, it lands on the first gap rather than starting over — the
    /// behaviour that makes closing the cover mid-run free.
    @Test func itResumesOnTheFirstUnnamedCard() {
        #expect(sequence(assigned: [1, 2]).current == 4)
    }

    /// A gap in the middle is still the first gap. Somebody who named cards out of order on the
    /// flight and then opened the quick pass is not walked past the hole they left.
    @Test func itResumesOnAGapInTheMiddle() {
        #expect(sequence(assigned: [1, 4, 5]).current == 2)
    }

    /// **The run keeps every nameable card, not only the unnamed ones.** Building it from the
    /// gaps would make the sequence change shape under a finger: name No. 2, and No. 2 leaves the
    /// list you are standing in. The cursor carries the resume behaviour instead.
    @Test func theRunKeepsNamedCardsSoItCannotReshapeMidRun() {
        let run = sequence(assigned: [1, 2])
        #expect(run.cardNumbers == [1, 2, 4, 5, 6])
    }

    /// A full sheet has nothing to walk, so the run opens finished — which is what somebody who
    /// filled the flight and then tapped in to check it should get.
    @Test func aFullSheetOpensComplete() {
        #expect(sequence(assigned: [1, 2, 4, 5, 6]).isComplete)
    }

    // MARK: - Advancing

    @Test func advancingWalksTheRunInFlightOrder() {
        var run = sequence()
        run.advance()
        #expect(run.current == 2)
        run.advance()
        // Straight past No. 3, which is the caller's.
        #expect(run.current == 4)
    }

    @Test func advancingOffTheLastCardCompletesTheRun() {
        var run = sequence(assigned: [1, 2, 4, 5])
        #expect(run.current == 6)
        run.advance()
        #expect(run.isComplete)
        #expect(run.current == nil)
    }

    // MARK: - Going back (`E41-03`)

    /// Nothing behind the first card of the run.
    @Test func thereIsNoBackFromTheFirstCard() {
        #expect(!sequence().canGoBack)
    }

    @Test func backStepsOneCardInFlightOrder() {
        var run = sequence()
        run.advance()
        run.advance()
        #expect(run.current == 4)
        run.back()
        // Straight back past No. 3, which is the caller's — the run does not contain it in
        // either direction.
        #expect(run.current == 2)
    }

    /// Going back does not undo the name. The store keeps it, the chip comes back struck through,
    /// and tapping another name moves it — the flight's own behaviour, reached the other way.
    @Test func backDoesNotClearWhatIsBehindIt() {
        var run = sequence(assigned: [1])
        #expect(run.current == 2)
        run.back()
        #expect(run.current == 1)
        #expect(run.cardNumbers == [1, 2, 4, 5, 6])
    }

    /// **No back from the recap.** Its rows are the way back and a better one: they name the card
    /// you are going to instead of counting cards backwards to reach it.
    @Test func thereIsNoBackFromTheRecap() {
        var run = sequence(assigned: [1, 2, 4, 5, 6])
        #expect(run.isComplete)
        #expect(!run.canGoBack)
        run.back()
        #expect(run.isComplete)
    }

    /// An excursion is already a correction to one card and returns on its own.
    @Test func thereIsNoBackFromAnExcursion() {
        var run = sequence(assigned: [1, 2, 4, 5, 6])
        run.jump(to: 4)
        #expect(!run.canGoBack)
        run.back()
        #expect(run.current == 4)
    }

    /// Back then forward is a round trip, not a lost card.
    @Test func backAndForwardReturnsToWhereItWas() {
        var run = sequence()
        run.advance()
        run.advance()
        let before = run.current
        run.back()
        run.advance()
        #expect(run.current == before)
    }

    // MARK: - Corrections from the recap

    /// A jump is a correction to one card, so answering it returns to the recap instead of
    /// walking out the rest of the sequence from wherever the correction happened to sit.
    @Test func answeringAJumpReturnsToTheRecapRatherThanContinuing() {
        var run = sequence(assigned: [1, 2, 4, 5, 6])
        #expect(run.isComplete)
        run.jump(to: 2)
        #expect(run.current == 2)
        run.advance()
        #expect(run.isComplete)
    }

    /// The recap lists the caller's own card too, and that row is not a control.
    @Test func jumpingToACardNotInTheRunDoesNothing() {
        var run = sequence(assigned: [1, 2, 4, 5, 6])
        run.jump(to: 3)
        #expect(run.isComplete)
    }

    /// A jump taken mid-run — reachable once the recap can be reached and left again — still
    /// behaves as an excursion rather than rewinding the walk.
    @Test func aJumpMidRunStillReturnsToTheRecap() {
        var run = sequence()
        run.advance()
        #expect(run.current == 2)
        run.jump(to: 1)
        run.advance()
        #expect(run.isComplete)
    }
}

/// `E41-02`. When the cover opens itself.
///
/// Three clauses, and both ways of getting them wrong are silent: once too often and the quick
/// pass is an obstruction somebody has to dismiss on every foreground; once too rarely and the
/// feature quietly does not exist for anyone who does not go looking. Neither shows up in a
/// screenshot.
@Suite struct QuickPassPresentationTests {

    /// The ordinary case: guess window open, nothing named, unseal done, no link, never offered.
    private func conditions(
        canGuess: Bool = true,
        hasUnnamedCards: Bool = true,
        unsealHasRun: Bool = true,
        arrivedFromLink: Bool = false,
        alreadyOfferedThisRound: Bool = false
    ) -> QuickPassPresentation.Conditions {
        .init(
            canGuess: canGuess,
            hasUnnamedCards: hasUnnamedCards,
            unsealHasRun: unsealHasRun,
            arrivedFromLink: arrivedFromLink,
            alreadyOfferedThisRound: alreadyOfferedThisRound
        )
    }

    @Test func itOpensOnTheFirstArrivalOfARound() {
        #expect(QuickPassPresentation.shouldPresent(conditions()))
    }

    // MARK: - The refusals

    /// A non-submitter is shown the flight with the apparatus disabled but whole (`docs/08` §6).
    /// The quick pass would be an empty pool with nothing to do in it.
    @Test func itNeverOpensForSomebodyWhoCannotGuess() {
        #expect(!QuickPassPresentation.shouldPresent(conditions(canGuess: false)))
    }

    @Test func itNeverOpensOnAFullSheet() {
        #expect(!QuickPassPresentation.shouldPresent(conditions(hasUnnamedCards: false)))
    }

    /// **The unseal gets its night.** It carries half the app's motion budget and plays once per
    /// round; a modal over it spends the signature moment on nothing.
    @Test func itWaitsForTheUnseal() {
        #expect(!QuickPassPresentation.shouldPresent(conditions(unsealHasRun: false)))
    }

    /// And the refusals outrank an explicit intent. A push tap on a round somebody cannot guess
    /// in still lands on the flight.
    @Test func aLinkDoesNotOverrideTheRefusals() {
        #expect(!QuickPassPresentation.shouldPresent(
            conditions(canGuess: false, arrivedFromLink: true)
        ))
        #expect(!QuickPassPresentation.shouldPresent(
            conditions(unsealHasRun: false, arrivedFromLink: true)
        ))
    }

    // MARK: - Once, unless asked

    /// Dismissed to browse the flight is a thing the person said, and it is remembered.
    @Test func itDoesNotOpenTwiceOnItsOwn() {
        #expect(!QuickPassPresentation.shouldPresent(conditions(alreadyOfferedThisRound: true)))
    }

    /// A notification tap is a question just re-asked. Having dismissed the cover earlier is not
    /// an answer to it.
    @Test func aLinkReopensItAfterADismissal() {
        #expect(QuickPassPresentation.shouldPresent(
            conditions(arrivedFromLink: true, alreadyOfferedThisRound: true)
        ))
    }
}
