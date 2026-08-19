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
            case .noGroup:
                pendingInviteCode = code
                pending = nil
            case .ready:
                // docs/04 §3: the server would answer ALREADY_IN_GROUP. Tapping your own
                // invite is not an error worth a toast, so drop it silently.
                pending = nil
            case .unknown, .signedOut, .noProfile:
                // Keep it. Sign-in and naming come first, and the code is still good after.
                break
            }

        // `groupID` is not acted on here — switching to the named circle before landing is
        // `E19-03`'s job. This slice only makes sure a link that names one still parses and
        // still reaches this switch rather than being dropped.
        case .round(_), .results(_):
            // Both mean "today's round". Results for today is a branch of RoundScreen, not a
            // pushed destination — modelling `.results` as a push is precisely the mistake
            // that would let a link land on a phase that is not current. Pop to the root and
            // let the server's phase decide what renders (docs/05 §5).
            guard session == .ready, roundIsLoaded else { return }
            path = []
            pending = nil

        case .record(_):
            guard session == .ready, roundIsLoaded else { return }
            path = [.record]
            pending = nil
        }
    }

    /// Called by the join screen once it has put the code in its field, so returning to the
    /// screen later does not re-prefill a code the user cleared on purpose.
    func clearPendingInviteCode() {
        pendingInviteCode = nil
    }
}
