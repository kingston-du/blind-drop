import Foundation
import Testing
@testable import BlindDrop

/// The counts, at the answers (`E46-03`, `docs/19-REACTIONS.md` §7, §8.3, §8.4).
///
/// `ReactionTests` covers the *placing* half, at the reveal, where no count exists at all. This
/// suite is the other half: the arithmetic that keeps a count honest while a tap is still in
/// flight, the two absences that render identically on purpose, and the read-only archive.
///
/// **The claim this suite cannot make on its own** is the last one the slice asks for — that
/// nothing about reactions reaches the share card. The assertion for that is the share-card
/// goldens **not moving**: `ShareCardContent.rows` is `[ResultCardDTO]`, so every card the share
/// renderer holds now carries a tally, and the only reason none of it appears on the card is
/// that `ShareCardView` draws none of it. A picture is what proves that, and the pictures are
/// already committed. `theShareCardIsUnmovedByAMark` below pins everything about the content
/// *besides* those rows, so a regression that started reading the tally into a headline or a
/// band would fail here rather than only in a PNG.
@MainActor
@Suite struct ReactionCountTests {

    // MARK: - The two absences that look the same

    /// A card nobody marked, and a night that scored before this feature shipped, are the same
    /// render: **no row at all** (`docs/19` §8.3). The server sends three zeros for both, on
    /// purpose — a flag telling them apart would be a flag nothing could use.
    @Test func aCardNobodyMarkedIsEmpty() throws {
        let results = try ResultsFixture.results()
        let quiet = try #require(results.cards.first { $0.cardNumber == 3 })

        #expect(quiet.reactions.isEmpty)
        #expect(quiet.myReaction == nil)
        #expect(quiet.reactions == .none)
    }

    /// A round from before this shipped carries no `reactions` key at all, and decodes to the
    /// same three zeros rather than failing the whole payload — the allowance `tonightTopEar`
    /// already makes, for the same reason: a backend a step behind this build must not turn a
    /// past night's answers into *"That didn't work."*
    @Test func aPreFeatureNightDecodesToThreeZeros() throws {
        var json = try ResultsFixture.rawPayload()
        json["cards"] = (json["cards"] as? [[String: Any]] ?? []).map { card in
            var card = card
            card.removeValue(forKey: "reactions")
            card.removeValue(forKey: "my_reaction")
            return card
        }
        let results = try JSONDecoder.api.decode(
            ResultsDTO.self, from: try JSONSerialization.data(withJSONObject: json)
        )

        #expect(results.cards.count == 8)
        #expect(results.cards.allSatisfy { $0.reactions.isEmpty })
        #expect(results.cards.allSatisfy { $0.myReaction == nil })
    }

    /// All three keys, zeros included, never `null` (`docs/19` §7) — and the wire names are the
    /// contract's, not Swift's.
    @Test func theTallyCarriesAllThreeKinds() throws {
        let results = try ResultsFixture.results()
        let first = try #require(results.cards.first)

        #expect(first.reactions.loved == 4)
        #expect(first.reactions.interesting == 1)
        #expect(first.reactions.notForMe == 0)
        #expect(first.reactions.count(of: .notForMe) == 0, "a zero is a count, not an absence")
        #expect(first.myReaction == .loved)
    }

    // MARK: - The arithmetic

    /// The server's counts **include the caller's own mark**, so placing one has to move the
    /// number beside it. A filled heart over a count that did not move is a visible lie.
    @Test func placingAMarkMovesItsCount() {
        let counts = ReactionCounts(loved: 4, interesting: 1, notForMe: 0)

        let placed = counts.adjusted(from: nil, to: .loved)

        #expect(placed == ReactionCounts(loved: 5, interesting: 1, notForMe: 0))
    }

    @Test func changingAMarkMovesBothCounts() {
        let counts = ReactionCounts(loved: 4, interesting: 1, notForMe: 0)

        let changed = counts.adjusted(from: .loved, to: .interesting)

        #expect(changed == ReactionCounts(loved: 3, interesting: 2, notForMe: 0))
    }

