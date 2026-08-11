import Foundation

/// `docs/13` §3. An `actor`, so concurrent screens share one session and one refresh.
///
/// E08-05 implements `send(_:)`, `Envelope<T>` (which feeds `server_now` to `ServerClock`
/// **before** returning the payload), the `APIError` mapping, `X-Storefront`, and the retry
/// policy. E08-01 lands the constructor only, because the composition root has to hand it the
/// base URL, the clock, and the session, and that wiring is what makes `-apiBaseURL` reach
/// anything at all.
actor APIClient {
    let baseURL: URL
    private let clock: ServerClock
    private let session: SessionStore

    /// `clock` and `session` are references, not copies: the clock the client re-anchors is
    /// the same one every countdown reads, which is how the app stays on server time with no
    /// extra requests (`docs/13` §3).
    init(baseURL: URL, clock: ServerClock, session: SessionStore) {
        self.baseURL = baseURL
        self.clock = clock
        self.session = session
    }
}
