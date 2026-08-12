import Foundation

/// `docs/13` §3. An `actor`, so concurrent screens share one session, one auth header, and one
/// refresh — three screens waking at 20:00 must not produce three token refreshes.
///
/// Four things about this file are load-bearing:
///
/// 1. **Every response re-anchors the clock.** `server_now` is on every envelope, success or
///    failure, and it is handed to `ServerClock` *before* the payload is returned. That is how
///    the countdown is server time on the first screen rather than one request later
///    (`docs/13` §5), with no clock endpoint and no extra round trip.
/// 2. **`waitsForConnectivity` is off.** A request that cannot go out fails now and says so.
///    The alternative is a spinner that resolves in forty seconds, by which time the user has
///    force-quit and the round has moved on.
/// 3. **Retries are per endpoint, never per verb.** `docs/13` §3: idempotent GETs twice, the
///    two idempotent PUTs once, nothing else. The policy lives on `Endpoint` so it is declared
///    beside the route it belongs to.
/// 4. **One 401 buys one refresh.** Then the session is over. A loop that refreshed on every
///    401 would spin against a revoked token for as long as the app was open.
actor APIClient {
    let baseURL: URL
    private let clock: ServerClock
    private let session: SessionStore
    private let transport: URLSession

    /// `clock` and `session` are references, not copies: the clock the client re-anchors is
    /// the same one every countdown reads, which is how the app stays on server time with no
    /// extra requests (`docs/13` §3, §5).
    ///
    /// `transport` is injectable so `NetworkingTests` can stub `URLProtocol` without a server.
    /// It defaults to the one configuration the app ships with, so a caller cannot accidentally
    /// get a session that waits for connectivity.
    init(
        baseURL: URL,
        clock: ServerClock,
        session: SessionStore,
        transport: URLSession = APIClient.makeTransport()
    ) {
        self.baseURL = baseURL
        self.clock = clock
        self.session = session
        self.transport = transport
    }

    /// The app's `URLSession`. Fast honest failures (`docs/13` §3), and no disk cache for API
    /// responses — the only thing this app caches to disk is artwork (`docs/13` §7).
    static func makeTransport(_ configuration: URLSessionConfiguration = .ephemeral) -> URLSession {
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    // MARK: - Sending

    /// Sends an endpoint and returns its payload, or throws the one error type a view can show.
    func send<Response: Decodable & Sendable>(_ endpoint: Endpoint<Response>) async throws(APIError) -> Response {
        let data = try await sendReturningData(endpoint)
        // A 204 has no body and no envelope. `NoContent` is the only type that can decode
        // from nothing, and asking for any other type from a 204 route is a programming error
        // that shows up as `.unreadable` in the one test that tries it.
        if data.isEmpty {
            guard let empty = NoContent() as? Response else { throw APIError.unreadable }
            return empty
        }
        guard let envelope = try? JSONDecoder.api.decode(Envelope<Response>.self, from: data) else {
            throw APIError.unreadable
        }
        await clock.sync(serverNow: envelope.serverNow)
        return envelope.data
    }

    /// The transport half: builds the request, applies the retry policy, and turns everything
    /// that is not a 2xx into an `APIError`.
    private func sendReturningData<Response>(_ endpoint: Endpoint<Response>) async throws(APIError) -> Data {
        var attempt = 0
        while true {
            do {
                return try await attemptOnce(endpoint, isRetry: attempt > 0)
            } catch {
                guard error.isWorthRetrying, attempt < endpoint.retry.backoff.count else { throw error }
                try? await Task.sleep(for: endpoint.retry.backoff[attempt])
                attempt += 1
            }
        }
    }

    private func attemptOnce<Response>(
        _ endpoint: Endpoint<Response>,
        isRetry: Bool
    ) async throws(APIError) -> Data {
        // Captured before the request goes out, and handed back to the session on a 401. It is
        // what lets "one 401 buys one refresh" survive three requests failing at once: the two
        // that were already carrying a token somebody else has since rotated retry instead of
        // spending a second refresh (`docs/13` §3).
        let token = await session.accessToken
        let request: URLRequest
        do {
            request = try await makeRequest(endpoint, token: token)
        } catch {
            throw APIError.unreadable
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch {
            // Every transport failure is `.offline` to a person: there is one thing they can
            // do about a timeout, a dropped connection, and no network at all, and it is the
            // same thing. `URLError.cancelled` is deliberately included — a cancelled request
            // is a screen that went away, and nothing renders its error.
            throw APIError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.unreadable }

        if (200..<300).contains(http.statusCode) {
            return data
        }

        let failure = try? JSONDecoder.api.decode(ErrorEnvelope.self, from: data)
        if let failure {
            // A failure envelope carries `server_now` too, and a phone that has just been
            // refused is exactly the phone whose clock should not be guessing (`docs/13` §5).
            await clock.sync(serverNow: failure.serverNow)
        }
        let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
        let error = failure?.error.apiError(retryAfter: retryAfter)
            // A body that is not our envelope — a gateway's own 502 page, say. The status code
            // is the only thing left worth reading.
            ?? APIError(code: http.statusCode >= 500 ? "INTERNAL" : "NOT_FOUND")

        if case .unauthenticated = error, !isRetry {
            // One refresh, one retry, then the session is over (`docs/13` §3).
            if await session.refreshCredentials(after: token) {
                return try await attemptOnce(endpoint, isRetry: true)
            }
            await session.endSession()
        }

        // `NO_PROFILE` and `NO_GROUP` are facts about the caller, not about the request, and
        // they route (`docs/04` §2). Every other code is left alone here — the screen that
        // asked is the one that knows what a `WRONG_PHASE` means to it.
        await session.noteServerSaid(error)
        throw error
    }

    private func makeRequest<Response>(
        _ endpoint: Endpoint<Response>,
        token: String?
    ) async throws -> URLRequest {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(endpoint.path.trimmingPrefix("/").description),
            resolvingAgainstBaseURL: false
        )
        if !endpoint.query.isEmpty { components?.queryItems = endpoint.query }
        guard let url = components?.url else { throw APIError.unreadable }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // `docs/06` §4: the storefront decides which catalog a search reads, and it comes from
        // the device's region rather than its language — somebody whose phone is in French in
        // Brooklyn should get the American catalog. It rides every request, not just the two
        // catalog ones, so there is no route where forgetting it is possible.
        request.setValue(Self.storefront, forHTTPHeaderField: "X-Storefront")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body = endpoint.body {
            request.httpBody = try body()
        }
        return request
    }

    /// `Locale.current.region?.identifier.lowercased()` (`docs/13` §3), falling back to the US
    /// storefront — the one Apple Music guarantees exists.
    static var storefront: String {
        Locale.current.region?.identifier.lowercased() ?? "us"
    }
}
