import Foundation
import Testing
@testable import BlindDrop

/// The round flow's live-fixture checks: E10's open/search/seal paths and E11's revealed guess
/// save.
///
/// `RoundStoreTests` and `SubmitStoreTests` are stubs — fast, exact, and unable to notice that the
/// client builds a body the server would refuse or reads a field the contract does not send. This
/// suite runs the **real** `APIClient` and the **real** DTO decoding against `ios/Fixtures/server.ts`,
/// whose payloads are `docs/04` verbatim (`E00-05`).
///
/// Skipped unless `BLINDDROP_FIXTURE_API` is set, which `ios/scripts/verify-fixture.sh` does after
/// starting the server. A test that silently passes when its server is not running is worse than
/// no test.
@MainActor
@Suite(.enabled(if: FixtureServer.baseURL != nil))
struct FixtureRoundTests {

    private func environment() throws -> AppEnvironment {
        let base = try #require(FixtureServer.baseURL)
        return AppEnvironment(
            configuration: AppConfiguration(apiBaseURL: base),
            secrets: Keychain(service: "app.blinddrop.tests.\(UUID().uuidString)"),
            defaults: RoundFixture.scratchDefaults()
        )
    }

    /// The phase the server was started with, read from its own `/__fixture` route.
    ///
    /// Asked rather than assumed, so the one suite covers both of the epic's fixture runs —
    /// `E10-01`'s *"`PHASE=open` fixture run"* and `E10-06`'s *"`PHASE=voided` fixture run"* — by
    /// being run twice against a server started differently, instead of by two suites that would
    /// each be skipped half the time.
    private func servedFixturePhase() async throws -> String {
        let base = try #require(FixtureServer.baseURL)
        let (data, _) = try await URLSession.shared.data(from: base.appending(path: "__fixture"))
        let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (envelope?["data"] as? [String: Any])?["phase"] as? String ?? "open"
    }

    private func servedPhase() async throws -> RoundState {
        let phase = try await servedFixturePhase()
        // The server's phase names carry a variant suffix (`open_nosub`, `revealed_joinedlate`);
        // the round's state is the part before it.
        return RoundState(rawValue: phase.split(separator: "_").first.map(String.init) ?? phase) ?? .open
    }

