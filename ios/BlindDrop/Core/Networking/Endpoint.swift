import Foundation

/// One call in `docs/04`, typed by what it returns.
///
/// Every endpoint the app has is a `static` on this type, so the set of requests the client can
/// make is a list somebody can read in one sitting — and a screen cannot invent a URL. That is
/// not tidiness: `docs/01` ADR-011 makes every group-scoped route an authorization surface —
/// the caller must belong to the named circle — and a codebase where paths were built at call
/// sites is one where somebody eventually builds `/groups/\(someOtherUsersId)/record` by hand.
/// `scoped(_:_:_:)` below is the one place a `:group_id` segment is spliced in.
struct Endpoint<Response: Sendable>: Sendable {

    enum Method: String, Sendable {
        case get = "GET"
        case put = "PUT"
        case post = "POST"
        case patch = "PATCH"
        case delete = "DELETE"
    }

    let method: Method
    /// The path under the functions base URL, e.g. `/rounds/{group_id}/current`.
    let path: String
    let query: [URLQueryItem]
    /// Encoded lazily so the endpoint stays `Sendable` without an existential, and so an
    /// encoding failure surfaces at send time as an error rather than as a `try!` at build time.
    let body: (@Sendable () throws -> Data)?
    let retry: RetryPolicy

    init(
        _ method: Method,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (@Sendable () throws -> Data)? = nil,
        retry: RetryPolicy = .none
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.retry = retry
    }

}

/// How many times a failed attempt may be repeated, and how long to wait first.
///
/// `docs/13` §3: idempotent GETs retry twice with 200ms/600ms backoff; the two idempotent PUTs
/// retry once; **nothing else retries.** A `POST /groups/join` that retried could spend two of
/// a user's ten hourly attempts on one tap, and a retried submission is only safe because
/// `PUT` is an upsert on `(round_id, user_id)` — which is a property of those two routes, not
/// of the verb.
struct RetryPolicy: Sendable {
    let backoff: [Duration]

    static let none = RetryPolicy(backoff: [])
    /// The two idempotent PUTs (`docs/04` §4).
    static let once = RetryPolicy(backoff: [.milliseconds(200)])
    /// Idempotent GETs.
    static let twice = RetryPolicy(backoff: [.milliseconds(200), .milliseconds(600)])
}

/// A request body from any `Encodable` value, encoded when the request is actually built.
private func json(_ value: some Encodable & Sendable) -> @Sendable () throws -> Data {
    { try JSONEncoder().encode(value) }
}

// MARK: - Request bodies
//
// One type per body `docs/04` documents, at file scope so the endpoint factories stay one
// line each. The property names are the wire's, snake case included: these types exist to be
// the JSON, and a `CodingKeys` block on a two-field struct would be ceremony around nothing.

private struct DisplayNameBody: Encodable, Sendable { let display_name: String }
private struct DeviceBody: Encodable, Sendable { let apns_token: String; let environment: String }
private struct DeviceDeleteBody: Encodable, Sendable { let apns_token: String }
private struct DeleteAccountBody: Encodable, Sendable { let apple_authorization_code: String }
private struct CreateGroupBody: Encodable, Sendable {
    let name: String
    let timezone: String
    let reveal_hour: Int?
}
private struct JoinBody: Encodable, Sendable { let invite_code: String }
private struct PatchGroupBody: Encodable, Sendable {
    let name: String?
    let reveal_hour: Int?
    let cue_cadence: Int?
}
private struct MemberRoleBody: Encodable, Sendable { let role: String }
private struct InvitePersonBody: Encodable, Sendable { let user_id: String }
private struct GuessesBody: Encodable, Sendable { let assignments: [GuessAssignment] }

/// Endpoints that answer `204` and have no payload to decode.
struct NoContent: Decodable, Sendable, Equatable {}

/// Builds a group-scoped path — `/groups/{id}…` or `/rounds/{id}/current…` — from a group id
/// that has already been resolved. The one place `docs/01` ADR-011's `:group_id` segment is
/// spliced into a path, so every group-scoped factory below reads as "this route, for this
/// circle" rather than re-deriving the shape.
private func scoped(_ base: String, _ groupID: String, _ suffix: String = "") -> String {
    "\(base)/\(groupID)\(suffix)"
}

// MARK: - docs/04 §2 — identity

extension Endpoint {
    static var me: Endpoint<UserDTO> { .init(.get, "/me", retry: .twice) }

    static func setDisplayName(_ name: String) -> Endpoint<UserDTO> {
        .init(.put, "/me", body: json(DisplayNameBody(display_name: name)))
    }

