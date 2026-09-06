import Foundation

/// Owns the typed navigation path and the pending deep link (`docs/13` §4).
///
/// The rule this type exists to keep is `docs/05` §5: *"A deep link **never** shortcuts a
/// phase gate … A deep link is a navigation hint, not an authorization."* So `receive` stores
/// and navigates nothing; `consume` applies the link only once the round has actually loaded,
/// and applies it exactly once — a link consumed twice re-pushes The Record every time the
/// round refetches.
///
/// Note what `consume` is deliberately **not** given: the round's phase. Knowing it would be
/// the standing temptation to gate on it, and the whole point is that the link does not care
/// what phase it is — the server decides, and `RoundScreen` renders whatever it said.
@Observable @MainActor
final class Router {
    /// Two destinations, one modal, no tab bar. An array rather than `NavigationPath` so
    /// "two destinations" is checkable by reading one enum, and so a deep link can replace the
    /// whole stack atomically.
    var path: [Route] = []

    /// Held, not applied. Cleared by `consume`.
    private(set) var pending: DeepLink?

    /// Set from a consumed `.join` link so `JoinOrCreateScreen` (E09-03) can prefill the code.
    private(set) var pendingInviteCode: String?
    /// A recipient-specific invitation (`E20-02`) waiting for its short accept/decline sheet.
    private(set) var pendingInvitationID: String?

    /// Set when a `.round` or `.results` link is consumed; cleared by whoever acts on it
    /// (`E41-02`).
    ///
    /// `pending` cannot answer *"did this arrival come from a notification?"* on its own, because
    /// `consume` clears it the moment the round loads — before any phase screen exists to look.
    /// Both those links mean *today's round*, and the round root is where the tap lands, so this
    /// is the one bit of the tap that has to outlive the consumption: it is what tells the reveal
    /// phase to open the quick pass on the first unnamed card rather than on the flight.
    ///
    /// A flag rather than a second pending link, because it is not a destination — the
    /// destination was already reached. It is the *reason* the app is here.
    private(set) var arrivedFromRoundLink = false

    /// `nil` in, nothing happens — `DeepLink.init?` returns `nil` for anything we do not
    /// recognise, and an unrecognised link must not clear a good pending one.
    func receive(_ link: DeepLink?) {
        guard let link else { return }
        pending = link
    }

    /// Called when the session settles, and again by `RoundStore` (E10) once the round has
    /// loaded. Idempotent: a link that cannot be applied yet stays pending.
    func consume(session: SessionState, roundIsLoaded: Bool) {
        guard let link = pending else { return }

        switch link {
        case .join(let code):
            switch session {
            case .noGroup, .ready:
                // **`.ready` used to drop this on the floor** (`E38-02`), on the argument that
                // *"the server would answer ALREADY_IN_GROUP, and tapping your own invite is
                // not an error worth a toast"*. That was true when a person could hold exactly
                // one circle. Since ADR-011 they may hold three, and a code arriving at a
                // `.ready` session almost always names one they are **not** in —
                // `POST /groups/join` would have accepted it, and `ALREADY_IN_GROUP` is raised
                // only for the circle they are actually in (`memberships_unique_active_pair`).
                // Silently discarding it made every forwarded invite link a dead end.
                //
                // It prefills and stops, in both states. A deep link is a navigation hint, not
                // an authorization (`docs/05` §5): a forwarded message must never put somebody
                // in a circle they did not choose. `.noGroup` lands on `JoinOrCreateScreen`,
                // `.ready` on `JoinCircleSheet`; both read this same code.
                pendingInviteCode = code
                pending = nil
            case .unknown, .signedOut, .noProfile:
                // Keep it. Sign-in and naming come first, and the code is still good after.
                break
            }

        case let .invitation(id):
            switch session {
            case .ready, .noGroup:
                pendingInvitationID = id
                pending = nil
            case .unknown, .signedOut, .noProfile:
                // A direct invitation names an account, so authentication and naming must come
                // first. It remains pending until the server can prove the recipient owns it.
                break
            }

        // `groupID` is not acted on here. By the time `consume` runs, `resolvePendingCircle`
        // has already switched the active circle (or dropped the link if it named one we do
        // not hold) — this switch only decides where in the path a *held* circle's round lands.
        case .round(_), .results(_):
            // Both mean "today's round". Results for today is a branch of RoundScreen, not a
            // pushed destination — modelling `.results` as a push is precisely the mistake
            // that would let a link land on a phase that is not current. Pop to the root and
            // let the server's phase decide what renders (docs/05 §5).
            guard session == .ready, roundIsLoaded else { return }
            path = []
            pending = nil
            arrivedFromRoundLink = true

        case .record(_):
            guard session == .ready, roundIsLoaded else { return }
            path = [.record]
            pending = nil
        }
    }

    /// Called once the arrival has been acted on, so a later foreground is an ordinary one.
    func clearArrivedFromRoundLink() {
        arrivedFromRoundLink = false
    }

    /// Called by the join screen once it has put the code in its field, so returning to the
    /// screen later does not re-prefill a code the user cleared on purpose.
    func clearPendingInviteCode() {
        pendingInviteCode = nil
    }

    func clearPendingInvitation() {
        pendingInvitationID = nil
    }

    /// A person's own tap in the switcher (`E19-02`) discards whatever a deep link was still
    /// asking for (`E19-03` review). `resolvePendingCircle` switches the active circle as soon
    /// as a pending link's is valid, but does not clear `pending` itself — that link is still
    /// "owed" its navigation, consumed later by `consume()`. Left alone, a manual switch to a
    /// **third** circle while that fetch is still in flight would find the link still pending on
    /// the very next load and silently switch back to it, undoing the choice just made. An
    /// explicit switch is not a hint; it is the last word, and it says so here.
    func clearPending() {
        pending = nil
    }

    /// A pending link may name a specific circle (`docs/05` §5's circle prefix, `E19-01`) —
    /// switching to it before landing is `E19-03`'s job, and this is where that happens.
    /// `RoundStore.load()` calls this before it resolves which circle "today's round" means, so
    /// a switch (if any) is answered by the very fetch already under way rather than needing a
    /// second one.
    ///
    /// A link naming a circle the caller does not hold — left, or never joined — **fails
    /// gracefully**: dropped here, the same "do nothing rather than guess" rule `DeepLink.init?`
    /// and `PushRouter.link(from:)` already apply to a link this app does not recognise at all.
    /// A bare link (`groupID == nil`) and a link already naming the active circle both no-op,
    /// since neither needs a switch.
    func resolvePendingCircle(against circles: CircleStore) {
        guard let groupID = pending?.groupID else { return }
        guard circles.circles.contains(where: { $0.id == groupID }) else {
            pending = nil
            return
        }
        if groupID != circles.activeGroupID {
            circles.select(groupID)
        }
    }
}
