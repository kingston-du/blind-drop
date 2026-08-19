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
        #expect(context.openState(now: beforeOpen) == .beforeOpen)

        #expect(context.deadline(now: afterOpen) == context.round.revealsAt)
        #expect(context.openState(now: afterOpen) == .open)
    }

    // MARK: - The unanchored clock has an answer of its own

    /// With no anchor the clock knows nothing, and *"the round is open"* is not the thing to
    /// guess (`docs/13` §5 rule 3) — which is exactly what the `Bool` this replaced did guess,
    /// on every return to the foreground, for the length of a refetch.
    ///
    /// **Every time-dependent branch has an *unknown* answer** and this is the assertion of it:
    /// there is no reading of `nil` here that comes out as one side of `opens_at`.
    @Test func anUnanchoredClockAnswersUnknownRatherThanGuessing() throws {
        let context = try RoundFixture.context()
        #expect(context.openState(now: nil) == .unknown)
        #expect(context.deadline(now: nil) == nil)
        #expect(context.deadline(openState: .unknown) == nil)
        // And specifically not the reveal, which is the wrong event by ten hours and the one the
        // old `false` picked.
        #expect(context.deadline(now: nil) != context.round.revealsAt)
    }

    /// The clock's silence is scoped to the one question that needs it. Three of the four phases
    /// count to something no reading of the clock could change — tomorrow's opening, the answers
    /// landing — so an unanchored clock must not blank *those*, or a foreground cycle would
    /// dash a countdown that was never in doubt.
    @Test(arguments: ["round_revealed", "round_voided", "round_scored"])
    func aphaseThatDoesNotAskTheClockStillKnowsItsDeadline(_ fixture: String) throws {
        let context = try RoundFixture.context(fixture)
        #expect(context.deadline(now: nil) != nil)
        #expect(context.deadline(now: nil) == context.deadline(now: context.round.revealsAt))
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
        let deadline = try #require(context.deadline(now: context.round.revealsAt))

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
        let groupID = try RoundFixture.groupID()
        stub.arm(routes: [
            "/rounds/\(groupID)/current": try RoundFixture.envelope("round_open"),
            "/groups/\(groupID)": try RoundFixture.envelope("group_current"),
        ])
        let store = RoundStore(
            api: env.api, session: env.session, clock: env.clock, router: env.router, circles: env.circles
        )

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
        let groupID = try RoundFixture.groupID()
        stub.arm(routes: [
            "/rounds/\(groupID)/current": try RoundFixture.envelope("round_open"),
            "/groups/\(groupID)": try RoundFixture.envelope("group_current"),
        ])
        let store = RoundStore(
            api: env.api, session: env.session, clock: env.clock, router: env.router, circles: env.circles
        )
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
        let store = RoundStore(
            api: env.api, session: env.session, clock: env.clock, router: env.router, circles: env.circles
        )

        await store.load()

        #expect(store.state.value == nil)
        #expect(store.state.error == .offline)
    }

    // MARK: - The hold

    /// **The foregrounding cycle, end to end** — the bug this suite's `.unknown` cases exist for.
    ///
    /// `RootView` invalidates the clock on `scenePhase == .active` and `RoundScreen` refetches;
    /// in between, `ServerClock` has no anchor. This walks that window with a round in the dark
    /// hours, which is the case that broke: the old `Bool` answered `false` there, the screen
    /// read that as *"open"*, and the search field and its keyboard went up over a closed round
    /// until the response landed.
    ///
    /// What `RoundScreen` holds is one `OpenState`, so that is what is walked here: the live
    /// reading goes `.beforeOpen` → `.unknown` → `.beforeOpen`, and the *held* answer — the one
    /// the screen renders from — is `.beforeOpen` throughout, pointing the countdown at
    /// `opens_at` the whole way rather than jumping to `reveals_at` and back.
    @Test func theHeldAnswerSurvivesAnInvalidateAndRefetch() async throws {
        let (env, stub) = RoundFixture.environment()
        // An hour before the round opens: the dark hours, on the server's clock.
        let beforeOpen = "2026-08-10T13:00:00Z"
        let groupID = try RoundFixture.groupID()
        stub.arm(routes: [
            "/rounds/\(groupID)/current": try RoundFixture.envelope("round_open", serverNow: beforeOpen),
            "/groups/\(groupID)": try RoundFixture.envelope("group_current", serverNow: beforeOpen),
        ])
        let store = RoundStore(
            api: env.api, session: env.session, clock: env.clock, router: env.router, circles: env.circles
        )
        await store.load()

        let context = try #require(store.state.value)
        let held = context.openState(now: env.clock.now)
        #expect(held == .beforeOpen)
        #expect(context.deadline(openState: held) == context.round.opensAt)

        // `willEnterForeground`. The anchor is stale after a nap (`docs/13` §5 rule 5) and the
        // refetch has not landed yet.
        env.clock.invalidate()

        #expect(context.openState(now: env.clock.now) == .unknown, "the clock says so honestly")
        #expect(context.deadline(now: env.clock.now) == nil, "and does not pick an event")
        // The screen renders from the held answer, which is unchanged and still counts to the
        // opening. This is the assertion that the search screen does not appear.
        #expect(context.deadline(openState: held) == context.round.opensAt)
        #expect(held != .open)

        // The refetch lands and the clock re-anchors. Nothing snaps, because nothing moved.
        await store.load()

        #expect(env.clock.now != nil)
        let after = try #require(store.state.value)
        #expect(after.openState(now: env.clock.now) == held)
        #expect(after.round.id == context.round.id, "the same round, so the hold was still valid")
    }

    /// **A context can never exist alongside an unanchored clock**, which is what makes the hold
    /// complete: on a cold launch there is nothing held, and there is nothing to hold *for*
    /// either, because there is no round on screen yet.
    ///
    /// The mechanism is in `APIClient.send`, which calls `clock.sync(serverNow:)` on the envelope
    /// before it returns the payload — so `RoundStore.load()` cannot reach `state.apply` with an
    /// unanchored clock. Asserted on both outcomes: a successful load has an anchor, and a failed
    /// one has no context to render with or without one.
    @Test func acontextNeverExistsWithoutAnAnchoredClock() async throws {
        let (offline, offlineStub) = RoundFixture.environment(
            responses: [RoundStub.Response(failure: URLError(.notConnectedToInternet))]
        )
        // `environment(responses:)` pre-arms a successful `/groups` so every other fixture-backed
        // test does not have to think about `CircleStore` at all (`E19-01`) — but *this* test's
        // whole point is a transport that is down for every request, circles included, so that
        // default has to be overridden rather than left to anchor the clock on its own.
        offlineStub.armExact("/groups", RoundStub.Response(failure: URLError(.notConnectedToInternet)))
        let unloaded = RoundStore(
            api: offline.api, session: offline.session, clock: offline.clock, router: offline.router,
            circles: offline.circles
        )
        await unloaded.load()
        #expect(offline.clock.now == nil, "a transport failure carries no server_now")
        #expect(unloaded.state.value == nil, "and so there is no round to render against it")

        let (env, stub) = RoundFixture.environment()
        let groupID = try RoundFixture.groupID()
        stub.arm(routes: [
            "/rounds/\(groupID)/current": try RoundFixture.envelope("round_open"),
            "/groups/\(groupID)": try RoundFixture.envelope("group_current"),
        ])
        let store = RoundStore(
            api: env.api, session: env.session, clock: env.clock, router: env.router, circles: env.circles
        )
        await store.load()

        #expect(store.state.value != nil)
        #expect(env.clock.now != nil, "the envelope anchored the clock before state.apply ran")
        // The pair, stated as the invariant the screen depends on rather than as two facts.
        #expect(store.state.value == nil || env.clock.now != nil)

        // Adopting a seal rebuilds a context that already existed, so it cannot introduce one
        // either — the other path to `state.apply(.success(…))`.
        store.adopt(SubmissionDTO(track: try RoundFixture.track(), sealedAt: try #require(env.clock.now)))
        #expect(store.state.value != nil)
        #expect(env.clock.now != nil)
    }

    /// The store refetches when the deadline passes; it never moves the round itself. There is no
    /// method on it that could — this asserts the question it *does* answer.
    @Test func theDeadlineIsReportedRatherThanActedOn() async throws {
        let (env, stub) = RoundFixture.environment()
        // `server_now` a minute after the reveal: the round on the wire still says `open`, because
        // only the server decides that, and the client's job is to notice and ask again.
        let groupID = try RoundFixture.groupID()
        stub.arm(routes: [
            "/rounds/\(groupID)/current": try RoundFixture.envelope("round_open", serverNow: "2026-08-11T00:01:00Z"),
            "/groups/\(groupID)": try RoundFixture.envelope("group_current", serverNow: "2026-08-11T00:01:00Z"),
        ])
        let store = RoundStore(
            api: env.api, session: env.session, clock: env.clock, router: env.router, circles: env.circles
        )
        await store.load()

        #expect(store.deadlineHasPassed())
        #expect(store.state.value?.round.state == .open, "the client did not promote the round")
    }
}
