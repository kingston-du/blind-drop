import Foundation
import Testing
@testable import BlindDrop

/// `docs/13` §4's routing table, asserted as a value. The view switches on exactly this, so a
/// wrong row here is a wrong screen there.
@Suite struct RootDestinationTests {

    @Test(arguments: zip(
        [SessionState.unknown, .signedOut, .noProfile, .noGroup, .ready],
        [RootDestination.waiting, .signIn, .displayName, .joinOrCreate, .round]
    ))
    func sessionStateSelectsTheScreen(_ session: SessionState, _ expected: RootDestination) {
        #expect(RootDestination(session: session) == expected)
    }

    /// The one that matters most: before the first response we show nothing, not a sign-in
    /// wall. A signed-in user must never be asked to sign in because a request was in flight.
    @Test func unknownRendersNothingRatherThanGuessingSignedOut() {
        #expect(RootDestination(session: .unknown) == .waiting)
        #expect(RootDestination(session: .unknown) != .signIn)
    }
}

/// `docs/05` §5: *"A deep link **never** shortcuts a phase gate … A deep link is a navigation
/// hint, not an authorization."* Everything here is that sentence, made testable.
@MainActor
@Suite struct RouterTests {

    @Test func receivingALinkNavigatesNothing() {
        let router = Router()
        router.receive(.record(groupID: nil))
        #expect(router.path.isEmpty)
        #expect(router.pending == .record(groupID: nil))
    }

    /// `E19-03` review: a person's own tap in the switcher is the last word — it discards
    /// whatever a deep link was still asking for rather than letting the link reassert itself.
    @Test func clearPendingDropsAnOutstandingLink() {
        let router = Router()
        router.receive(.round(groupID: "g_1"))
        #expect(router.pending != nil)

        router.clearPending()

        #expect(router.pending == nil)
    }

    @Test func aLinkIsNotConsumedBeforeTheRoundLoads() {
        let router = Router()
        router.receive(.record(groupID: nil))
        router.consume(session: .ready, roundIsLoaded: false)
        #expect(router.path.isEmpty)
        #expect(router.pending == .record(groupID: nil))
    }

    @Test func theRecordIsPushedOnceTheRoundHasLoaded() {
        let router = Router()
        router.receive(.record(groupID: nil))
        router.consume(session: .ready, roundIsLoaded: true)
        #expect(router.path == [.record])
        #expect(router.pending == nil)
    }

    /// A link consumed twice re-pushes The Record every time the round refetches.
    @Test func aLinkIsConsumedExactlyOnce() {
        let router = Router()
        router.receive(.record(groupID: nil))
        router.consume(session: .ready, roundIsLoaded: true)
        router.path = []
        router.consume(session: .ready, roundIsLoaded: true)
        #expect(router.path.isEmpty)
    }

    /// Results for today is a branch of `RoundScreen`, not a pushed destination. Opened at
    /// 21:30 against a `revealed` round it lands on the guess screen with no error — which is
    /// only true because consuming it pushes nothing and sets no phase.
    @Test func resultsPopsToTheRootAndPushesNothing() {
        let router = Router()
        router.path = [.settings]
        router.receive(.results(groupID: nil))
        router.consume(session: .ready, roundIsLoaded: true)
        #expect(router.path.isEmpty)
        #expect(router.pending == nil)
    }

    @Test func theRoundLinkPopsToTheRoot() {
        let router = Router()
        router.path = [.record]
        router.receive(.round(groupID: nil))
        router.consume(session: .ready, roundIsLoaded: true)
        #expect(router.path.isEmpty)
    }

    /// Joining is a session concern, not a round concern, so it does not wait on a round.
    @Test func aJoinLinkPrefillsTheCodeWhenTheCallerHasNoGroup() {
        let router = Router()
        router.receive(.join(code: "K7MQ2X"))
        router.consume(session: .noGroup, roundIsLoaded: false)
        #expect(router.pendingInviteCode == "K7MQ2X")
        #expect(router.pending == nil)
    }

    /// docs/04 §3 would answer `ALREADY_IN_GROUP`. Tapping your own invite is noise, not an
    /// error worth showing.
    @Test func aJoinLinkIsDroppedSilentlyWhenAlreadyInAGroup() {
        let router = Router()
        router.receive(.join(code: "K7MQ2X"))
        router.consume(session: .ready, roundIsLoaded: true)
        #expect(router.pendingInviteCode == nil)
        #expect(router.pending == nil)
        #expect(router.path.isEmpty)
    }

    /// Sign-in and naming come first; the code is still good afterwards, so it must survive.
    @Test(arguments: [SessionState.unknown, .signedOut, .noProfile])
    func aJoinLinkSurvivesUntilTheCallerCanUseIt(_ session: SessionState) {
        let router = Router()
        router.receive(.join(code: "K7MQ2X"))
        router.consume(session: session, roundIsLoaded: false)
        #expect(router.pending == .join(code: "K7MQ2X"))
        #expect(router.pendingInviteCode == nil)

        router.consume(session: .noGroup, roundIsLoaded: false)
        #expect(router.pendingInviteCode == "K7MQ2X")
    }

