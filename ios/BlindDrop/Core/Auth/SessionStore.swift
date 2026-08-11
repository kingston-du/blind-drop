import Foundation

/// What the **server** has told us about the caller. Every transition is server-declared;
/// none of them is inferred client-side (`docs/13` §4, `docs/04` §1–§2).
///
/// | Server says | state |
/// |---|---|
/// | `401 UNAUTHENTICATED` | `.signedOut` |
/// | `409 NO_PROFILE` | `.noProfile` |
/// | `409 NO_GROUP`, or `GET /me` → `has_group: false` | `.noGroup` |
/// | `GET /me` → `has_group: true` | `.ready` |
///
/// `.unknown` is the fifth case and is not a deviation from `docs/13` §4's four: it is
/// `docs/13` §5 rule 3 — "before the first successful response the app does not know" —
/// applied to identity as well as to time. It renders nothing rather than guessing
/// `.signedOut`, because guessing wrong shows a sign-in wall to a signed-in user.
enum SessionState: Equatable, Sendable {
    case unknown
    case signedOut
    case noProfile
    /// The caller's profile exists but they are in no group yet. E08-05's `UserDTO` will be
    /// attached to `.noGroup`/`.ready` when the DTO layer lands; E08-01 needs only the branch.
    case noGroup
    case ready
}

/// Owns the Supabase session (`docs/13` §1). The only place `SessionState` is assigned.
///
/// E08-05 gives it an `APIClient` so `load()` can call `GET /me`; E09-01 gives it Sign in with
/// Apple, refresh, and sign-out. Until then `load()` deliberately leaves the state at
/// `.unknown` rather than asserting `.signedOut` — an unimplemented call is not evidence about
/// the user.
@Observable @MainActor
final class SessionStore {
    private(set) var state: SessionState = .unknown

    func load() async {}
}
