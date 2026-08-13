import Foundation
import Testing
@testable import BlindDrop

/// Rounds, groups and a client for the round tests.
///
/// Rounds are **decoded from `ios/Fixtures/payloads/*.json`**, never built with an initialiser,
/// and that is not an inconvenience worked around — it is the point. `RoundDTO`'s memberwise
/// initialiser is private precisely so that *"there is exactly one place `RoundDTO.state` is
/// assigned, and it is the decoder"* (`docs/13` §2) is true of the type rather than of everybody's
/// discipline. A test that could construct a `.revealed` round out of thin air would be a test
/// that stopped exercising the decoder it depends on.
@MainActor
enum RoundFixture {

    // MARK: - Payloads

    /// A payload file from `ios/Fixtures`, which is the fixture server's source of truth and the
    /// contract verbatim (`ios/Fixtures/README.md`). Read from the repo rather than copied into a
    /// bundle — a second copy of a contract is a second thing to keep in step.
    static func payload(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Unit
            .deletingLastPathComponent()   // BlindDropTests
            .deletingLastPathComponent()   // ios
        return try Data(contentsOf: root.appending(path: "Fixtures/payloads/\(name).json"))
    }

    static func round(_ name: String) throws -> RoundDTO {
        try JSONDecoder.api.decode(RoundDTO.self, from: payload(name))
    }

    static func group() throws -> GroupDTO {
        try JSONDecoder.api.decode(GroupDTO.self, from: payload("group_current"))
    }

    static func track() throws -> TrackDTO {
        try JSONDecoder.api.decode(TrackDTO.self, from: payload("track_resolved"))
    }

    /// A whole context, which is what every phase screen is handed.
    static func context(_ name: String = "round_open") throws -> RoundContext {
        RoundContext(round: try round(name), group: try group())
    }

    // MARK: - A client that never leaves the machine

