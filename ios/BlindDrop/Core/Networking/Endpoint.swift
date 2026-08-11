import Foundation

/// One call in `docs/04`, typed by what it returns.
///
/// Every endpoint the app has is a `static` on this type, so the set of requests the client can
/// make is a list somebody can read in one sitting — and a screen cannot invent a URL. That is
/// not tidiness: ADR-005 says no route takes a group id, and a codebase where paths are built
/// at call sites is one where somebody eventually builds `/groups/\(id)/record`.
struct Endpoint<Response: Sendable>: Sendable {

    enum Method: String, Sendable {
        case get = "GET"
        case put = "PUT"
        case post = "POST"
        case patch = "PATCH"
        case delete = "DELETE"
    }

    let method: Method
    /// The path under the functions base URL, e.g. `/rounds/current`.
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
private struct CreateGroupBody: Encodable, Sendable {
    let name: String
    let timezone: String
    let reveal_hour: Int?
}
private struct JoinBody: Encodable, Sendable { let invite_code: String }
private struct PatchGroupBody: Encodable, Sendable { let name: String?; let reveal_hour: Int? }
private struct GuessesBody: Encodable, Sendable { let assignments: [GuessAssignment] }

/// Endpoints that answer `204` and have no payload to decode.
struct NoContent: Decodable, Sendable, Equatable {}

// MARK: - docs/04 §2 — identity

extension Endpoint {
    static var me: Endpoint<UserDTO> { .init(.get, "/me", retry: .twice) }

    static func setDisplayName(_ name: String) -> Endpoint<UserDTO> {
        .init(.put, "/me", body: json(DisplayNameBody(display_name: name)))
    }

    /// `DELETE /me` — 204. Deletes the principal and the device tokens, ends the membership,
    /// and anonymises the historical profile to *Former member*. Submissions and guesses stay,
    /// because other people's scores and The Record depend on them (`docs/04` §2).
    static var deleteAccount: Endpoint<NoContent> { .init(.delete, "/me") }

    /// `POST /devices` — 204, always, whether the token was new, moved between users, or
    /// unchanged. There is no read side, so registering tells the caller nothing.
    static func registerDevice(token: String, environment: String) -> Endpoint<NoContent> {
        .init(.post, "/devices", body: json(DeviceBody(apns_token: token, environment: environment)))
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

    static var currentGroup: Endpoint<GroupDTO> { .init(.get, "/groups/current", retry: .twice) }

    static func updateGroup(name: String?, revealHour: Int?) -> Endpoint<GroupPatchDTO> {
        .init(.patch, "/groups/current", body: json(PatchGroupBody(name: name, reveal_hour: revealHour)))
    }

    static var leaveGroup: Endpoint<NoContent> { .init(.post, "/groups/current/leave") }

    static var standings: Endpoint<StandingsDTO> {
        .init(.get, "/groups/current/standings", retry: .twice)
    }
}

// MARK: - docs/04 §4 — the round

extension Endpoint {
    static var currentRound: Endpoint<RoundDTO> { .init(.get, "/rounds/current", retry: .twice) }

    /// `PUT /rounds/current/submission`. Idempotent by design — the same body twice produces
    /// one row and the same response — which is what makes retrying it safe (`docs/04` §4).
    static func seal(_ input: SubmissionInput) -> Endpoint<SubmissionDTO> {
        .init(.put, "/rounds/current/submission", body: json(input), retry: .once)
    }

    /// `PUT /rounds/current/guesses` — a whole-sheet upsert; the server diffs. A card sent with
    /// `null` is an explicit clear; a card left out is untouched (`docs/04` §4).
    static func saveGuesses(_ assignments: [GuessAssignment]) -> Endpoint<GuessSheetDTO> {
        .init(
            .put, "/rounds/current/guesses",
            body: json(GuessesBody(assignments: assignments)),
            retry: .once
        )
    }

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
    static func record(member: String? = nil, cursor: String? = nil, limit: Int? = nil) -> Endpoint<RecordDTO> {
        var query: [URLQueryItem] = []
        if let member { query.append(URLQueryItem(name: "member", value: member)) }
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        return .init(.get, "/groups/current/record", query: query, retry: .twice)
    }

    static func export(_ service: ExportService) -> Endpoint<ExportDTO> {
        .init(
            .get, "/groups/current/record/export",
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
