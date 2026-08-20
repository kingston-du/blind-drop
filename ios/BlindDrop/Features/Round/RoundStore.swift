import Foundation

/// The round and the group it belongs to, together.
///
/// One value rather than two `LoadState`s because every phase screen needs both and neither is
/// useful alone: the countdown needs `reveals_at`, and the words beside it — *"Sealed until
/// 8:00."*, *"Monday 10 August"*, the stamp's initial — are all in the **group's** terms
/// (`docs/13` §5 rule 6). A screen holding one and waiting on the other would be a screen with a
/// countdown and no idea what it is counting to.
struct RoundContext: Sendable, Equatable {
    let round: RoundDTO
    let group: GroupDTO

    /// The mark printed in the seal stamp: the group's first letter.
    var groupInitial: String { String(group.name.prefix(1)) }

    /// The reveal hour as a person reads it — *"8:00 PM"* (`docs/11` `sealed.status`).
    var revealTime: String { RevealHour.formatted(group.revealHour) }

    /// The hour the next round opens, in the same form (`docs/11` `submit.closed.subhead`,
    /// `voided.next`).
    var opensTime: String { RevealHour.formatted(RevealHour.opensHour(revealHour: group.revealHour)) }

    /// The hour the answers land, in the same form (`docs/11` `howto.step4.time`). Nothing on a
    /// live phase screen needed this on its own — `deadline(now:)` already counts to `scores_at`
    /// — but the how-to page states it as a fact rather than a countdown, so it needs the words.
    var scoresTime: String { RevealHour.formatted(RevealHour.scoresHour(revealHour: group.revealHour)) }

    /// *"Monday 10 August"* (`docs/08` §2), in the group's timezone.
    var dateHeadline: String? {
        calendar.headline(localDate: round.localDate)
    }

    /// The group's own clock, which every date and hour on these screens is written in.
    var calendar: GroupCalendar { GroupCalendar(timezone: group.timezone) }

    /// Which side of `opens_at` an `open` round sits on — `docs/08` §2's dark hours, where the
    /// field is not raised and the copy names the next opening, versus the round being live.
    ///
    /// **Three cases rather than a `Bool`, because there are three answers.** A `Bool` has
    /// nowhere to put *"the clock has no anchor"*, so whichever way it falls it is asserting a
    /// fact about the time of day that the app does not have. That is not a hypothetical: it
    /// shipped. `isBeforeOpen(now:)` answered `nil` with `false` — *"the round is open"* — and
    /// `RootView` invalidates the clock on every `scenePhase == .active` (`docs/13` §5 rule 5),
    /// so for the length of one refetch on **every** return to the foreground the app rendered
    /// the search screen, keyboard and all, over a round that was actually closed, and then
    /// snapped back when the response landed.
    ///
    /// The type now makes that particular mistake unavailable: there is no way to read this
    /// value without deciding, in the open, what to do when the answer is `.unknown`. What
    /// `RoundScreen` does is hold the last one it was given — see `RoundScreen.openState(_:)`.
    enum OpenState: Sendable, Equatable {
        /// The clock has no anchor, so where the round sits in its own day is not yet a thing
        /// the app knows. It is not "closed" and it is not "open"; it is unanswered.
        case unknown
        /// Before `opens_at`: the dark hours.
        case beforeOpen
        /// `opens_at` has passed and the blind window is running.
        case open
    }

    /// Where the round sits relative to its opening, as far as the app actually knows.
    ///
    /// - Parameter now: the clock's reading, or `nil` while it has no anchor. `nil` in gives
    ///   `.unknown` out, unconditionally — `docs/13` §5 rule 3: an unanchored clock is truthful
    ///   about having no anchor rather than helpful about what the time probably is.
    func openState(now: Date?) -> OpenState {
        guard let now else { return .unknown }
        return now < round.opensAt ? .beforeOpen : .open
    }

