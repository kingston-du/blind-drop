import Foundation
import Testing
@testable import BlindDrop

/// `E12-01`. What the results screen decides that is not pixels: what a card says about the
/// room, what it says about the caller, and the cadence the answers arrive on.
///
/// Rules rather than layout, so they are asserted on the values — a rule checked only by a
/// golden PNG is a rule that fails as *"3.1% of pixels differ"*.
@MainActor
@Suite struct ResultsTests {

    // MARK: - The card's own numbers

    /// A card carries the server's answer through untouched: whose it was, the count, and the
    /// caller's guess. Decoded from `ios/Fixtures/payloads/results.json`, which is `docs/04`
    /// verbatim, rather than hand-built — the mapping is only worth testing against the shape
    /// the server actually sends.
    @Test func aCardResolvesToItsOwnerAndTheRoomsCount() throws {
        let results = try ResultsFixture.results()
        let first = try #require(results.cards.first)

        #expect(first.resolution.owner == "Dee")
        #expect(first.resolution.correctCount == 4)
        #expect(first.resolution.eligibleCount == 7)
        #expect(first.resolution.myGuess == CardResolution.MyGuess(name: "Dee", isCorrect: true))
    }

    /// **A card the caller did not guess has no mark**, and that is one fact rather than three.
    ///
    /// No. 4 is Ana's own song in the §4.4 fixture, and `my_guess` is `null` — the same `null` a
    /// blank card and a round the caller could not play in both send. Rendering a mark for any
    /// of them would be the screen inventing a guess that was never made.
    @Test func aCardWithNoGuessCarriesNoMark() throws {
        let results = try ResultsFixture.results()
        let mine = try #require(results.cards.first { $0.cardNumber == 4 })

        #expect(mine.myGuess == nil)
        #expect(mine.resolution.myGuess == nil)
    }

    /// A wrong guess is carried as the wrong name, not erased. No. 5 was Gus's; Ana said Cal.
    @Test func aWrongGuessKeepsTheNameTheCallerActuallySaid() throws {
        let results = try ResultsFixture.results()
        let card = try #require(results.cards.first { $0.cardNumber == 5 })

        #expect(card.resolution.myGuess == CardResolution.MyGuess(name: "Cal", isCorrect: false))
        #expect(card.resolution.owner == "Gus")
    }

    // MARK: - "%lld of %lld got it", and the two nights that get a sentence

    @Test func theCountReadsAsAFraction() {
        #expect(Copy.resultCount(correct: 4, eligible: 7) == "4 of 7 got it")
    }

    /// *"Nobody got it"* and *"Everybody got it"* are copy, not arithmetic (`docs/11`). Both
    /// ends of the range are true as fractions and both read like a spreadsheet.
    @Test func theEndsOfTheRangeGetTheirOwnSentence() {
        #expect(Copy.resultCount(correct: 0, eligible: 7) == "Nobody got it")
        #expect(Copy.resultCount(correct: 7, eligible: 7) == "Everybody got it")
    }

    // MARK: - VoiceOver (docs/12 §2)

    /// A results card announces the number, the title, the artist, the owner and the count —
    /// and then, only if the caller guessed, what they said.
    @Test func aResultsCardAnnouncesTheAnswerAndThenTheCallersOwnGuess() {
        let label = Copy.A11y.card(
            number: 5, title: "Kill Bill", artist: "SZA",
            guess: .resolved(CardResolution(
                owner: "Gus", correctCount: 1, eligibleCount: 7,
                myGuess: CardResolution.MyGuess(name: "Cal", isCorrect: false)
            ))
        )

        #expect(label == "No. 5. Kill Bill by SZA. Dropped by Gus. 1 of 7 got it. Your guess was Cal. Wrong.")
    }

    /// No guess, no second sentence — the same silence the screen shows.
    @Test func aResultsCardWithNoGuessAnnouncesOnlyTheAnswer() {
        let label = Copy.A11y.card(
            number: 4, title: "Ribs", artist: "Lorde",
            guess: .resolved(CardResolution(
                owner: "Ana", correctCount: 6, eligibleCount: 7, myGuess: nil
            ))
        )

        #expect(label == "No. 4. Ribs by Lorde. Dropped by Ana. 6 of 7 got it.")
    }

    /// **Never red, never a cross** (`docs/07` §2) — and never the word either. A correct guess
    /// is announced with the same sentence shape as a wrong one, so the reader is told a fact
    /// rather than congratulated.
    @Test func aCorrectGuessIsAnnouncedInTheSameSentenceShape() {
        let label = Copy.A11y.card(
            number: 1, title: "Redbone", artist: "Childish Gambino",
            guess: .resolved(CardResolution(
                owner: "Dee", correctCount: 4, eligibleCount: 7,
                myGuess: CardResolution.MyGuess(name: "Dee", isCorrect: true)
            ))
        )

        #expect(label.hasSuffix("Your guess was Dee. Correct."))
    }

    // MARK: - The name-resolve (docs/09 §4)