    @Test func aDirectInvitationWaitsForAnAuthenticatedProfileThenOpens() {
        let router = Router()
        let id = "c0000000-0000-4000-8000-000000000001"
        router.receive(.invitation(id: id))

        router.consume(session: .signedOut, roundIsLoaded: false)
        #expect(router.pending == .invitation(id: id))

        router.consume(session: .ready, roundIsLoaded: false)
        #expect(router.pending == nil)
        #expect(router.pendingInvitationID == id)
    }

    /// A round-scoped link received while signed out must not act on the next session change
    /// alone — the round still has to be there.
    @Test func roundLinksRequireBothAReadySessionAndALoadedRound() {
        let router = Router()
        router.receive(.record(groupID: nil))
        router.consume(session: .signedOut, roundIsLoaded: true)
        #expect(router.pending == .record(groupID: nil))
        router.consume(session: .ready, roundIsLoaded: false)
        #expect(router.pending == .record(groupID: nil))
        router.consume(session: .ready, roundIsLoaded: true)
        #expect(router.path == [.record])
    }

    /// `docs/08` intro and `docs/13` §4: three pushed destinations, and that is the list. The
    /// modal (Search) is presented from Submit and never enters the path.
    @Test func thePathHasExactlyThreeDestinations() {
        #expect(Route.allCases.count == 3)
        #expect(Set(Route.allCases) == [.record, .group, .settings])
    }
}

/// `Router.resolvePendingCircle(against:)` — `E19-03`. Switching to a link's named circle
/// **before** landing on it, and failing gracefully when the caller does not hold that circle.
@MainActor
@Suite struct ResolvePendingCircleTests {

    private func circlesResponse(_ ids: [String]) -> RoundStub.Response {
        let json: [String: Any] = [
            "circles": ids.map { ["id": $0, "name": $0, "my_state": "sealed", "needs_action": false] },
        ]
        return RoundFixture.envelope(try! JSONSerialization.data(withJSONObject: json))
    }

    /// A link naming a circle the caller holds, other than the active one, switches to it.
    @Test func switchesToAHeldCircleTheLinkNames() async throws {
        let (env, stub) = RoundFixture.environment()
        stub.armExact("/groups", circlesResponse(["a", "b"]))
        _ = await env.circles.resolveActiveID()
        #expect(env.circles.activeGroupID == "a", "the server's own oldest-active-first order")

        env.router.receive(.record(groupID: "b"))
        env.router.resolvePendingCircle(against: env.circles)

        #expect(env.circles.activeGroupID == "b")
        #expect(env.router.pending == .record(groupID: "b"), "the link itself is untouched — only navigated once `consume` runs")
    }

    /// A link naming a circle the caller has left, or never joined, fails gracefully: dropped,
    /// same as a link this app does not recognise at all — never a guess at a fallback circle.
    @Test func dropsALinkNamingACircleTheCallerDoesNotHold() async throws {
        let (env, stub) = RoundFixture.environment()
        stub.armExact("/groups", circlesResponse(["a", "b"]))
        _ = await env.circles.resolveActiveID()

        env.router.receive(.round(groupID: "some-circle-the-caller-left"))
        env.router.resolvePendingCircle(against: env.circles)

        #expect(env.circles.activeGroupID == "a", "no switch happened")
        #expect(env.router.pending == nil, "and the link is gone rather than left to be guessed at later")
    }

    /// A link naming the circle already active is a no-op — nothing to switch, nothing dropped.
    @Test func noOpsWhenTheLinkNamesTheAlreadyActiveCircle() async throws {
        let (env, stub) = RoundFixture.environment()
        stub.armExact("/groups", circlesResponse(["a", "b"]))
        _ = await env.circles.resolveActiveID()

        env.router.receive(.round(groupID: "a"))
        env.router.resolvePendingCircle(against: env.circles)

        #expect(env.circles.activeGroupID == "a")
        #expect(env.router.pending == .round(groupID: "a"))
    }

    /// A bare link — no circle prefix — never touches the active circle.
    @Test func abareLinkNeverSwitches() async throws {
        let (env, stub) = RoundFixture.environment()
        stub.armExact("/groups", circlesResponse(["a", "b"]))
        _ = await env.circles.resolveActiveID()

        env.router.receive(.round(groupID: nil))
        env.router.resolvePendingCircle(against: env.circles)

        #expect(env.circles.activeGroupID == "a")
        #expect(env.router.pending == .round(groupID: nil))
    }

    /// Nothing pending is nothing to resolve.
    @Test func nothingPendingIsANoOp() async throws {
        let (env, stub) = RoundFixture.environment()
        stub.armExact("/groups", circlesResponse(["a"]))
        _ = await env.circles.resolveActiveID()

        env.router.resolvePendingCircle(against: env.circles)

        #expect(env.circles.activeGroupID == "a")
    }
}