    /// What the screen is counting to, and it is never the same thing twice:
    ///
    /// | Phase | Deadline | Why |
    /// |---|---|---|
    /// | `open`, before `opens_at` | `opens_at` | the dark hours (`docs/08` §2) |
    /// | `open` | `reveals_at` | the blind window closing |
    /// | `revealed` | `scores_at` | the answers landing |
    /// | `voided` | tomorrow's open | *"the countdown to tomorrow's open"* (`docs/08` §5) |
    /// | `scored` | tomorrow's open | the night is over |
    ///
    /// Taking an `OpenState` rather than a `Date?` is what lets `RoundScreen` ask this question
    /// against a **held** answer instead of against the clock directly. The two halves of the
    /// open phase's row in that table are the same fact stated twice — which side of `opens_at`
    /// we are on, and therefore what the countdown reads — so they must not be resolved
    /// separately or they can disagree for a frame.
    ///
    /// - Parameter openState: only the `open` phase consults it. The other three count to
    ///   something the clock has no say in, which is why a voided round still knows what it is
    ///   counting to while the clock is unanchored, and why this is not simply `nil` whenever
    ///   the clock is.
    /// - Returns: `nil` in exactly one case — an `open` round whose `OpenState` is `.unknown`,
    ///   where the answer genuinely depends on a time the app does not have. `opens_at` and
    ///   `reveals_at` are ten hours apart; picking one is not a rounding error, it is the
    ///   difference between counting to the right event and the wrong one.
    func deadline(openState: OpenState) -> Date? {
        switch round.phase {
        case .open:
            switch openState {
            case .unknown: nil
            case .beforeOpen: round.opensAt
            case .open: round.revealsAt
            }
        case .revealed:
            round.scoresAt
        case .voided, .scored:
            calendar.nextDay(round.opensAt)
        }
    }

    /// The same table, read straight off the clock. The convenience for everything that is not
    /// holding a previous answer — the store's own elapsed check, and the tests.
    func deadline(now: Date?) -> Date? {
        deadline(openState: openState(now: now))
    }
}

/// Owns today's round (`docs/13` §2).
///
/// Two rules shape this type, and both are `CLAUDE.md` §2:
///
/// 1. **It never decides a phase.** There is no method here that sets a state, and the only place
///    `RoundDTO.phase` is chosen is the decoder. A countdown reaching zero causes a *refetch*;
///    what happens next is whatever the server then says. A client that flipped its own state at
///    20:00:00 would show a reveal that had not happened.
/// 2. **It holds nothing about anybody else.** The `open` payload has no count and no roster to
///    hold, and there is no field on this type where one could be put. That is `docs/14` §3
///    expressed as a shape rather than as a rule to remember.
@Observable @MainActor
final class RoundStore {

    private(set) var state: LoadState<RoundContext> = .idle

    /// The caller's `user_id`, for `RevealStore` to remove itself from the name pool.
    var me: String? { session.user?.userID }

    private let api: APIClient
    private let session: SessionStore
    private let clock: ServerClock
    private let router: Router
    /// Which circle "today's round" means (`docs/01` ADR-011, `E19-01`). Resolved fresh on
    /// every `load()` rather than pinned at construction, so a circle switched underneath this
    /// store (`E19-02`) is picked up on the very next refetch instead of needing a rebuilt store.
    private let circles: CircleStore

    init(api: APIClient, session: SessionStore, clock: ServerClock, router: Router, circles: CircleStore) {
        self.api = api
        self.session = session
        self.clock = clock
        self.router = router
        self.circles = circles
    }

