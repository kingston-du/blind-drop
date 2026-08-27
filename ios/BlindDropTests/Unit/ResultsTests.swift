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

    // MARK: - E29-01: who guessed you, and tonight's top three

    /// `guesses` is populated only on the card the caller owns. No. 4 is Ana's, and the fixture
    /// carries six guesses against it — Ribs' duplicate (Ana and Ben both dropped it) makes every
    /// one of them correct, `docs/02` §4.3.
    @Test func guessesIsPopulatedOnlyOnTheCallersOwnCard() throws {
        let results = try ResultsFixture.results()
        let mine = try #require(results.cards.first { $0.cardNumber == 4 })
        let others = results.cards.filter { $0.cardNumber != 4 }

        #expect(mine.guesses?.map(\.guesserName) == ["Ben", "Cal", "Dee", "Fay", "Gus", "Hal"])
        #expect(mine.guesses?.allSatisfy(\.isCorrect) == true)
        for card in others {
            #expect(card.guesses == nil, "card \(card.cardNumber) is not Ana's")
        }
    }

    /// `tonight_top_ear` ranks the round alone — Cal's 100% leads, and Fay and Hal share rank 3 on
    /// an identical 0.571, the tie the fixture happens to carry at exactly the boundary this cuts
    /// off at. Both stay; the array is not simply truncated to three entries.
    @Test func tonightTopEarIsRankedWithTiesAtTheBoundaryKeptWhole() throws {
        let results = try ResultsFixture.results()

        #expect(results.tonightTopEar.map(\.displayName) == ["Cal", "Ana", "Fay", "Hal"])
        #expect(results.tonightTopEar.map(\.rank) == [1, 2, 3, 3])
    }

    /// `tonight_top_ear` arrived in `E29-01`; a backend deployed a step behind this build may not
    /// send it yet. That one absent ranking must not turn a whole night's answers into "That
    /// didn't work" — the screen decodes to an empty list and shows the rest.
    @Test func aResultsPayloadWithoutTonightTopEarStillDecodes() throws {
        var object = try #require(
            JSONSerialization.jsonObject(with: RoundFixture.payload("results")) as? [String: Any]
        )
        object.removeValue(forKey: "tonight_top_ear")
        let stripped = try JSONSerialization.data(withJSONObject: object)

        let results = try JSONDecoder.api.decode(ResultsDTO.self, from: stripped)

        #expect(results.tonightTopEar.isEmpty)
        #expect(results.cards.count == 8)
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

        #expect(events.map(\.at) == [0, 80, 120, 160, 200, 240, 280, 320, 400])
        #expect(events.map(\.cardNumber) == [1, 1, 2, 1, 2, 3, 2, 3, 3])
        #expect(events.map(\.kind) == [
            .name, .mark, .name, .bar, .mark, .name, .bar, .mark, .bar
        ])
    }

    /// The card numbers are the server's, not indices: a flight that starts at No. 1 and a
    /// hypothetical one that does not are scheduled the same way.
    @Test func theTimelineSchedulesByPositionAndCarriesTheCardsOwnNumber() {
        let events = ResolveAnimation.timeline(cardNumbers: [7, 4])
        #expect(events.map { ($0.at, $0.cardNumber) }.map(\.0) == [0, 80, 120, 160, 200, 280])
        #expect(events.map(\.cardNumber) == [7, 7, 4, 7, 4, 4])
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
        let store = ResultsStore(
            api: env.api, roundID: "c0000000-0000-4000-8000-000000000001", circles: env.circles
        )

        await store.load()

        #expect(store.cards.map(\.cardNumber) == Array(1...8))
        // *Some* request, not the first one: `load()` issues the answers and the standings
        // concurrently (`E12-03`), so which of the two wins the race is a coin flip and a test
        // that asserted on `.first` would pass or fail on it.
        let paths = session.requests.compactMap { $0.url?.path() }
        #expect(paths.contains { $0.hasSuffix("/rounds/c0000000-0000-4000-8000-000000000001/results") })
    }

    /// `tonight_top_ear` reaches `viewState` untouched — the store holds no opinion about it
    /// beyond decoding, the same as every other field on `ResultsDTO`.
    @Test func theStoreSurfacesTonightTopEar() async throws {
        let (env, session) = RoundFixture.environment()
        session.arm([try RoundFixture.envelope("results")])
        let store = ResultsStore(
            api: env.api, roundID: "c0000000-0000-4000-8000-000000000001", circles: env.circles
        )

        await store.load()

        #expect(store.viewState(resolve: nil).tonightTopEar.map(\.displayName) == ["Cal", "Ana", "Fay", "Hal"])
    }

    /// A failed refresh keeps the answers on screen (`LoadState.stale`). Results do not change
    /// once they land, so blanking them because a refetch timed out would throw away a screen
    /// that was still correct.
    @Test func aFailedRefreshKeepsTheAnswers() async throws {
        let (env, session) = RoundFixture.environment()
        session.arm([try RoundFixture.envelope("results")])
        let store = ResultsStore(api: env.api, roundID: "r", circles: env.circles)
        await store.load()

        session.arm([RoundStub.Response(status: 0, body: Data(), failure: URLError(.notConnectedToInternet))])
        await store.load()

        #expect(store.cards.count == 8)
        #expect(store.state.error == .offline)
    }

    // MARK: - The share entry (docs/10 §4–5)

    /// **The gap this closes.** `ResultsStore.viewState(resolve:)` used to never populate
    /// `share`, so **Share tonight** never rendered on any screen that only ever asked the store
    /// for it — which, before `RoundScreen`'s own `ResultsHost` grew a second, duplicate copy of
    /// this same construction, was every one of them. Once the answers and the group have both
    /// landed, the button's ingredients are there.
    @Test func theShareEntryAppearsOnceTheAnswersAndTheGroupHaveLanded() async throws {
        let (env, session) = RoundFixture.environment()
        let groupID = try RoundFixture.groupID()
        session.armExact("/groups/\(groupID)", try RoundFixture.envelope("group_current"))
        session.arm(routes: [
            "/results": try RoundFixture.envelope("results"),
            "/standings": try RoundFixture.envelope("standings"),
        ])
        let store = ResultsStore(
            api: env.api, roundID: "r", circles: env.circles, artworkLoader: CountingArtworkLoader()
        )

        await store.load()

        let share = try #require(store.viewState(resolve: nil).share)
        #expect(share.content.groupName == "The Cove")
        // Derived the same way `shareEntry` derives it, rather than a literal string — the date
        // this produces is `Locale.current`-dependent (`GroupCalendarTests` is the suite that
        // pins a locale), so what is worth asserting here is that the store used the fixture
        // group's own zone and the round's own `local_date`, not a hand-typed guess at either.
        let expectedDate = GroupCalendar(timezone: "America/New_York").shareDate(localDate: "2026-08-08")
        #expect(share.content.date == expectedDate)
    }

    /// No group, no share — `docs/10` §4's *"nothing about a round that is not `scored` is ever
    /// renderable"* extended to *"and nothing before the group is known either"*: the button
    /// does not appear ahead of having anything to put on the card. The answers still load on
    /// their own, the same independence `aFailedStandingsDoesNotTakeTheAnswersDown` already
    /// covers for `standings`.
    @Test func thereIsNoShareEntryWithoutTheGroup() async throws {
        let (env, session) = RoundFixture.environment()
        session.arm([try RoundFixture.envelope("results")])
        let store = ResultsStore(
            api: env.api, roundID: "r", circles: env.circles, artworkLoader: CountingArtworkLoader()
        )

        await store.load()

        #expect(store.cards.count == 8, "the answers still load on their own")
        #expect(store.viewState(resolve: nil).share == nil)
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
