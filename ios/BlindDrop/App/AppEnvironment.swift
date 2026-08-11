import Foundation

/// The composition root, and the only singleton in the app (`CLAUDE.md` §4, `docs/13` §2).
///
/// "Singleton" here means *one instance, constructed at the root and injected with
/// `.environment(_:)`* — **not** `static let shared`. There is deliberately no static
/// accessor: a global is how stores start reaching around injection, and it would make the
/// fixture-pointed environment that tests build impossible.
///
/// Feature stores are **not** here. Each screen owns its own `…Store`, constructed from this
/// (`docs/13` §2); what lives here is only what the whole app shares.
@Observable @MainActor
final class AppEnvironment {
    let configuration: AppConfiguration
    let clock: ServerClock
    let session: SessionStore
    let api: APIClient
    let router: Router

    init(configuration: AppConfiguration = .resolve()) {
        self.configuration = configuration
        // The clock is made first and handed to the client, so the instance the client
        // re-anchors on every response is the instance every countdown reads (docs/13 §3, §5).
        let clock = ServerClock()
        let session = SessionStore()
        self.clock = clock
        self.session = session
        self.api = APIClient(baseURL: configuration.apiBaseURL, clock: clock, session: session)
        self.router = Router()
    }
}