    @Test func clearingAMarkTakesItBackOut() {
        let counts = ReactionCounts(loved: 4, interesting: 1, notForMe: 0)

        #expect(counts.adjusted(from: .loved, to: nil) == ReactionCounts(loved: 3, interesting: 1, notForMe: 0))
    }

    /// **Applied against the baseline, never accumulated** — which is what makes a sequence of
    /// taps unable to drift. Adjusting by a no-op change is the identity.
    @Test func adjustingToTheSameMarkChangesNothing() {
        let counts = ReactionCounts(loved: 4, interesting: 1, notForMe: 0)

        #expect(counts.adjusted(from: .loved, to: .loved) == counts)
        #expect(counts.adjusted(from: nil, to: nil) == counts)
    }

    /// Clamped at zero. It should never need to be — `from` is only ever a mark the server
    /// counted — and a negative count on a card would be the one arithmetic bug a person could
    /// actually see.
    @Test func aCountNeverGoesNegative() {
        let empty = ReactionCounts.none

        #expect(empty.adjusted(from: .loved, to: nil) == .none)
    }

    // MARK: - The store, marking at the answers

    /// A tap moves the mark **and** the count, before the write returns.
    @Test func markingAtTheAnswersMovesTheMarkAndTheCount() async throws {
        let store = try await loadedStore()

        // No. 6 — two hearts, and nothing of the caller's on it.
        store.mark(.loved, on: 6)

        let model = try #require(store.viewState(resolve: nil).reactions[6])
        #expect(model.mine == .loved)
        #expect(model.counts.loved == 3, "the caller's own mark joined the count it is part of")
    }

    /// **The caller's own card is markable here and nowhere else** (`docs/19` §4, §8.3): the
    /// quick pass skips it at the reveal, so the answers are the only surface it ever gets. No.
    /// 4 is Ana's own song in the §4.4 fixture — the store special-cases nothing about it.
    @Test func theCallersOwnCardIsMarkable() async throws {
        let store = try await loadedStore()
        let own = try #require(store.cards.first { $0.guesses != nil })
        #expect(own.cardNumber == 4)

        store.mark(.interesting, on: own.cardNumber)

        let model = try #require(store.viewState(resolve: nil).reactions[own.cardNumber])
        #expect(model.mine == .interesting)
        // It arrived `loved`, so the change moves two counts, not one.
        #expect(model.counts.loved == 2)
        #expect(model.counts.interesting == 3)
    }

    @Test func tappingTheChosenMarkAgainClearsIt() async throws {
        let store = try await loadedStore()

        store.mark(nil, on: 1)

        let model = try #require(store.viewState(resolve: nil).reactions[1])
        #expect(model.mine == nil)
        #expect(model.counts.loved == 3, "and the count came down with it")
    }

    @Test func aCardOutsideTheRoundIsIgnored() async throws {
        let store = try await loadedStore()

        store.mark(.loved, on: 99)

        #expect(store.marks[99] == nil)
    }

    /// The write goes to the **circle's current round**, with no round id in it (`docs/19` §7,
    /// guard 2). That absence is the structural half of *reactions close with the round*.
    @Test func theWriteGoesToTheCurrentRoundsRoute() async throws {
        let (store, session) = try await loadedStoreAndSession()

        store.mark(.notForMe, on: 6)
        await waitUntil { session.count(matching: "/current/reactions") == 1 }

        let write = try #require(session.requests.last { $0.url?.path().hasSuffix("/current/reactions") == true })
        #expect(write.httpMethod == "PUT")
        #expect(write.url?.path().contains(store.roundID) == false, "no round id in the write path")
    }

