import Foundation
import Testing
@testable import BlindDrop

/// `docs/13` §3 and `docs/04` §1–6: the wire, asserted against the fixture payloads that are
/// the contract verbatim (`ios/Fixtures/README.md`).
///
/// Nothing here talks to a network. A stub `URLProtocol` answers every request, which is what
/// makes "a GET retries twice and a POST does not" a countable fact rather than a claim, and
/// what lets the 401 path be exercised without a token to revoke.
///
/// The payload tests decode `ios/Fixtures/payloads/*.json` from disk rather than embedding
/// copies. A second copy of a contract is a second thing to keep in step, and the whole reason
/// those files exist is that there is exactly one.
///
/// `.serialized` because the stub is process-wide: one queue of canned responses and one list
/// of requests, which is what makes counting attempts possible at all. Tests that armed it
/// concurrently would answer each other's requests.
@Suite(.serialized) struct NetworkingTests {

    // MARK: - The stub

    /// Answers a request from a queue of canned responses and records what it was asked.
    final class Stub: URLProtocol, @unchecked Sendable {
        struct Response: Sendable {
            var status: Int = 200
            var body: Data = Data()
            var headers: [String: String] = [:]
            /// A transport failure — no response at all, the way a dead network behaves.
            var failure: URLError?
        }

        nonisolated(unsafe) private static var queue: [Response] = []
        nonisolated(unsafe) private static var last: Response = Response()
        nonisolated(unsafe) private(set) static var requests: [URLRequest] = []
        private static let lock = NSLock()

        /// Arms the stub. The last response repeats, so a retry test can say "fail twice, then
        /// succeed" and a header test does not have to count.
        static func arm(_ responses: [Response]) {
            lock.lock(); defer { lock.unlock() }
            queue = responses
            last = responses.last ?? Response()
            requests = []
        }

        static func next() -> Response {
            lock.lock(); defer { lock.unlock() }
            return queue.isEmpty ? last : queue.removeFirst()
        }

        static func record(_ request: URLRequest) {
            lock.lock(); defer { lock.unlock() }
            requests.append(request)
        }

        static var requestCount: Int {
            lock.lock(); defer { lock.unlock() }
            return requests.count
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Stub.record(request)
            let response = Stub.next()
            if let failure = response.failure {
                client?.urlProtocol(self, didFailWithError: failure)
                return
            }
            let http = HTTPURLResponse(
                url: request.url!,
                statusCode: response.status,
                httpVersion: "HTTP/1.1",
                headerFields: response.headers
            )!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response.body)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    /// A client wired to the stub, with a real clock and a real session store.
    ///
    /// The store's two dependencies are the doubles from `AuthTests`: a network these tests do
    /// not want and a keychain they must not touch. It has no refresh token, which is what
    /// makes `a401RefreshesOnceAndThenEndsTheSession` reach the end of the session.
    @MainActor
    private static func makeClient() -> (APIClient, ServerClock, SessionStore) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        let clock = ServerClock()
        let session = SessionStore(auth: FakeAuth(), secrets: MemorySecrets())
        let client = APIClient(
            baseURL: URL(string: "https://fixture.test/functions/v1")!,
            clock: clock,
            session: session,
            transport: APIClient.makeTransport(configuration)
        )
        return (client, clock, session)
    }

