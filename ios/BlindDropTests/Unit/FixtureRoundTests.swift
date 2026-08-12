import Foundation
import Testing
@testable import BlindDrop

/// `E10-01`'s *"`PHASE=open` fixture run"* and `E10-02`'s *"search returns results < 400ms against
/// the fixture server"*.
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
    private func servedPhase() async throws -> RoundState {
        let base = try #require(FixtureServer.baseURL)
        let (data, _) = try await URLSession.shared.data(from: base.appending(path: "__fixture"))
        let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let phase = (envelope?["data"] as? [String: Any])?["phase"] as? String ?? "open"
        // The server's phase names carry a variant suffix (`open_nosub`, `revealed_joinedlate`);
        // the round's state is the part before it.
        return RoundState(rawValue: phase.split(separator: "_").first.map(String.init) ?? phase) ?? .open
    }

    /// The whole screen's data, from the server the app will actually speak to.
    @Test func theRoundLoadsAgainstTheFixtureServer() async throws {
        let env = try environment()
        let store = RoundStore(api: env.api, session: env.session, clock: env.clock, router: env.router)

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

    /// **AC-10's search budget** (`E10-02`): a query returns results in under 400ms.
    ///
    /// Measured around the client's own call, which is what the user waits on — the debounce sits
    /// in front of it and is asserted separately in `SubmitStoreTests`. The fixture server answers
    /// from memory, so what this really proves is that nothing in the client's path (the envelope,
    /// the retry policy, the decode of twenty tracks) is slow enough to spend the budget on its
    /// own.
    @Test func searchAnswersInsideTheBudget() async throws {
        let env = try environment()
        let store = SubmitStore(api: env.api)

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
        let store = SubmitStore(api: env.api)

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
        let round = RoundStore(api: env.api, session: env.session, clock: env.clock, router: env.router)
        let submit = SubmitStore(api: env.api)
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

    private func resolvedTrack(_ store: SubmitStore) async -> TrackDTO? {
        store.pasted = "https://open.spotify.com/track/2QjOHCTQ1JF3zJyfWY7EMU"
        return await store.resolve()
    }
}
