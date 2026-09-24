import Foundation

/// Every failure the app can show a person, and nothing else.
///
/// The seventeen server codes are `docs/04` §1 verbatim; the two below them are the client's
/// own, because "the request never left the phone" and "the server said no" are different
/// facts and the copy deck gives them different words (`docs/11`).
///
/// **A raw `URLError` or a `DecodingError` never reaches a view.** Everything is mapped here,
/// which is what makes `error.copy` — and therefore every failure state in the app — a
/// finite, reviewable list rather than whatever Foundation happened to say.
enum APIError: Error, Equatable, Sendable {
    /// 401. The token is missing, invalid, or was rejected after one refresh.
    case unauthenticated
    /// 409. Authenticated, but no display name yet — the client routes to onboarding step 2.
    case noProfile
    /// 409. Not in a group yet.
    case noGroup
    /// 404. An invite code, a round, or a resource that does not exist. Deliberately the same
    /// answer as "exists but is not yours" (`docs/14` §4).
    case notFound
    /// 409. The action is not allowed in the round's current state.
    ///
    /// The associated state is **all** the server sends, and all it may send: `docs/04` §1 is
    /// explicit that a phase error never carries "3 of 8 submitted, wait for reveal".
    case wrongPhase(state: RoundState?)
    /// 403. Guessing without having dropped a song.
    case notASubmitter
    /// 403. Joined after `reveals_at`, so this round is not theirs to play.
    case joinedLate
    /// 409. Fewer than three drops; nothing was revealed.
    case roundVoided
    /// 409. `BD003` — the same track, already dropped today, in any circle the caller is in
    /// (`E18-03`). Its own case rather than a generic refusal because it is the one seal failure
    /// that **retrying cannot fix**: the user has to pick a different song, and a screen saying
    /// *"Try again"* sends them round a loop with no exit.
    case trackAlreadyUsed
    /// 400. A validation failure, naming the field where the server named one — and never the
    /// offending value.
    case invalidInput(field: String?)
    /// 409. ADR-005: one group per user.
    case alreadyInGroup
    /// 409. The caller already sent this person a live direct invitation.
    case alreadyInvited
    /// 409. ADR-011: no more than three active groups.
    case circleLimitReached
    /// 403. A group settings change by somebody who is not the admin.
    case notAdmin
    /// 409. The caller is the circle's only admin and other active members remain —
    /// `E21-01`'s open question. Unreachable from this app's own UI today (there is no promote
    /// or remove yet, `E21-02`), but enforced server-side regardless.
    case lastAdminMustTransfer
    /// 429, with the `Retry-After` header where the server sent one.
    case rateLimited(retryAfter: TimeInterval?)
    /// 502. Apple Music or Spotify is not answering.
    case upstreamUnavailable
    /// 409. Account deletion needs a fresh Sign in with Apple authorization code.
    case reauthenticationRequired
    /// 403. The fresh Apple credential does not belong to the signed-in account.
    case reauthenticationFailed
    /// 502. Apple's identity service could not complete deletion reauthentication.
    case authProviderUnavailable
    /// 500. Carries no detail by design — the detail is in the server log.
    case server

    /// The request never reached the server: no connectivity, a timeout, a dropped
    /// connection. `waitsForConnectivity` is off (`docs/13` §3), so this arrives quickly and
    /// honestly instead of forty seconds later.
    case offline
    /// A response that is not the envelope this app speaks: a proxy's HTML error page, a
    /// truncated body, a field whose type changed. Bundled into one case on purpose — the
    /// user can do exactly one thing about all of them, and a decoding error's `debugDescription`
    /// is not a sentence anybody should read.
    case unreadable
}

extension APIError {

    /// The server code this case came from, or `nil` for the two client-side ones.
    var serverCode: String? {
        switch self {
        case .unauthenticated: "UNAUTHENTICATED"
        case .noProfile: "NO_PROFILE"
        case .noGroup: "NO_GROUP"
        case .notFound: "NOT_FOUND"
        case .wrongPhase: "WRONG_PHASE"
        case .notASubmitter: "NOT_A_SUBMITTER"
        case .joinedLate: "JOINED_LATE"
        case .roundVoided: "ROUND_VOIDED"
        case .trackAlreadyUsed: "TRACK_ALREADY_USED"
        case .invalidInput: "INVALID_INPUT"
        case .alreadyInGroup: "ALREADY_IN_GROUP"
        case .alreadyInvited: "ALREADY_INVITED"
        case .circleLimitReached: "CIRCLE_LIMIT_REACHED"
        case .notAdmin: "NOT_ADMIN"
        case .lastAdminMustTransfer: "LAST_ADMIN_MUST_TRANSFER"
        case .rateLimited: "RATE_LIMITED"
        case .upstreamUnavailable: "UPSTREAM_UNAVAILABLE"
        case .reauthenticationRequired: "REAUTHENTICATION_REQUIRED"
        case .reauthenticationFailed: "REAUTHENTICATION_FAILED"
        case .authProviderUnavailable: "AUTH_PROVIDER_UNAVAILABLE"
        case .server: "INTERNAL"
        case .offline, .unreadable: nil
        }
    }

