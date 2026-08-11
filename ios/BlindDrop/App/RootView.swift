import SwiftUI

/// Which screen the session state calls for. `docs/13` §4's routing table, lifted out of the
/// view so it can be asserted in a unit test instead of eyeballed in a simulator
/// (`CLAUDE.md` §7).
enum RootDestination: Equatable, Sendable {
    /// Nothing yet. Before the first `GET /me` the app does not know who is asking and does
    /// not guess — the same rule as `docs/13` §5 rule 3, applied to identity.
    case waiting
    case signIn
    case displayName
    case joinOrCreate
    case round

    init(session: SessionState) {
        switch session {
        case .unknown:   self = .waiting
        case .signedOut: self = .signIn
        case .noProfile: self = .displayName
        case .noGroup:   self = .joinOrCreate
        case .ready:     self = .round
        }
    }
}

/// The root. Routes on session state (`docs/13` §4), owns the one `NavigationStack`, and
/// holds no state of its own.
///
/// There is exactly one `NavigationStack` and zero `TabView` here. `docs/08` intro: *"There is
/// no tab bar."* `docs/13` §9 lists a tab bar as an automatic review rejection. The Record and
/// Group settings are reached from `RoundScreen`'s toolbar.
///
/// Appearance is not touched anywhere in this tree — `.preferredColorScheme(.light)` is set
/// once, in `BlindDropApp` (`docs/07` intro).
struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = env.router

        NavigationStack(path: $router.path) {
            Group {
                switch RootDestination(session: env.session.state) {
                case .waiting:
                    Color.clear
                case .signIn:
                    SignInScreen()
                case .displayName:
                    DisplayNameScreen()
                case .joinOrCreate:
                    JoinOrCreateScreen(prefilledCode: router.pendingInviteCode)
                case .round:
                    RoundScreen()
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .record:        RecordScreen()
                case .groupSettings: GroupSettingsScreen()
                }
            }
        }
        .task {
            await env.session.load()
            // A `.join` link does not wait on a round — joining is a session-level concern.
            env.router.consume(session: env.session.state, roundIsLoaded: false)
        }
        .onChange(of: scenePhase) { _, phase in
            // docs/13 §5 rule 5: the monotonic anchor does not advance while the device is
            // asleep, so any background period leaves it stale. Invalidate on the way back in;
            // a countdown must never render from a stale anchor.
            if phase == .active { env.clock.invalidate() }
        }
    }
}