    /// `DELETE /me` — 204. Deletes the principal and the device tokens, ends the membership,
    /// and anonymises the historical profile to *Former member*. Submissions and guesses stay,
    /// because other people's scores and The Record depend on them (`docs/04` §2).
    static func deleteAccount(authorizationCode: String? = nil) -> Endpoint<NoContent> {
        let body = authorizationCode.map {
            json(DeleteAccountBody(apple_authorization_code: $0))
        }
        return .init(.delete, "/me", body: body)
    }

    /// `POST /devices` — 204, always, whether the token was new, moved between users, or
    /// unchanged. There is no read side, so registering tells the caller nothing.
    static func registerDevice(token: String, environment: String) -> Endpoint<NoContent> {
        .init(.post, "/devices", body: json(DeviceBody(apns_token: token, environment: environment)))
    }

    static func unregisterDevice(token: String) -> Endpoint<NoContent> {
        .init(.delete, "/devices", body: json(DeviceDeleteBody(apns_token: token)))
    }
}

// MARK: - docs/04 §3 — groups

extension Endpoint {
    static func createGroup(name: String, timezone: String, revealHour: Int?) -> Endpoint<GroupDTO> {
        .init(
            .post, "/groups",
            body: json(CreateGroupBody(name: name, timezone: timezone, reveal_hour: revealHour))
        )
    }

    /// `POST /groups/join`. **Never retried**: it is rate-limited at ten an hour precisely
    /// because it is the invite-code brute-force surface (`docs/04` §8), and an automatic
    /// second attempt spends somebody's quota for them.
    static func joinGroup(inviteCode: String) -> Endpoint<GroupDTO> {
        .init(.post, "/groups/join", body: json(JoinBody(invite_code: inviteCode)))
    }

    /// `GET /groups` — one row per circle the caller holds (`docs/04` §3, `E18-02`). The
    /// switcher's entire data source, and `CircleStore`'s.
    static var circles: Endpoint<CirclesDTO> { .init(.get, "/groups", retry: .twice) }

    /// `GET /groups/{group_id}` — a named circle (`docs/01` ADR-011). No `current` form: every
    /// caller has already resolved a group id through `CircleStore` before it reaches here.
    static func group(_ groupID: String) -> Endpoint<GroupDTO> {
        .init(.get, scoped("/groups", groupID), retry: .twice)
    }

    static func updateGroup(
        _ groupID: String, name: String?, revealHour: Int?, cueCadence: Int? = nil
    ) -> Endpoint<GroupDTO> {
        .init(
            .patch, scoped("/groups", groupID),
            body: json(PatchGroupBody(name: name, reveal_hour: revealHour, cue_cadence: cueCadence))
        )
    }

    static func leaveGroup(_ groupID: String) -> Endpoint<NoContent> {
        .init(.post, scoped("/groups", groupID, "/leave"))
    }

    static func updateMemberRole(_ userID: String, in groupID: String, role: String) -> Endpoint<GroupDTO> {
        .init(
            .patch,
            scoped("/groups", groupID, "/members/\(userID)"),
            body: json(MemberRoleBody(role: role))
        )
    }

    static func removeMember(_ userID: String, from groupID: String) -> Endpoint<NoContent> {
        .init(.delete, scoped("/groups", groupID, "/members/\(userID)"))
    }

    static func standings(_ groupID: String) -> Endpoint<StandingsDTO> {
        .init(.get, scoped("/groups", groupID, "/standings"), retry: .twice)
    }

    static func memberProfile(_ userID: String, in groupID: String) -> Endpoint<MemberProfileDTO> {
        .init(.get, scoped("/groups", groupID, "/members/\(userID)/profile"), retry: .twice)
    }

    static func insights(in groupID: String) -> Endpoint<InsightsDTO> {
        .init(.get, scoped("/groups", groupID, "/insights"), retry: .twice)
    }

    static var peopleYouPlayedWith: Endpoint<KnownPeopleDTO> {
        .init(.get, "/groups/people-you-played-with", retry: .twice)
    }

    static func invitePerson(_ userID: String, to groupID: String) -> Endpoint<InvitationDTO> {
        .init(.post, scoped("/groups", groupID, "/invitations"), body: json(InvitePersonBody(user_id: userID)))
    }

    /// The invitations **this circle has sent** and nobody has answered yet (`E38-03` fix).
    ///
    /// Not to be confused with `invitations` below, which is the caller's own *received* ones.
    /// Two segments against that route's one, on the server as well as here, so the two cannot
    /// be reached by accident from the other's path.
    static func sentInvitations(for groupID: String) -> Endpoint<SentInvitationsDTO> {
        .init(.get, scoped("/groups", groupID, "/invitations"), retry: .twice)
    }

    static var invitations: Endpoint<InvitationsDTO> {
        .init(.get, "/groups/invitations", retry: .twice)
    }