    /// An envelope around a fixture payload, the way the server sends it.
    private static func envelope(_ payload: Data, serverNow: String = "2026-08-10T18:42:07Z") -> Data {
        var body = Data(#"{"server_now":"\#(serverNow)","data":"#.utf8)
        body.append(payload)
        body.append(Data("}".utf8))
        return body
    }

    private static func failure(_ code: String, extra: String = "") -> Data {
        Data(#"{"server_now":"2026-08-10T18:42:07Z","error":{"code":"\#(code)","message":"x"\#(extra)}}"#.utf8)
    }

    /// The fixture payloads, read from the repo. `#filePath` rather than a bundle resource:
    /// these files belong to `ios/Fixtures`, which is the fixture *server's* source of truth,
    /// and copying them into a test bundle would be the second copy this comment exists to
    /// prevent.
    private static func fixture(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Unit
            .deletingLastPathComponent()   // BlindDropTests
            .deletingLastPathComponent()   // ios
        return try Data(contentsOf: root.appending(path: "Fixtures/payloads/\(name).json"))
    }

    // MARK: - The envelope and the clock

    /// `docs/13` §3: `server_now` reaches `ServerClock` **before** the payload reaches the
    /// caller. Asserted by reading the clock the instant `send` returns — if the sync happened
    /// after, or on a detached task, this is the test that notices.
    @MainActor
    @Test func everyResponseAnchorsTheClockBeforeItReturns() async throws {
        let (client, clock, _) = Self.makeClient()
        #expect(clock.now == nil, "before the first response the app does not know the time")

        Stub.arm([.init(body: Self.envelope(try Self.fixture("me")))])
        _ = try await client.send(.me)

        let anchored = try #require(clock.now)
        let sent = try Date("2026-08-10T18:42:07Z", strategy: .iso8601)
        #expect(abs(anchored.timeIntervalSince(sent)) < 1, "the clock reads what the server said")
    }

    /// A *failed* response carries `server_now` too, and a phone that has just been refused is
    /// exactly the phone whose clock should not be guessing.
    @MainActor
    @Test func aFailureAnchorsTheClockAsWell() async throws {
        let (client, clock, _) = Self.makeClient()
        Stub.arm([.init(status: 409, body: Self.failure("NO_GROUP"))])

        await #expect(throws: APIError.noGroup) { try await client.send(.round("g1")) }
        #expect(clock.now != nil, "a refusal is still evidence about the time")
    }

    // MARK: - The contract, decoded

    @MainActor
    @Test func everyFixturePayloadDecodesIntoItsDTO() async throws {
        let (client, _, _) = Self.makeClient()

        func load<Response: Decodable & Sendable>(
            _ fixture: String, _ endpoint: Endpoint<Response>
        ) async throws -> Response {
            Stub.arm([.init(body: Self.envelope(try Self.fixture(fixture)))])
            return try await client.send(endpoint)
        }

        let me = try await load("me", .me)
        #expect(me.displayName == "Ana")
        #expect(me.hasGroup)

        let group = try await load("group_current", .group("g1"))
        #expect(group.name == "The Cove")
        #expect(group.timezone == "America/New_York")
        #expect(group.revealHour == 20)
        #expect(group.members.count == 9)
        #expect(group.isAdmin)

        let results = try await load("results", .results(roundID: "r"))
        #expect(results.submitterCount == 8)
        #expect(results.cards.count == 8)
        #expect(results.cards.allSatisfy { $0.eligibleGuesserCount == 7 })
        #expect(results.people.count == 8)

        let standings = try await load("standings", .standings("g1"))
        #expect(standings.roundsPlayed > 0)
        #expect(standings.bestEar.first?.rank == 1)
        #expect(!standings.readability.isEmpty)

        let record = try await load("record", .record("g1"))
        #expect(!record.days.isEmpty)
        #expect(record.days.allSatisfy { !$0.entries.isEmpty })
        #expect(record.nextCursor == nil)
        #expect(record.days.first?.cue?.text == "A song you hate", "a cued night carries its cue per day")
        #expect(record.days.last?.cue == nil, "an uncued night carries no cue, not an empty one")

        let spotify = try await load("record_export_spotify", .export("g1", .spotify))
        #expect(spotify.playlistName.hasSuffix("Blind Drop"))
        #expect(spotify.tracks.allSatisfy { $0.spotifyURI != nil })

        let search = try await load("tracks_search", .search("lorde"))
        #expect(!search.results.isEmpty)
        // The artwork URL is Apple's template, kept whole (`docs/06` §2.1).
        #expect(search.results.allSatisfy { $0.artworkURL?.contains("{w}x{h}") == true })

        let track = try await load("track_resolved", .resolve(.isrc("USUM71311296")))
        #expect(track.trackKey.hasPrefix("isrc:"))
    }

    // MARK: - The phase enum

    /// `docs/13` §3: *"a `revealed` payload's `cards` array is impossible to access from a view
    /// holding an `open` round"*. The compiler enforces it — there is no `cards` property on
    /// `RoundDTO` at all — so what this test can add is that each phase decodes into its own
    /// case with its own keys, including the two that are shaped identically on the wire.
    @MainActor
    @Test func eachPhaseDecodesOnlyItsOwnKeys() async throws {
        let (client, _, _) = Self.makeClient()

        func round(_ fixture: String) async throws -> RoundDTO {
            Stub.arm([.init(body: Self.envelope(try Self.fixture(fixture)))])
            return try await client.send(.round("g1"))
        }

        let open = try await round("round_open")
        guard case let .open(mine) = open.phase else {
            Issue.record("an `open` payload must decode as .open"); return
        }
        #expect(mine?.track.title == "Kill Bill")
        #expect(open.state == .open)
        // `cue` is a base key: present on every phase, decoded before the phase switch
        // (`docs/18-CUES.md` §8).
        #expect(open.cue == CueDTO(key: "song_you_hate", text: "A song you hate"))

        let nosub = try await round("round_open_nosub")
        guard case .open(nil) = nosub.phase else {
            Issue.record("a non-submitter's open round has no submission"); return
        }

        // `voided` is byte-identical in shape to `open` and is still its own case: the screen
        // it drives says something completely different, and a boolean would let one of them
        // render as the other.
        let voided = try await round("round_voided")
        guard case let .voided(returned) = voided.phase else {
            Issue.record("a voided payload must decode as .voided"); return
        }
        #expect(returned != nil, "a voided round returns the caller's own song")
        // Absent key → `nil`, with nothing to throw (`decodeIfPresent`).
        #expect(voided.cue == nil, "an uncued round decodes to nil, not an empty cue")

        let revealed = try await round("round_revealed")
        guard case let .revealed(_, payload) = revealed.phase else {
            Issue.record("a revealed payload must decode as .revealed"); return
        }
        #expect(payload.cards.count == 8)
        #expect(payload.myCardNumber == 4)
        #expect(payload.canGuess)
        #expect(payload.cannotGuessReason == nil)
        // The name pool is every submitter including the caller, whole (`docs/04` §4).
        #expect(payload.namePool.count == 8)
        // Cards are ascending and identical for everyone; the numbering is the game's spine.
        #expect(payload.cards.map(\.cardNumber) == Array(1...8))
        #expect(revealed.cue?.key == "song_you_hate", "the revealed round carries the same base-key cue")

        let nonSubmitter = try await round("round_revealed_nosub")
        guard case let .revealed(_, blocked) = nonSubmitter.phase else {
            Issue.record("still a revealed round"); return
        }
        #expect(!blocked.canGuess)
        #expect(blocked.cannotGuessReason == .notASubmitter)
        #expect(blocked.myCardNumber == nil)

        let late = try await round("round_revealed_joinedlate")
        guard case let .revealed(_, joinedLate) = late.phase else {
            Issue.record("still a revealed round"); return
        }
        #expect(joinedLate.cannotGuessReason == .joinedLate)

        let scored = try await round("round_scored")
        guard case .scored = scored.phase else {
            Issue.record("a scored payload must decode as .scored"); return
        }
        #expect(scored.cue?.text == "A song you hate", "the scored round carries the same base-key cue")
    }

    /// A `cards` array on an `open` payload — the shape a leak would take — is dropped rather
    /// than decoded. There is nowhere in `.open` to put it, which is the point.
    @MainActor
    @Test func anOpenPayloadCarryingCardsIsStillJustAnOpenRound() async throws {
        let (client, _, _) = Self.makeClient()
        let leaky = """
        {"round_id":"r","local_date":"2026-08-10","state":"open",
         "opens_at":"2026-08-10T14:00:00Z","reveals_at":"2026-08-11T00:00:00Z",
         "scores_at":"2026-08-11T02:00:00Z","my_submission":null,
         "cards":[{"card_no":1,"track":{}}],"name_pool":[{"user_id":"u","display_name":"Ben"}]}
        """
        Stub.arm([.init(body: Self.envelope(Data(leaky.utf8)))])

        let round = try await client.send(.round("g1"))
        guard case .open(nil) = round.phase else {
            Issue.record("a state of `open` decodes as .open whatever else is in the body")
            return
        }
    }

    // MARK: - Errors

    /// Every code in `docs/04` §1, mapped, with the copy key the UI will show.
    @MainActor
    @Test func everyServerCodeMapsToItsError() async throws {
        let (client, _, _) = Self.makeClient()

        let cases: [(String, Int, APIError, String)] = [
            ("UNAUTHENTICATED", 401, .unauthenticated, "error.unauthenticated"),
            ("NO_PROFILE", 409, .noProfile, "error.noprofile"),
            ("NO_GROUP", 409, .noGroup, "error.nogroup"),
            ("NOT_FOUND", 404, .notFound, "error.notfound"),
            ("NOT_A_SUBMITTER", 403, .notASubmitter, "error.notsubmitter"),
            ("JOINED_LATE", 403, .joinedLate, "error.joinedlate"),
            ("ROUND_VOIDED", 409, .roundVoided, "error.roundvoided"),
            ("ALREADY_IN_GROUP", 409, .alreadyInGroup, "error.alreadyingroup"),
            ("ALREADY_INVITED", 409, .alreadyInvited, "error.alreadyinvited"),
            ("CIRCLE_LIMIT_REACHED", 409, .circleLimitReached, "error.circlelimitreached"),
            ("NOT_ADMIN", 403, .notAdmin, "error.notadmin"),
            ("UPSTREAM_UNAVAILABLE", 502, .upstreamUnavailable, "error.upstream"),
            ("REAUTHENTICATION_REQUIRED", 409, .reauthenticationRequired, "settings.delete.reauth"),
            ("REAUTHENTICATION_FAILED", 403, .reauthenticationFailed, "settings.delete.reauth"),
            ("AUTH_PROVIDER_UNAVAILABLE", 502, .authProviderUnavailable, "error.authprovider"),
            ("INTERNAL", 500, .server, "error.generic"),
        ]
        for (code, status, expected, copyKey) in cases {
            Stub.arm([.init(status: status, body: Self.failure(code))])
            await #expect(throws: expected, "\(code)") {
                try await client.send(.group("g1"))
            }
            #expect(expected.copyKey == copyKey, "\(code)")
            #expect(expected.serverCode == code, "\(code)")
        }
    }

    /// The three codes that carry detail carry exactly the detail `docs/04` §1 allows, and the
    /// detail arrives on the error rather than being thrown away.
    @MainActor
    @Test func theThreeCodesWithDetailKeepIt() async throws {
        let (client, _, _) = Self.makeClient()

        Stub.arm([.init(status: 409, body: Self.failure("WRONG_PHASE", extra: #","state":"revealed""#))])
        await #expect(throws: APIError.wrongPhase(state: .revealed)) {
            try await client.send(.seal("g1", .appleMusicID("1")))
        }

        Stub.arm([.init(status: 400, body: Self.failure("INVALID_INPUT", extra: #","details":{"field":"limit"}"#))])
        await #expect(throws: APIError.invalidInput(field: "limit")) {
            try await client.send(.record("g1", limit: 500))
        }

        Stub.arm([.init(
            status: 429,
            body: Self.failure("RATE_LIMITED"),
            headers: ["Retry-After": "37"]
        )])
        await #expect(throws: APIError.rateLimited(retryAfter: 37)) {
            try await client.send(.search("lorde"))
        }
    }

    /// A body that is not our envelope — a gateway's HTML, a truncated response, a field whose
    /// type changed — is one error with one thing a person can do about it.
    @MainActor
    @Test func aBodyThatIsNotTheEnvelopeIsUnreadable() async throws {
        let (client, _, _) = Self.makeClient()

        Stub.arm([.init(body: Data("<html>502 Bad Gateway</html>".utf8))])
        await #expect(throws: APIError.unreadable) { try await client.send(.me) }

        Stub.arm([.init(body: Self.envelope(Data(#"{"user_id":"u"}"#.utf8)))])
        await #expect(throws: APIError.unreadable) { try await client.send(.me) }
    }

    /// A transport failure is `.offline`, quickly. `waitsForConnectivity` is off precisely so
    /// this does not take forty seconds (`docs/13` §3).
    @MainActor
    @Test func aDeadNetworkIsOfflineAndNotASpinner() async throws {
        let (client, _, _) = Self.makeClient()
        Stub.arm([.init(failure: URLError(.notConnectedToInternet))])

        await #expect(throws: APIError.offline) { try await client.send(.joinGroup(inviteCode: "K7MQ2X")) }
        #expect(APIClient.makeTransport().configuration.waitsForConnectivity == false)
    }

    // MARK: - Retry policy

    /// `docs/13` §3, counted: an idempotent GET is attempted three times in all, the two
    /// idempotent PUTs twice, and everything else once.
    @MainActor
    @Test func onlyTheEndpointsThatMayRetryDo() async throws {
        let (client, _, _) = Self.makeClient()

        Stub.arm([.init(failure: URLError(.timedOut))])
        await #expect(throws: APIError.offline) { try await client.send(.round("g1")) }
        #expect(Stub.requestCount == 3, "an idempotent GET retries twice")

        Stub.arm([.init(failure: URLError(.timedOut))])
        await #expect(throws: APIError.offline) { try await client.send(.seal("g1", .appleMusicID("1"))) }
        #expect(Stub.requestCount == 2, "PUT /rounds/current/submission retries once")

        Stub.arm([.init(failure: URLError(.timedOut))])
        await #expect(throws: APIError.offline) {
            try await client.send(.saveGuesses("g1", [GuessAssignment(cardNumber: 1, guessedUserID: nil)]))
        }
        #expect(Stub.requestCount == 2, "PUT /rounds/current/guesses retries once")

        // Joining is rate-limited at ten an hour because it is the brute-force surface
        // (`docs/04` §8). An automatic second attempt would spend somebody's quota for them.
        Stub.arm([.init(failure: URLError(.timedOut))])
        await #expect(throws: APIError.offline) { try await client.send(.joinGroup(inviteCode: "K7MQ2X")) }
        #expect(Stub.requestCount == 1, "nothing else retries")
    }

    /// A retry that succeeds returns the payload, and the failed attempts leave no trace.
    @MainActor
    @Test func aRetryThatLandsIsAnOrdinarySuccess() async throws {
        let (client, _, _) = Self.makeClient()
        Stub.arm([
            .init(failure: URLError(.networkConnectionLost)),
            .init(body: Self.envelope(try Self.fixture("me"))),
        ])

        let me = try await client.send(.me)
        #expect(me.displayName == "Ana")
        #expect(Stub.requestCount == 2)
    }

    /// A refusal is not a flake. Retrying a `WRONG_PHASE` produces another one and spends a
    /// person's battery doing it, and retrying a 429 makes the window longer.
    @MainActor
    @Test func refusalsAreNotRetried() async throws {
        let (client, _, _) = Self.makeClient()

        Stub.arm([.init(status: 409, body: Self.failure("WRONG_PHASE", extra: #","state":"open""#))])
        await #expect(throws: APIError.wrongPhase(state: .open)) { try await client.send(.round("g1")) }
        #expect(Stub.requestCount == 1)

        Stub.arm([.init(status: 429, body: Self.failure("RATE_LIMITED"))])
        await #expect(throws: APIError.rateLimited(retryAfter: nil)) { try await client.send(.round("g1")) }
        #expect(Stub.requestCount == 1)
    }

    // MARK: - Headers, and the 401

    /// `X-Storefront` on **every** request, not just the two catalog ones — there is no route
    /// where forgetting it is possible (`docs/13` §3).
    @MainActor
    @Test func everyRequestCarriesTheStorefront() async throws {
        let (client, _, _) = Self.makeClient()
        Stub.arm([.init(body: Self.envelope(try Self.fixture("me")))])

        _ = try await client.send(.me)
        _ = try? await client.send(.leaveGroup("g1"))

        #expect(Stub.requestCount == 2)
        for request in Stub.requests {
            let storefront = request.value(forHTTPHeaderField: "X-Storefront")
            #expect(storefront == APIClient.storefront)
            #expect(storefront?.isEmpty == false)
        }
    }

    /// One 401 buys one refresh and one retry. With no refresh token to spend, the session
    /// ends — and it ends after exactly one attempt, not in a loop against a revoked token.
    @MainActor
    @Test func a401RefreshesOnceAndThenEndsTheSession() async throws {
        let (client, _, session) = Self.makeClient()
        Stub.arm([.init(status: 401, body: Self.failure("UNAUTHENTICATED"))])

        await #expect(throws: APIError.unauthenticated) { try await client.send(.me) }
        #expect(Stub.requestCount == 1, "no refresh token, so no second attempt")
        #expect(session.state == .signedOut, "the session is over, and RootView routes on it")
    }

    /// A 204 has no envelope to decode, and asking for one anyway is not an error.
    @MainActor
    @Test func aBodilessResponseIsNotAFailure() async throws {
        let (client, _, _) = Self.makeClient()
        Stub.arm([.init(status: 204)])

        _ = try await client.send(.leaveGroup("g1"))
        _ = try await client.send(.registerDevice(token: "abc", environment: "sandbox"))
        _ = try await client.send(.unregisterDevice(token: "abc"))
        _ = try await client.send(.deleteAccount())
    }

    // MARK: - Requests going out

    /// The three ways to name a song are one key each, never three optionals (`docs/04` §4),
    /// and a cleared guess is an **explicit** `null` rather than an omitted key (rule 7).
    @MainActor
    @Test func requestBodiesAreTheShapeTheContractDescribes() async throws {
        func encoded(_ body: (@Sendable () throws -> Data)?) throws -> String {
            let encode = try #require(body)
            return String(decoding: try encode(), as: UTF8.self)
        }

        #expect(try encoded(Endpoint<SubmissionDTO>.seal("g1", .appleMusicID("1440857781")).body)
            == #"{"apple_music_id":"1440857781"}"#)
        #expect(try encoded(Endpoint<SubmissionDTO>.seal("g1", .isrc("USUM71703861")).body)
            == #"{"isrc":"USUM71703861"}"#)

        let sheet = try encoded(Endpoint<GuessSheetDTO>.saveGuesses("g1", [
            GuessAssignment(cardNumber: 1, guessedUserID: "u_ben"),
            GuessAssignment(cardNumber: 2, guessedUserID: nil),
        ]).body)
        #expect(sheet.contains(#""guessed_user_id":null"#), "clearing a card is explicit")
        #expect(sheet.contains(#""card_no":2"#))

        #expect(try encoded(Endpoint<NoContent>.unregisterDevice(token: "a1b2").body)
            == #"{"apns_token":"a1b2"}"#)
        #expect(try encoded(Endpoint<NoContent>.deleteAccount(authorizationCode: "fresh-code").body)
            == #"{"apple_authorization_code":"fresh-code"}"#)
        #expect(Endpoint<NoContent>.deleteAccount().body == nil, "non-Apple deletion has no body")
        #expect(try encoded(Endpoint<GroupDTO>.updateMemberRole("u_ben", in: "g1", role: "admin").body)
            == #"{"role":"admin"}"#)

        let roleEndpoint = Endpoint<GroupDTO>.updateMemberRole("u_ben", in: "g1", role: "admin")
        #expect(roleEndpoint.method == .patch)
        #expect(roleEndpoint.path == "/groups/g1/members/u_ben")
        let removeEndpoint = Endpoint<NoContent>.removeMember("u_ben", from: "g1")
        #expect(removeEndpoint.method == .delete)
        #expect(removeEndpoint.path == "/groups/g1/members/u_ben")
    }

    /// Query parameters land on the URL, which is what makes `?member=` and the cursor work at
    /// all — and the path is the contract's, not a string a screen built.
    @MainActor
    @Test func queryParametersReachTheURL() async throws {
        let (client, _, _) = Self.makeClient()
        Stub.arm([.init(body: Self.envelope(try Self.fixture("record")))])

        _ = try await client.send(.record("g1", member: "u_ana", cursor: "eyJkIjoiMjAyNi0wOC0wMSJ9", limit: 25))

        let url = try #require(Stub.requests.first?.url)
        #expect(url.path() == "/functions/v1/groups/g1/record")
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.contains(URLQueryItem(name: "member", value: "u_ana")))
        #expect(query.contains(URLQueryItem(name: "cursor", value: "eyJkIjoiMjAyNi0wOC0wMSJ9")))
        #expect(query.contains(URLQueryItem(name: "limit", value: "25")))
    }

    // MARK: - LoadState

    /// `docs/13` §7: a foreground refetch that fails keeps what was on screen and says it may
    /// be out of date. The transition lives on `LoadState` so a store cannot forget it.
    @Test func aFailedRefreshKeepsWhatWasAlreadyThere() {
        var state = LoadState<String>.idle
        #expect(state.value == nil)

        state.apply(.success("tonight"))
        #expect(state.value == "tonight")

        state.apply(.failure(.offline))
        #expect(state.value == "tonight", "the data survives the failed refresh")
        #expect(state.error == .offline)
        if case .stale = state {} else { Issue.record("a failed refresh over data is .stale") }

        var fresh = LoadState<String>.loading
        fresh.apply(.failure(.offline))
        #expect(fresh.value == nil)
        if case .failed = fresh {} else { Issue.record("a first load that fails is .failed") }
    }
}