    /// **A write landing must not move the count back.** The baseline `adjusted(from:to:)` works
    /// against is the mark *the loaded payload's counts were computed with*, and a write does not
    /// reload the payload — so a landed write leaves both the mark and the count exactly where
    /// the tap put them. Treating the landed write as the new baseline made the adjustment a
    /// no-op a moment later and snapped the number back beside a mark that had stayed put, which
    /// is a lie a person sees on screen and no test here was asking about.
    @Test func aLandedWriteLeavesTheCountWhereTheTapPutIt() async throws {
        let (store, session) = try await loadedStoreAndSession()

        store.mark(.loved, on: 6)
        await waitUntil { session.count(matching: "/current/reactions") == 1 }
        // Long enough for the completion to have been applied on the main actor, which is the
        // window the regression lived in — the count was right at the tap and wrong afterwards.
        try? await Task.sleep(for: .milliseconds(300))

        let model = try #require(store.viewState(resolve: nil).reactions[6])
        #expect(model.mine == .loved)
        #expect(model.counts.loved == 3, "the count snapped back once the write landed")
    }

    /// A failed write puts the mark **and the count** back to what the server last confirmed. A
    /// mark left lit after a failure is a claim the person made and nobody recorded, and there
    /// is no later write to carry it — the next tap sends only its own card.
    @Test func aFailedWriteRevertsTheMarkAndItsCount() async throws {
        let (store, session) = try await loadedStoreAndSession()
        session.armExact("/current/reactions", RoundFixture.failure(409, "WRONG_PHASE"))

        store.mark(.notForMe, on: 1)
        #expect(store.marks[1] == .notForMe, "optimistic first")
        await waitUntil { store.reactionErrorKey != nil }

        let model = try #require(store.viewState(resolve: nil).reactions[1])
        #expect(model.mine == .loved, "back to what the server has")
        #expect(model.counts.loved == 4, "and the count with it")
    }