    /// Loads the round and the group, for whichever circle `CircleStore` currently resolves as
    /// active.
    ///
    /// Concurrently, because they are independent GETs and the launch budget is 90 seconds for the
    /// **whole loop** (`docs/00` §7) — two serial round trips at 8pm on cellular is a spinner
    /// nobody asked for. Both are `retry: .twice` idempotent GETs, so a flaky first attempt does
    /// not cost the user the screen.
    ///
    /// A failure keeps whatever is already on screen (`LoadState.apply` → `.stale`), which is the
    /// offline behaviour `docs/08` §10 asks for: the cached phase rendered greyed, with a banner,
    /// rather than a blank screen. A circle list that cannot be resolved at all fails the same
    /// way — there is no second error path for "we don't know which circle yet".
    func load() async {
        if state.value == nil { state = .loading }

        guard let groupID = await circles.resolveActiveID() else {
            state.apply(.failure(circles.state.error ?? .unreadable))
            router.consume(session: session.state, roundIsLoaded: state.value != nil)
            return
        }

        async let round = result(of: .round(groupID))
        async let group = result(of: .group(groupID))
        let outcome: Result<RoundContext, APIError>
        switch (await round, await group) {
        case let (.success(round), .success(group)):
            outcome = .success(RoundContext(round: round, group: group))
        case let (.failure(error), _), let (_, .failure(error)):
            outcome = .failure(error)
        }

        // The caller switched to a **different** circle while this request was in flight
        // (`E19-02` review). `.task(id: loadToken)` cancels the old task on a switch, and
        // cancellation usually reaches these requests before they finish — but not always: a
        // response that had already fully arrived when cancellation was requested completes
        // normally regardless, and applying it here would silently revert the screen to the
        // circle the caller just switched *away* from, with no error and no visible cause.
        // `circles.activeGroupID` is the caller's most recent choice; a mismatch means the
        // circle this request answers for is not the one on screen, and the load that is for
        // the current circle will make its own call here with its own answer.
        guard circles.activeGroupID == groupID else { return }

        state.apply(outcome)

        // `docs/05` §5: a deep link is applied only **after** the round has loaded, so it can
        // never land on a phase that is not current. This is the "roundIsLoaded" half of that.
        router.consume(session: session.state, roundIsLoaded: state.value != nil)
    }

    /// The active circle just changed underneath this store (`E19-02`). Clears to `.loading`
    /// rather than leaving the previous circle's round on screen for the length of the refetch
    /// that follows.
    ///
    /// `load()`'s own "keep the stale value" behaviour (`LoadState.apply` → `.stale`) is right
    /// for an ordinary refresh, where what is being shown does not change — and wrong here,
    /// where it does: a card tapped in that window belongs to the circle just switched **away**
    /// from, and `SubmitStore`/`RevealStore` resolve `circles.resolveActiveID()` fresh at the
    /// moment of the tap, so an action taken against the old round would silently land on the
    /// new circle. Clearing first removes the window rather than racing it.
    func invalidate() {
        state = .loading
    }

    /// The caller has just sealed a song, and the server said so.
    ///
    /// Adopting the response rather than refetching is what makes the sheet dismiss onto an
    /// already-sealed card (`docs/08` §3.2) instead of onto a submit screen that corrects itself a
    /// round trip later. It is **not** a phase decision: the phase is copied, not chosen — see
    /// `RoundDTO.adopting(mySubmission:)`, which cannot change a case even by mistake.
    func adopt(_ submission: SubmissionDTO) {
        guard let context = state.value else { return }
        let updated = RoundContext(
            round: context.round.adopting(mySubmission: submission),
            group: context.group
        )
        state.apply(.success(updated))
    }

    /// Whether the thing the screen is counting to has passed.
    ///
    /// The screen asks on every tick and refetches on `true`; the server decides what that means.
    /// `nil` clock → `false`: an unanchored clock knows nothing, and *"the deadline passed"* is
    /// not the thing to guess (`docs/13` §5 rule 3).
    ///
    /// This one deliberately does **not** consult `RoundScreen`'s held answer. A hold is right
    /// for a rendering decision — it keeps a screen the app was told was correct on screen — and
    /// wrong for this, which is the trigger for a refetch. Firing a request off a remembered
    /// time would be the client acting on a clock it does not have.
    func deadlineHasPassed() -> Bool {
        guard let context = state.value,
              let now = clock.now,
              let deadline = context.deadline(now: now)
        else { return false }
        return now >= deadline
    }

    private func result<R: Decodable & Sendable>(of endpoint: Endpoint<R>) async -> Result<R, APIError> {
        // `APIClient.send` throws `APIError` and nothing else — a typed `throws`, so there is no
        // second `catch` here for an error that cannot arrive.
        do {
            return .success(try await api.send(endpoint))
        } catch {
            return .failure(error)
        }
    }
}
