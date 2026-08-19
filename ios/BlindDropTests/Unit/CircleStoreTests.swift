import Foundation
import Testing
@testable import BlindDrop

/// `CircleStore` — `E19-01`, `docs/01` ADR-011. What every group-scoped store resolves as "the
/// active circle" before it can load anything.
@MainActor
@Suite(.serialized) struct CircleStoreTests {

    private func circlesResponse(_ ids: [String]) -> RoundStub.Response {
        let json: [String: Any] = [
            "circles": ids.map { ["id": $0, "name": $0, "my_state": "sealed", "needs_action": false] },
        ]
        return RoundFixture.envelope(try! JSONSerialization.data(withJSONObject: json))
    }

    /// A persisted choice is used as long as it still names one of the caller's circles — the
    /// point of persisting it at all.
    @Test func theSavedChoiceWinsWhenItStillNamesACircle() async throws {
        let (env, stub) = RoundFixture.environment()
        stub.armExact("/groups", circlesResponse(["a", "b"]))
        env.flags.activeCircleID = "b"

        let resolved = await env.circles.resolveActiveID()

        #expect(resolved == "b")
    }

    /// A saved id for a circle the caller has since left is quietly ignored rather than
    /// remembered forever — the server's own oldest-active-first order is what `/groups/current`
    /// always resolved to, and is the fallback here.
    @Test func astaleSavedChoiceFallsBackToServerOrder() async throws {
        let (env, stub) = RoundFixture.environment()
        stub.armExact("/groups", circlesResponse(["a", "b"]))
        env.flags.activeCircleID = "some-circle-the-caller-left"

        let resolved = await env.circles.resolveActiveID()

        #expect(resolved == "a", "the first row is the server's oldest-active-first order")
    }

    /// `GET /groups` answering `{"circles": []}` is `docs/04` §3's `NO_GROUP`, restated as a 200
    /// rather than a 409 — and nothing routes a caller with no circle back to onboarding unless
    /// this tells `SessionStore` so explicitly (`E19-01` review).
    @Test func anEmptyListResolvesToNilAndTellsTheSession() async throws {
        let (env, stub) = RoundFixture.environment()
        stub.armExact("/groups", circlesResponse([]))

        let resolved = await env.circles.resolveActiveID()

        #expect(resolved == nil)
        #expect(env.session.state == .noGroup)
    }

    /// The list belongs to whoever was signed in when it was fetched. `AppEnvironment` outlives
    /// any one session, so a sign-out has to clear the cache or the next account sees the first
    /// one's circles until something else happens to trigger a refetch.
    @Test func resetClearsTheCachedList() async throws {
        let (env, stub) = RoundFixture.environment()
        stub.armExact("/groups", circlesResponse(["a"]))
        _ = await env.circles.resolveActiveID()
        #expect(env.circles.state.value != nil)

        env.circles.reset()

        #expect(env.circles.state.value == nil)
        #expect(env.circles.activeGroupID == nil)
    }

    /// `SessionStore.endSession()` calls `reset()` itself — this is the wiring, not the logic
    /// above, and it is what a sign-out/sign-in on the same install actually depends on.
    @Test func endingTheSessionResetsTheCircleList() async throws {
        let (env, stub) = RoundFixture.environment()
        stub.armExact("/groups", circlesResponse(["a"]))
        _ = await env.circles.resolveActiveID()
        #expect(env.circles.state.value != nil)

        env.session.endSession()

        #expect(env.circles.state.value == nil)
    }

    /// Three stores resolving their circle on the same launch produce one request, the same
    /// de-duplication `SessionStore.refreshCredentials` uses.
    @Test func concurrentResolvesShareOneRequest() async throws {
        let (env, stub) = RoundFixture.environment()
        stub.armExact("/groups", circlesResponse(["a", "b"]))

        async let first = env.circles.resolveActiveID()
        async let second = env.circles.resolveActiveID()
        async let third = env.circles.resolveActiveID()
        let results = await [first, second, third]

        #expect(results == ["a", "a", "a"])
        #expect(stub.count(matching: "/groups") == 1)
    }
}