    /// A **new payload** is adopted: the mark and the count both come from the server again.
    ///
    /// This is the read side of the baseline. `adoptMarks()` also guards the write in flight —
    /// a refetch landing between a tap and its response must not put the server's older mark
    /// back over the one the person is looking at — and **that half is not asserted here**: the
    /// stub and the app share one `URLSession`, so a held write and the refetch meant to land
    /// inside it serialise, and the "concurrent" test would only ever be a picture of them
    /// happening in order. The guard is the same generation-and-in-flight apparatus
    /// `ReactionTests` exercises properly against `RevealStore`, which takes an injectable saver
    /// this store does not. Worth closing if `ResultsStore` ever grows one.
    @Test func aNewPayloadIsAdopted() async throws {
        let (store, session) = try await loadedStoreAndSession()
        #expect(store.marks[1] == .loved)

        var json = try ResultsFixture.rawPayload()
        json["cards"] = (json["cards"] as? [[String: Any]] ?? []).map { card in
            var card = card
            if card["card_no"] as? Int == 1 {
                card["my_reaction"] = "not_for_me"
                card["reactions"] = ["loved": 3, "interesting": 1, "not_for_me": 1]
            }
            return card
        }
        session.arm(routes: [
            "/results": RoundFixture.envelope(try JSONSerialization.data(withJSONObject: json)),
            "/standings": try RoundFixture.envelope("standings"),
        ])
        await store.load()

        let model = try #require(store.viewState(resolve: nil).reactions[1])
        #expect(model.mine == .notForMe)
        #expect(model.counts == ReactionCounts(loved: 3, interesting: 1, notForMe: 1),
                "the new payload's counts, adjusted by nothing")
    }

    // MARK: - What reactions must not touch (docs/19 §9)

    /// Placing a mark changes the reactions and **nothing else** on the screen's state: not the
    /// caller's two numbers, not the standings, not tonight's ranking, not the cards themselves.
    @Test func aMarkChangesNothingButTheReactions() async throws {
        let store = try await loadedStore()
        let before = store.viewState(resolve: nil)

        store.mark(.notForMe, on: 6)
        let after = store.viewState(resolve: nil)

        #expect(after.reactions != before.reactions)
        #expect(after.me == before.me)
        #expect(after.standings == before.standings)
        #expect(after.tonightTopEar == before.tonightTopEar)
        #expect(after.cards == before.cards, "the payload is untouched; the overlay is the store's")
    }

    /// The share card's own content is unmoved by the tally. `rows` is excluded because it *is*
    /// `[ResultCardDTO]` — every card carries a tally now, and the reason none of it appears on
    /// the card is that `ShareCardView` draws none of it, which the committed share goldens are
    /// the picture of. Everything the content derives is pinned here.
    @Test func theShareCardIsUnmovedByAMark() throws {
        let plain = try ResultsFixture.results()
        var json = try ResultsFixture.rawPayload()
        json["cards"] = (json["cards"] as? [[String: Any]] ?? []).map { card in
            var card = card
            card["reactions"] = ["loved": 9, "interesting": 9, "not_for_me": 9]
            card["my_reaction"] = "not_for_me"
            return card
        }
        let marked = try JSONDecoder.api.decode(
            ResultsDTO.self, from: try JSONSerialization.data(withJSONObject: json)
        )

        let a = ShareCardContent(results: plain, groupName: "The Cove", date: "8 August")
        let b = ShareCardContent(results: marked, groupName: "The Cove", date: "8 August")

        #expect(a.headline == b.headline)
        #expect(a.hasPersonalNight == b.hasPersonalNight)
        #expect(a.ear == b.ear)
        #expect(a.readability == b.readability)
        #expect(a.readabilityBand == b.readabilityBand)
        #expect(a.roomTally == b.roomTally)
        #expect(a.roomTallyOverflow == b.roomTallyOverflow)
        #expect(a.overflow == b.overflow)
    }

    // MARK: - What VoiceOver hears

    /// *"Loved it, 4"* — the word and the count, and **no denominator** (`docs/19` §7). A total
    /// tells a small circle exactly how many people did not say it.
    @Test func theRowIsReadAsAWordAndACount() {
        let spoken = Copy.format("a11y.reaction.count", Copy.string(ReactionKind.loved.copyKey), 4)

        #expect(spoken.contains("Loved it"))
        #expect(spoken.contains("4"))
        #expect(!spoken.contains(" of "), "a published count carries no total")
    }

    @Test func markingAtTheAnswersIsAnnounced() async throws {
        let store = try await loadedStore()

        store.mark(.loved, on: 6)

        let placed = store.announcement
        #expect(placed?.contains("Loved it") == true)
        #expect(placed?.contains("6") == true)
        store.consumeAnnouncement()
        #expect(store.announcement == nil)
    }

    // MARK: - Helpers

    private func loadedStore() async throws -> ResultsStore {
        try await loadedStoreAndSession().0
    }

    /// A store over the §4.4 answers, with its circle resolved — which is what gives the write
    /// route a group id to be scoped by.
    private func loadedStoreAndSession() async throws -> (ResultsStore, StubSession) {
        let (env, session) = RoundFixture.environment()
        session.arm(routes: [
            "/results": try RoundFixture.envelope("results"),
            "/standings": try RoundFixture.envelope("standings"),
        ])
        session.armExact("/current/reactions", RoundFixture.envelope(Data(#"{"my_reactions":[]}"#.utf8)))
        let store = ResultsStore(
            api: env.api,
            roundID: "c0000000-0000-4000-8000-000000000001",
            circles: env.circles
        )
        await store.load()
        return (store, session)
    }

    /// Polls with a real upper bound, the same pattern the other fixture-backed suites use: the
    /// main actor can be ready to perform a write without having been scheduled yet.
    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}

extension ResultsFixture {
    /// The §4.4 answers as loose JSON, for the two tests that have to **edit** the contract
    /// before decoding it — a night from before this feature, and a night with the tally maxed.
    static func rawPayload() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: RoundFixture.payload("results")) as? [String: Any] ?? [:]
    }
}
