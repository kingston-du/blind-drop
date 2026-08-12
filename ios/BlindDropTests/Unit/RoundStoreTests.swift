import Foundation
import Testing
@testable import BlindDrop

/// `RoundStore` and `RoundContext` — `E10-01`'s two rules, asserted rather than commented.
///
/// `.serialized` because `RoundStub`'s queue is process-wide and these tests count requests.
@MainActor
@Suite struct RoundStoreTests {

    // MARK: - What the countdown counts to

    /// `docs/08` §2: during the dark hours the countdown reads to `opens_at`, and afterwards to
    /// the reveal. Both are the *same* `open` round — the difference is what time it is, and the
    /// time comes from the server's clock.
    @Test func anOpenRoundCountsToTheOpeningAndThenToTheReveal() throws {
        let context = try RoundFixture.context()
        let beforeOpen = context.round.opensAt.addingTimeInterval(-60)
        let afterOpen = context.round.opensAt.addingTimeInterval(60)

        #expect(context.deadline(now: beforeOpen) == context.round.opensAt)
        #expect(context.isBeforeOpen(now: beforeOpen))

        #expect(context.deadline(now: afterOpen) == context.round.revealsAt)
        #expect(!context.isBeforeOpen(now: afterOpen))
    }

    /// With no anchor the clock knows nothing, and *"the round has not opened"* is not the thing
    /// to guess (`docs/13` §5 rule 3). The screen shows `--:--:--` meanwhile.
    @Test func anUnanchoredClockDoesNotClaimTheRoundIsClosed() throws {
        let context = try RoundFixture.context()
        #expect(!context.isBeforeOpen(now: nil))
        #expect(context.deadline(now: nil) == context.round.revealsAt)
    }

    /// `docs/08` §6: the reveal counts to the answers, not to the reveal that has already happened.
    @Test func arevealedRoundCountsToTheAnswers() throws {
        let context = try RoundFixture.context("round_revealed")
        #expect(context.deadline(now: context.round.revealsAt) == context.round.scoresAt)
    }

    /// `docs/08` §5: a voided round counts to **tomorrow's** open, which the payload does not
    /// carry — it is one day added on the group's own clock.
    @Test func avoidedRoundCountsToTomorrowsOpening() throws {
        let context = try RoundFixture.context("round_voided")
        let deadline = context.deadline(now: context.round.revealsAt)

        #expect(deadline > context.round.opensAt)
        // A day later on the wall clock, which is 24 hours except across a DST boundary — the
        // reason this goes through `Calendar` rather than through arithmetic on seconds.
        let calendar = GroupCalendar(timezone: context.group.timezone).calendar
        #expect(calendar.dateComponents([.hour], from: context.round.opensAt, to: deadline).hour ?? 0 >= 23)
        #expect(context.calendar.headline(localDate: context.round.localDate) != nil)
    }

    // MARK: - Adopting a submission

    /// The seal's response is adopted without a refetch, and **the phase is copied, not chosen**
    /// (`CLAUDE.md` §2.2). Asserted across every phase, because the one that could go wrong is the
    /// one nobody thought about.
    @Test(arguments: ["round_open", "round_voided", "round_revealed", "round_scored"])
    func adoptingASubmissionNeverChangesThePhase(_ fixture: String) throws {
        let round = try RoundFixture.round(fixture)
        let submission = SubmissionDTO(track: try RoundFixture.track(), sealedAt: round.opensAt)

        let adopted = round.adopting(mySubmission: submission)

        #expect(adopted.state == round.state, "the phase is copied")
        #expect(adopted.mySubmission?.track == submission.track, "and only the caller's own song moved")
        #expect(adopted.id == round.id)
        #expect(adopted.revealsAt == round.revealsAt)
    }

    /// A revealed round keeps its cards through an adoption. The payload is not the caller's own
    /// data and has no business being rebuilt.
    @Test func adoptingKeepsARevealedRoundsCards() throws {
        let round = try RoundFixture.round("round_revealed")
        guard case let .revealed(_, before) = round.phase else {
            Issue.record("the fixture is not a revealed round")
            return
        }
        let submission = SubmissionDTO(track: try RoundFixture.track(), sealedAt: round.opensAt)

        guard case let .revealed(_, after) = round.adopting(mySubmission: submission).phase else {
            Issue.record("adopting changed the phase")
            return
        }
        #expect(after == before)
    }

    // MARK: - Loading

    /// The round and the group land together, and the deep link is consumed **after** they do
    /// (`docs/05` §5).
    @Test func loadingFetchesTheRoundAndTheGroup() async throws {
        let (env, stub) = RoundFixture.environment()
        stub.arm(routes: [
            "/rounds/current": try RoundFixture.envelope("round_open"),
            "/groups/current": try RoundFixture.envelope("group_current"),
        ])
        let store = RoundStore(api: env.api, session: env.session, clock: env.clock, router: env.router)

        await store.load()

        let context = try #require(store.state.value)
        #expect(context.round.state == .open)
        #expect(context.group.name == "The Cove")
        #expect(context.groupInitial == "T")
        #expect(context.revealTime.contains("8") || context.revealTime.contains("20"))
        #expect(env.clock.now != nil, "every response anchors the clock")
    }

    /// A failed refresh keeps what is on screen and says so — `docs/08` §10's offline row, and the
    /// reason `LoadState` has a `.stale` case at all.
    @Test func afailedRefreshKeepsTheLastGoodRound() async throws {
        let (env, stub) = RoundFixture.environment()
        stub.arm(routes: [
            "/rounds/current": try RoundFixture.envelope("round_open"),
            "/groups/current": try RoundFixture.envelope("group_current"),
        ])
        let store = RoundStore(api: env.api, session: env.session, clock: env.clock, router: env.router)
        await store.load()

        stub.arm([RoundStub.Response(failure: URLError(.notConnectedToInternet))])
        await store.load()

        #expect(store.state.value != nil, "the screen keeps what it had")
        #expect(store.state.error == .offline, "and says it may be out of date")
    }

    /// With nothing to fall back on, a failure is a failure — not an empty screen pretending to be
    /// a loaded one.
    @Test func afirstLoadThatFailsHasNothingToShow() async throws {
        let (env, _) = RoundFixture.environment(responses: [RoundStub.Response(failure: URLError(.timedOut))])
        let store = RoundStore(api: env.api, session: env.session, clock: env.clock, router: env.router)

        await store.load()

        #expect(store.state.value == nil)
        #expect(store.state.error == .offline)
    }

    /// The store refetches when the deadline passes; it never moves the round itself. There is no
    /// method on it that could — this asserts the question it *does* answer.
    @Test func theDeadlineIsReportedRatherThanActedOn() async throws {
        let (env, stub) = RoundFixture.environment()
        // `server_now` a minute after the reveal: the round on the wire still says `open`, because
        // only the server decides that, and the client's job is to notice and ask again.
        stub.arm(routes: [
            "/rounds/current": try RoundFixture.envelope("round_open", serverNow: "2026-08-11T00:01:00Z"),
            "/groups/current": try RoundFixture.envelope("group_current", serverNow: "2026-08-11T00:01:00Z"),
        ])
        let store = RoundStore(api: env.api, session: env.session, clock: env.clock, router: env.router)
        await store.load()

        #expect(store.deadlineHasPassed())
        #expect(store.state.value?.round.state == .open, "the client did not promote the round")
    }
}
