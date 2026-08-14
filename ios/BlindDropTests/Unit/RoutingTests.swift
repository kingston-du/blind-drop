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
        router.receive(.record)
        #expect(router.path.isEmpty)
        #expect(router.pending == .record)
    }

    @Test func aLinkIsNotConsumedBeforeTheRoundLoads() {
        let router = Router()
        router.receive(.record)
        router.consume(session: .ready, roundIsLoaded: false)
        #expect(router.path.isEmpty)
        #expect(router.pending == .record)
    }

    @Test func theRecordIsPushedOnceTheRoundHasLoaded() {
        let router = Router()
        router.receive(.record)
        router.consume(session: .ready, roundIsLoaded: true)
        #expect(router.path == [.record])
        #expect(router.pending == nil)
    }

    /// A link consumed twice re-pushes The Record every time the round refetches.
    @Test func aLinkIsConsumedExactlyOnce() {
        let router = Router()
        router.receive(.record)
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
        router.receive(.results)
        router.consume(session: .ready, roundIsLoaded: true)
        #expect(router.path.isEmpty)
        #expect(router.pending == nil)
    }

    @Test func theRoundLinkPopsToTheRoot() {
        let router = Router()
        router.path = [.record]
        router.receive(.round)
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

    /// A round-scoped link received while signed out must not act on the next session change
    /// alone — the round still has to be there.
    @Test func roundLinksRequireBothAReadySessionAndALoadedRound() {
        let router = Router()
        router.receive(.record)
        router.consume(session: .signedOut, roundIsLoaded: true)
        #expect(router.pending == .record)
        router.consume(session: .ready, roundIsLoaded: false)
        #expect(router.pending == .record)
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
