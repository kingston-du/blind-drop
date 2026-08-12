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
    /// The two notes of `docs/09`. Injected rather than constructed at the call site so the
    /// seal and unseal can be driven by a counting double in a test (`docs/09` §6) — and so
    /// `DesignSystem/` never depends on `UIImpactFeedbackGenerator` being real.
    let haptics: HapticEngine

    /// `auth` and `secrets` are parameters so `AuthTests` can build a whole environment around
    /// doubles — the alternative is a test that reaches into the simulator's keychain daemon
    /// and a network it has no business touching. Their defaults are what the app ships with.
    init(
        configuration: AppConfiguration = .resolve(),
        haptics: HapticEngine = SystemHaptics(),
        auth: (any AuthService)? = nil,
        secrets: any SecretStore = Keychain()
    ) {
        self.configuration = configuration
        // The clock is made first and handed to the client, so the instance the client
        // re-anchors on every response is the instance every countdown reads (docs/13 §3, §5).
        let clock = ServerClock()
        let session = SessionStore(
            auth: auth ?? SupabaseAuthService(configuration: configuration),
            secrets: secrets
        )
        let api = APIClient(baseURL: configuration.apiBaseURL, clock: clock, session: session)
        // The store needs the client to ask `GET /me`, and the client needs the store for the
        // auth header — so the edge is closed here, after both exist, and the store holds its
        // half weakly (`SessionStore.api`).
        session.attach(api)
        self.clock = clock
        self.session = session
        self.api = api
        self.router = Router()
        self.haptics = haptics
    }
}