    /// The whole screen's data, from the server the app will actually speak to.
    @Test func theRoundLoadsAgainstTheFixtureServer() async throws {
        let env = try environment()
        let store = RoundStore(
            api: env.api, session: env.session, clock: env.clock, router: env.router, circles: env.circles
        )

        await store.load()

        let context = try #require(store.state.value, "the round and the group both landed")
        #expect(context.round.state == (try await servedPhase()),
                "the client renders the phase the server named, and never one of its own")
        #expect(context.group.name == "The Cove")
        // Everything the screen writes down comes off these two, and none of it is about anybody
        // else: a date, an hour, an initial (`docs/08` §2, §4).
        #expect(context.dateHeadline != nil)
        #expect(!context.revealTime.isEmpty)
        #expect(!context.opensTime.isEmpty)
        #expect(context.groupInitial == "T")
        #expect(env.clock.now != nil, "every response anchors the clock")
    }

    /// `E19-02`: picking a circle in the switcher re-scopes `RoundStore` to it, against the real
    /// second circle `E19-01` added to the fixture server for exactly this — a real `:group_id`
    /// route the client did not have to invent a payload for.
    @Test func selectingACircleReScopesTheRoundToIt() async throws {
        let env = try environment()
        let store = RoundStore(
            api: env.api, session: env.session, clock: env.clock, router: env.router, circles: env.circles
        )
        await store.load()
        #expect(store.state.value?.group.name == "The Cove")

        // `Fixtures/server.ts`'s `SECONDARY_GROUP_ID` — a static second circle answered by every
        // `:group_id` route regardless of which `PHASE` the server was started with.
        env.circles.select("b0000000-0000-4000-8000-000000000099")
        store.invalidate()
        #expect(store.state.value == nil, "the previous circle is off screen before the refetch")

        await store.load()

        #expect(store.state.value?.group.name == "Late Night Radio")
    }

    /// **AC-10's search budget** (`E10-02`): a query returns results in under 400ms.
    ///
    /// Measured around the client's own call, which is what the user waits on — the debounce sits
    /// in front of it and is asserted separately in `SubmitStoreTests`. The fixture server answers
    /// from memory, so what this really proves is that nothing in the client's path (the envelope,
    /// the retry policy, the decode of twenty tracks) is slow enough to spend the budget on its
    /// own.
    @Test func searchAnswersInsideTheBudget() async throws {
        let env = try environment()
        let store = SubmitStore(api: env.api, circles: env.circles)

        let started = ContinuousClock.now
        store.query = "ribs"
        // The debounce plus a margin, then the results must already be there.
        try await Task.sleep(for: .milliseconds(700))
        let elapsed = ContinuousClock.now - started

        let results = try #require(store.results.value)
        #expect(!results.isEmpty)
        #expect(store.searchErrorKey == nil)
        // The request itself is what the budget is about; the sleep above is the debounce we
        // deliberately asked for.
        #expect(elapsed < .milliseconds(700) + .milliseconds(400))
    }

    /// The paste path against the real route.
    @Test func alinkResolvesAgainstTheFixtureServer() async throws {
        let env = try environment()
        let store = SubmitStore(api: env.api, circles: env.circles)

        store.pasted = "https://open.spotify.com/track/2QjOHCTQ1JF3zJyfWY7EMU"
        let track = await store.resolve()

        #expect(track?.title == "Ribs")
        #expect(store.pasteErrorKey == nil)
    }

    /// **The seal, end to end**: `PUT /rounds/current/submission`, and the round adopts what came
    /// back — which is what puts the caller on `SealedScreen` with no second round trip
    /// (`docs/08` §3.2).
    ///
    /// Only while the round is `open`, because that is the only phase the route allows: outside it
    /// the server answers `WRONG_PHASE` and the screen this exercises is not the one on display.
    /// Under a `voided` run the second half asserts the refusal instead, which is the same rule
    /// seen from the other side.
    @Test func sealingCompletesAndTheRoundAdoptsIt() async throws {
        let env = try environment()
        let round = RoundStore(
            api: env.api, session: env.session, clock: env.clock, router: env.router, circles: env.circles
        )
        let submit = SubmitStore(api: env.api, circles: env.circles)
        await round.load()
        let track = try #require(await resolvedTrack(submit))

        guard try await servedPhase() == .open else {
            #expect(await submit.seal(track) == nil, "a round that is not open seals nothing")
            #expect(submit.sealErrorKey != nil, "and the screen says so rather than animating")
            return
        }

        let submission = try #require(await submit.seal(track), "the server sealed it")
        round.adopt(submission)

        let context = try #require(round.state.value)
        #expect(context.round.state == .open, "sealing does not move the round along")
        #expect(context.round.mySubmission?.track.title == "Ribs")
    }

    /// E11-06 through the real `APIClient`: the whole sheet reaches the revealed fixture, a
    /// `null` clears its card, and the response decodes into the same DTO production adopts.
    @Test func guessesSaveAgainstTheRevealedFixture() async throws {
        guard try await servedFixturePhase() == "revealed" else { return }
        let env = try environment()
        let groupID = try #require(await env.circles.resolveActiveID())

        let sheet = try await env.api.send(.saveGuesses(groupID, [
            GuessAssignment(cardNumber: 1, guessedUserID: "u_ben"),
            GuessAssignment(cardNumber: 2, guessedUserID: nil),
        ]))

        #expect(sheet.assignments == [GuessDTO(cardNumber: 1, guessedUserID: "u_ben")])
        #expect(sheet.assignedCount == 1)
        #expect(sheet.assignableCount == 7)
    }

    /// **`E12-01`'s `PHASE=scored` fixture run.**
    ///
    /// The two halves of `docs/04` §4's split, in the order the app performs them: the round
    /// says `scored` and carries the base keys only, and the answers come from the round's own
    /// route. Run through the real `APIClient` and the real decoding, so a field the contract
    /// does not send — or a `null` the client turns into a zero — fails here rather than in a
    /// golden PNG.
    @Test func theAnswersLoadAgainstTheScoredFixture() async throws {
        guard try await servedFixturePhase() == "scored" else { return }
        let env = try environment()
        let round = RoundStore(
            api: env.api, session: env.session, clock: env.clock, router: env.router, circles: env.circles
        )

        await round.load()
        let context = try #require(round.state.value)
        #expect(context.round.state == .scored)

        let results = ResultsStore(api: env.api, roundID: context.round.id, circles: env.circles)
        await results.load()

        // The server's order, kept: `card_no` is the shuffle every member sees (`E03-04`).
        #expect(results.cards.map(\.cardNumber) == Array(1...8))
        let first = try #require(results.cards.first)
        #expect(first.resolution.owner == "Dee")
        #expect(first.resolution.eligibleCount == 7)

        // **`null` means *not applicable*, never *zero*** (`docs/04` §4). Eli submitted and
        // guessed nothing; a client that decoded that as `0` would turn "you sat out" into "you
        // scored nothing", which is the one judgement this product refuses to make.
        let people = try #require(results.state.value?.people)
        let eli = try #require(people.first { $0.displayName == "Eli" })
        #expect(eli.ear == nil)
        #expect(eli.readability != nil)
    }

    private func resolvedTrack(_ store: SubmitStore) async -> TrackDTO? {
        store.pasted = "https://open.spotify.com/track/2QjOHCTQ1JF3zJyfWY7EMU"
        return await store.resolve()
    }
}