    /// The `docs/11` key whose string the UI shows. The key, not the string: the words live in
    /// `Localizable.strings` (E09) and this layer must not be a second place they are written.
    var copyKey: String {
        switch self {
        case .unauthenticated: "error.unauthenticated"
        case .noProfile: "error.noprofile"
        case .noGroup: "error.nogroup"
        case .notFound: "error.notfound"
        case .wrongPhase: "error.wrongphase"
        case .notASubmitter: "error.notsubmitter"
        case .joinedLate: "error.joinedlate"
        case .roundVoided: "error.roundvoided"
        case .trackAlreadyUsed: "error.trackalreadyused"
        case .invalidInput: "error.invalidinput"
        case .alreadyInGroup: "error.alreadyingroup"
        case .alreadyInvited: "error.alreadyinvited"
        case .circleLimitReached: "error.circlelimitreached"
        case .notAdmin: "error.notadmin"
        case .lastAdminMustTransfer: "error.lastadmin"
        case .rateLimited: "error.ratelimited"
        case .upstreamUnavailable: "error.upstream"
        case .reauthenticationRequired, .reauthenticationFailed: "settings.delete.reauth"
        case .authProviderUnavailable: "error.authprovider"
        case .server, .unreadable: "error.generic"
        case .offline: "error.offline"
        }
    }

    /// Builds the error for a server code, with whatever detail that code is allowed to carry.
    ///
    /// An unrecognised code becomes `.server` rather than crashing or inventing a case: a
    /// deployed app meeting a newer server must degrade to "that didn't work", not to a fatal
    /// error, and `NetworkingTests` pins every code the contract does define.
    init(code: String, state: RoundState? = nil, field: String? = nil, retryAfter: TimeInterval? = nil) {
        switch code {
        case "UNAUTHENTICATED": self = .unauthenticated
        case "NO_PROFILE": self = .noProfile
        case "NO_GROUP": self = .noGroup
        case "NOT_FOUND": self = .notFound
        case "WRONG_PHASE": self = .wrongPhase(state: state)
        case "NOT_A_SUBMITTER": self = .notASubmitter
        case "JOINED_LATE": self = .joinedLate
        case "ROUND_VOIDED": self = .roundVoided
        case "TRACK_ALREADY_USED": self = .trackAlreadyUsed
        case "INVALID_INPUT": self = .invalidInput(field: field)
        case "ALREADY_IN_GROUP": self = .alreadyInGroup
        case "ALREADY_INVITED": self = .alreadyInvited
        case "CIRCLE_LIMIT_REACHED": self = .circleLimitReached
        case "NOT_ADMIN": self = .notAdmin
        case "LAST_ADMIN_MUST_TRANSFER": self = .lastAdminMustTransfer
        case "RATE_LIMITED": self = .rateLimited(retryAfter: retryAfter)
        case "UPSTREAM_UNAVAILABLE": self = .upstreamUnavailable
        case "REAUTHENTICATION_REQUIRED": self = .reauthenticationRequired
        case "REAUTHENTICATION_FAILED": self = .reauthenticationFailed
        case "AUTH_PROVIDER_UNAVAILABLE": self = .authProviderUnavailable
        default: self = .server
        }
    }

    /// Whether sending the same request again could plausibly produce a different answer.
    ///
    /// Only transport failures and the server's own 5xx. A 409 is not a flake: retrying a
    /// `WRONG_PHASE` produces another `WRONG_PHASE` and spends a person's battery doing it.
    /// `RATE_LIMITED` is excluded on purpose — the answer to being throttled is to stop, and
    /// the retry that "helps" is the one that makes the window longer.
    var isWorthRetrying: Bool {
        switch self {
        case .offline, .server: true
        default: false
        }
    }
}