    /// An environment whose transport is a stub, and the handle that arms it.
    ///
    /// The environment is real — a real `APIClient`, a real `ServerClock`, real DTO decoding — and
    /// only the transport is a double. That is the level at which a store test is worth writing:
    /// it catches a body the server would refuse and a field the contract does not send.
    ///
    /// **Each one gets its own stub state, keyed by a token on every request.** swift-testing runs
    /// *suites* in parallel even when each is `.serialized`, so three suites sharing one global
    /// queue answer each other's requests — which shows up as a test that counts zero requests
    /// after making one, and as an offline test that gets somebody else's 200. Keying on the token
    /// makes the isolation a property of the harness rather than of the run order.
    static func environment(responses: [RoundStub.Response] = []) -> (AppEnvironment, StubSession) {
        let session = RoundStub.session()
        session.arm(responses)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RoundStub.self]
        configuration.httpAdditionalHeaders = [RoundStub.tokenHeader: session.token]
        let environment = AppEnvironment(
            configuration: AppConfiguration(apiBaseURL: URL(string: "https://fixture.test/functions/v1")!),
            secrets: MemorySecrets(),
            defaults: scratchDefaults(),
            transport: APIClient.makeTransport(configuration)
        )
        return (environment, session)
    }

    /// A `UserDefaults` nobody else is using, so a flag test cannot leave the runner's own
    /// defaults changed for the next suite.
    static func scratchDefaults() -> UserDefaults {
        UserDefaults(suiteName: "app.blinddrop.tests.\(UUID().uuidString)") ?? .standard
    }

    /// An envelope around a payload, the way the server sends it (`docs/04` §1).
    static func envelope(_ payload: Data, serverNow: String = "2026-08-10T18:42:07Z") -> RoundStub.Response {
        var body = Data(#"{"server_now":"\#(serverNow)","data":"#.utf8)
        body.append(payload)
        body.append(Data("}".utf8))
        return RoundStub.Response(status: 200, body: body)
    }

    static func envelope(_ name: String, serverNow: String = "2026-08-10T18:42:07Z") throws -> RoundStub.Response {
        envelope(try payload(name), serverNow: serverNow)
    }

    static func failure(_ status: Int, _ code: String) -> RoundStub.Response {
        RoundStub.Response(
            status: status,
            body: Data(#"{"server_now":"2026-08-10T18:42:07Z","error":{"code":"\#(code)","message":"x"}}"#.utf8)
        )
    }
}

/// A `URLProtocol` that answers from a queue and remembers what it was asked.
///
/// State is **per session**, not global: every stubbed `AppEnvironment` gets a token, sends it on
/// every request through `httpAdditionalHeaders`, and this class keeps one queue per token. Suites
/// run in parallel with one another in swift-testing — `.serialized` orders a suite's own tests and
/// nothing more — so a single shared queue would have three suites answering each other's requests.
/// That failure looks like flakiness and is really a shared mutable global.
final class RoundStub: URLProtocol, @unchecked Sendable {
    struct Response: Sendable {
        var status: Int = 200
        var body: Data = Data()
        /// A transport failure — no response at all, the way a dead network behaves.
        var failure: URLError?
    }

    /// The header each stubbed session tags its requests with.
    static let tokenHeader = "X-Stub-Session"

    nonisolated(unsafe) private static var sessions: [String: StubSession] = [:]
    private static let lock = NSLock()

    /// A fresh, isolated stub session.
    static func session() -> StubSession {
        let session = StubSession(token: UUID().uuidString)
        lock.lock(); defer { lock.unlock() }
        sessions[session.token] = session
        return session
    }

    private static func session(for request: URLRequest) -> StubSession? {
        guard let token = request.value(forHTTPHeaderField: tokenHeader) else { return nil }
        lock.lock(); defer { lock.unlock() }
        return sessions[token]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = RoundStub.session(for: request)?.answer(request) ?? StubSession.unarmed

        if let failure = response.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        let http = HTTPURLResponse(
            url: request.url!,
            statusCode: response.status,
            httpVersion: "HTTP/1.1",
            headerFields: [:]
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// One test's canned server: what it answers, and what it was asked.
final class StubSession: @unchecked Sendable {
    let token: String

    private var queue: [RoundStub.Response] = []
    private var routes: [String: RoundStub.Response] = [:]
    private var last = RoundStub.Response()
    private var recorded: [URLRequest] = []
    private let lock = NSLock()

    init(token: String) {
        self.token = token
    }

    /// What an unrecognised session gets: a 404 in the contract's envelope, which surfaces as
    /// `NOT_FOUND` rather than as a hang or a decode error nobody can read.
    static let unarmed = RoundStub.Response(
        status: 404,
        body: Data(#"{"server_now":"2026-08-10T18:42:07Z","error":{"code":"NOT_FOUND","message":"no stub armed"}}"#.utf8)
    )

    /// Answers in order. The last response repeats, so a test can arm one answer and let a retry
    /// find it again.
    func arm(_ responses: [RoundStub.Response]) {
        lock.lock(); defer { lock.unlock() }
        queue = responses
        routes = [:]
        last = responses.last ?? StubSession.unarmed
        recorded = []
    }

    /// Answers **by path**, keyed on a substring of it.
    ///
    /// Required rather than convenient: `RoundStore.load()` issues its two GETs concurrently
    /// (`async let`), so a queue would hand whichever request won the race whichever payload
    /// happened to be first — and a test that passes because two coin flips agreed is worse than no
    /// test. Routing by path makes the concurrency the thing being exercised instead of the thing
    /// being worked around.
    func arm(routes armed: [String: RoundStub.Response]) {
        lock.lock(); defer { lock.unlock() }
        routes = armed
        queue = []
        last = StubSession.unarmed
        recorded = []
    }

    var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    /// How many requests hit a path. The debounce test's whole assertion.
    func count(matching path: String) -> Int {
        requests.filter { $0.url?.path().contains(path) ?? false }.count
    }

    fileprivate func answer(_ request: URLRequest) -> RoundStub.Response {
        lock.lock(); defer { lock.unlock() }
        recorded.append(request)
        let path = request.url?.path() ?? ""
        // Prefer the most specific path. Dictionary iteration is intentionally unordered, and
        // `/groups/current` also matches `/groups/current/record`; taking the first match made
        // concurrent store tests depend on hash order.
        if let routed = routes
            .filter({ path.contains($0.key) })
            .max(by: { $0.key.count < $1.key.count })?
            .value {
            return routed
        }
        return queue.isEmpty ? last : queue.removeFirst()
    }
}
