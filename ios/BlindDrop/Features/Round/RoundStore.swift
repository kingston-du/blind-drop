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

    /// *"Monday 10 August"* (`docs/08` §2), in the group's timezone.
    var dateHeadline: String? {
        calendar.headline(localDate: round.localDate)
    }

    /// The group's own clock, which every date and hour on these screens is written in.
    var calendar: GroupCalendar { GroupCalendar(timezone: group.timezone) }

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
    /// - Parameter now: the clock's reading, or `nil` while it has no anchor. The *dark hours*
    ///   branch is the only one that needs it, and with no anchor the screen counts to the reveal
    ///   — which is what it will do a moment later anyway, and what `--:--:--` is showing
    ///   meanwhile (`docs/13` §5 rule 3).
    func deadline(now: Date?) -> Date {
        switch round.phase {
        case .open:
            if let now, now < round.opensAt { return round.opensAt }
            return round.revealsAt
        case .revealed:
            return round.scoresAt
        case .voided, .scored:
            return calendar.nextDay(round.opensAt)
        }
    }

    /// Whether the round has not opened yet — `docs/08` §2's dark hours, where the button is
    /// disabled and the copy names the next opening.
    func isBeforeOpen(now: Date?) -> Bool {
        guard let now else { return false }
        return now < round.opensAt
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

    init(api: APIClient, session: SessionStore, clock: ServerClock, router: Router) {
        self.api = api
        self.session = session
        self.clock = clock
        self.router = router
    }

    /// Loads the round and the group.
    ///
    /// Concurrently, because they are independent GETs and the launch budget is 90 seconds for the
    /// **whole loop** (`docs/00` §7) — two serial round trips at 8pm on cellular is a spinner
    /// nobody asked for. Both are `retry: .twice` idempotent GETs, so a flaky first attempt does
    /// not cost the user the screen.
    ///
    /// A failure keeps whatever is already on screen (`LoadState.apply` → `.stale`), which is the
    /// offline behaviour `docs/08` §10 asks for: the cached phase rendered greyed, with a banner,
    /// rather than a blank screen.
    func load() async {
        if state.value == nil { state = .loading }

        async let round = result(of: .currentRound)
        async let group = result(of: .currentGroup)

        switch (await round, await group) {
        case let (.success(round), .success(group)):
            state.apply(.success(RoundContext(round: round, group: group)))
        case let (.failure(error), _), let (_, .failure(error)):
            state.apply(.failure(error))
        }

        // `docs/05` §5: a deep link is applied only **after** the round has loaded, so it can
        // never land on a phase that is not current. This is the "roundIsLoaded" half of that.
        router.consume(session: session.state, roundIsLoaded: state.value != nil)
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
    func deadlineHasPassed() -> Bool {
        guard let context = state.value, let now = clock.now else { return false }
        return now >= context.deadline(now: now)
    }

    private func result<R: Decodable & Sendable>(of endpoint: Endpoint<R>) async -> Result<R, APIError> {
        do {
            return .success(try await api.send(endpoint))
        } catch let error as APIError {
            return .failure(error)
        } catch {
            return .failure(.unreadable)
        }
    }
}