    /// *"Names arrive top-to-bottom, 120ms apart … the mark 80ms after its name."*
    ///
    /// Asserted on the timeline rather than by sleeping through it, which is the only way this
    /// cadence is a thing a test can be exact about.
    @Test func theTimelineStaggersNamesAndTrailsEachMarkBehindItsOwn() {
        let events = ResolveAnimation.timeline(cardNumbers: [1, 2, 3])

        #expect(events.map(\.at) == [0, 80, 120, 200, 240, 320])
        #expect(events.map(\.cardNumber) == [1, 1, 2, 2, 3, 3])
        #expect(events.map(\.kind) == [.name, .mark, .name, .mark, .name, .mark])
    }

    /// The card numbers are the server's, not indices: a flight that starts at No. 1 and a
    /// hypothetical one that does not are scheduled the same way.
    @Test func theTimelineSchedulesByPositionAndCarriesTheCardsOwnNumber() {
        let events = ResolveAnimation.timeline(cardNumbers: [7, 4])
        #expect(events.map { ($0.at, $0.cardNumber) }.map(\.0) == [0, 80, 120, 200])
        #expect(events.map(\.cardNumber) == [7, 7, 4, 4])
    }

    /// **Any scroll gesture completes the whole sequence immediately** (`docs/09` §4). Nothing
    /// is left mid-flight and nothing arrives afterwards.
    @Test func aSkipSettlesEveryCardAtOnce() {
        let animation = ResultsFixture.animation(cards: [1, 2, 3])
        #expect(animation.isRunning)

        animation.skip()

        #expect(!animation.isRunning)
        for card in [1, 2, 3] {
            #expect(animation.presentation(for: card, reducedMotion: false) == .settled)
        }
    }

    /// *"Results resolve: all names appear at once, no stagger"* (`docs/09` §5). Reduced motion
    /// removes the movement, not the arrival — so the end state is identical to the normal
    /// path's, which is exactly what `docs/09` §6 asks a test to compare.
    @Test func reducedMotionLandsOnTheSameEndState() async {
        let animation = ResultsFixture.animation(cards: [1, 2, 3])

        await animation.run(reducedMotion: true)

        #expect(!animation.isRunning)
        #expect(animation.namedCards == [1, 2, 3])
        #expect(animation.markedCards == [1, 2, 3])
    }

    /// **Runs once per round, persisted** (`docs/09` §4). A relaunch opens on the answers
    /// already in place rather than replaying them.
    @Test func aRoundResolvesOnlyOnceAcrossRelaunch() async {
        let defaults = RoundFixture.scratchDefaults()
        let first = ResolveAnimation(
            roundID: "round-scored", cardNumbers: [1, 2], flags: LocalFlags(defaults: defaults)
        )
        await first.run(reducedMotion: true)

        let relaunched = ResolveAnimation(
            roundID: "round-scored", cardNumbers: [1, 2], flags: LocalFlags(defaults: defaults)
        )

        #expect(!relaunched.isRunning)
        #expect(relaunched.presentation(for: 1, reducedMotion: false) == .settled)
    }

    /// A different round still gets its own run — the flag is per round, not per install.
    @Test func anotherRoundStillResolves() async {
        let defaults = RoundFixture.scratchDefaults()
        let first = ResolveAnimation(
            roundID: "round-a", cardNumbers: [1], flags: LocalFlags(defaults: defaults)
        )
        await first.run(reducedMotion: true)

        let second = ResolveAnimation(
            roundID: "round-b", cardNumbers: [1], flags: LocalFlags(defaults: defaults)
        )

        #expect(second.isRunning)
    }

    // MARK: - The store

    /// The store asks the round's own route and keeps the server's card order (`E03-04`).
    @Test func theStoreLoadsTheAnswersAndDoesNotReorderThem() async throws {
        let (env, session) = RoundFixture.environment()
        session.arm([try RoundFixture.envelope("results")])
        let store = ResultsStore(api: env.api, roundID: "c0000000-0000-4000-8000-000000000001")

        await store.load()

        #expect(store.cards.map(\.cardNumber) == Array(1...8))
        let path = try #require(session.requests.first?.url?.path())
        #expect(path.hasSuffix("/rounds/c0000000-0000-4000-8000-000000000001/results"))
    }

    /// A failed refresh keeps the answers on screen (`LoadState.stale`). Results do not change
    /// once they land, so blanking them because a refetch timed out would throw away a screen
    /// that was still correct.
    @Test func aFailedRefreshKeepsTheAnswers() async throws {
        let (env, session) = RoundFixture.environment()
        session.arm([try RoundFixture.envelope("results")])
        let store = ResultsStore(api: env.api, roundID: "r")
        await store.load()

        session.arm([RoundStub.Response(status: 0, body: Data(), failure: URLError(.notConnectedToInternet))])
        await store.load()

        #expect(store.cards.count == 8)
        #expect(store.state.error == .offline)
    }
}

/// The §4.4 results, decoded from the fixture the server serves.
@MainActor
enum ResultsFixture {
    static func results() throws -> ResultsDTO {
        try JSONDecoder.api.decode(ResultsDTO.self, from: RoundFixture.payload("results"))
    }

    static func animation(cards: [Int]) -> ResolveAnimation {
        ResolveAnimation(
            roundID: "round-\(UUID().uuidString)",
            cardNumbers: cards,
            flags: LocalFlags(defaults: RoundFixture.scratchDefaults())
        )
    }
}