    static func acceptInvitation(_ invitationID: String) -> Endpoint<GroupDTO> {
        .init(.post, "/groups/invitations/\(invitationID)/accept")
    }

    static func declineInvitation(_ invitationID: String) -> Endpoint<NoContent> {
        .init(.post, "/groups/invitations/\(invitationID)/decline")
    }
}

// MARK: - docs/04 §4 — the round

extension Endpoint {
    /// `GET /rounds/{group_id}/current` — today's round, for a named circle.
    static func round(_ groupID: String) -> Endpoint<RoundDTO> {
        .init(.get, scoped("/rounds", groupID, "/current"), retry: .twice)
    }

    /// `PUT /rounds/{group_id}/current/submission`. Idempotent by design — the same body twice
    /// produces one row and the same response — which is what makes retrying it safe
    /// (`docs/04` §4).
    static func seal(_ groupID: String, _ input: SubmissionInput) -> Endpoint<SubmissionDTO> {
        .init(.put, scoped("/rounds", groupID, "/current/submission"), body: json(input), retry: .once)
    }

    /// `PUT /rounds/{group_id}/current/guesses` — a whole-sheet upsert; the server diffs. A
    /// card sent with `null` is an explicit clear; a card left out is untouched (`docs/04` §4).
    static func saveGuesses(_ groupID: String, _ assignments: [GuessAssignment]) -> Endpoint<GuessSheetDTO> {
        .init(
            .put, scoped("/rounds", groupID, "/current/guesses"),
            body: json(GuessesBody(assignments: assignments)),
            retry: .once
        )
    }

    /// `GET /rounds/{round_id}/results` — the one round-scoped route that is not group-scoped
    /// in its path: the server resolves the round's own circle and proves membership of that
    /// (`docs/04` §4).
    static func results(roundID: String) -> Endpoint<ResultsDTO> {
        .init(.get, "/rounds/\(roundID)/results", retry: .twice)
    }
}

/// The three ways to name a song (`docs/04` §4). Exactly one is sent; the type is a `enum` so
/// "one of" is not a comment on a struct with three optionals.
enum SubmissionInput: Encodable, Sendable, Equatable {
    case appleMusicID(String)
    case spotifyURL(String)
    case isrc(String)

    enum CodingKeys: String, CodingKey {
        case appleMusicID = "apple_music_id"
        case spotifyURL = "spotify_url"
        case isrc
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .appleMusicID(value): try container.encode(value, forKey: .appleMusicID)
        case let .spotifyURL(value): try container.encode(value, forKey: .spotifyURL)
        case let .isrc(value): try container.encode(value, forKey: .isrc)
        }
    }
}

/// One line of a guess sheet on the way out. `guessedUserID` is **explicitly** `null` to clear
/// a card, which is why it is encoded even when nil (`docs/04` §4 rule 7).
struct GuessAssignment: Encodable, Sendable, Equatable {
    let cardNumber: Int
    let guessedUserID: String?

    init(cardNumber: Int, guessedUserID: String?) {
        self.cardNumber = cardNumber
        self.guessedUserID = guessedUserID
    }

    enum CodingKeys: String, CodingKey {
        case cardNumber = "card_no"
        case guessedUserID = "guessed_user_id"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cardNumber, forKey: .cardNumber)
        try container.encode(guessedUserID, forKey: .guessedUserID)
    }
}

// MARK: - docs/04 §5 — The Record

extension Endpoint {
    static func record(
        _ groupID: String,
        member: String? = nil,
        cursor: String? = nil,
        limit: Int? = nil
    ) -> Endpoint<RecordDTO> {
        var query: [URLQueryItem] = []
        if let member { query.append(URLQueryItem(name: "member", value: member)) }
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        return .init(.get, scoped("/groups", groupID, "/record"), query: query, retry: .twice)
    }

    static func export(_ groupID: String, _ service: ExportService) -> Endpoint<ExportDTO> {
        .init(
            .get, scoped("/groups", groupID, "/record/export"),
            query: [URLQueryItem(name: "service", value: service.rawValue)],
            retry: .twice
        )
    }
}

// MARK: - docs/04 §6 — tracks

extension Endpoint {
    /// Search. Retried like any other GET, and the budget that matters to it is AC-10's 400ms
    /// — which is a matter for the screen's debounce, not for this layer.
    static func search(_ query: String, limit: Int = 20) -> Endpoint<SearchResultsDTO> {
        .init(
            .get, "/tracks/search",
            query: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "limit", value: String(limit)),
            ],
            retry: .twice
        )
    }

    static func resolve(_ input: SubmissionInput) -> Endpoint<TrackDTO> {
        .init(.post, "/tracks/resolve", body: json(input))
    }
}
