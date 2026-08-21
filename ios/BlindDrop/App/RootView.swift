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
/// The Group roster and Settings are reached from `RoundScreen`'s toolbar.
///
/// Appearance is not touched anywhere in this tree — `.preferredColorScheme(.light)` is set
/// once, in `BlindDropApp` (`docs/07` intro).
struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @State private var loadToken = 0

    var body: some View {
        @Bindable var router = env.router

        NavigationStack(path: $router.path) {
            Group {
                switch RootDestination(session: env.session.state) {
                case .waiting:
                    SessionLoadingView(error: env.session.loadFailure) { loadToken += 1 }
                case .signIn:
                    SignInScreen()
                // Both onboarding destinations are rendered by the one flow, deliberately. The
                // routing table above still has two rows — they are two different things the
                // server said — but the *view* is one, so `OnboardingStore` survives the
                // transition between them. See `OnboardingStore`'s note on why the creator's
                // invite code cannot live in `SessionState`.
                case .displayName, .joinOrCreate:
                    OnboardingFlow()
                case .round:
                    RoundScreen()
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .record:   RecordScreen()
                case .group:    GroupScreen()
                case .settings: SettingsScreen()
                case .insights: InsightsScreen()
                }
            }
        }
        .task(id: loadToken) {
            #if DEBUG
            if env.configuration.usesFixtureSession {
                await env.session.startFixtureSession()
                if env.configuration.opensRecordForUITests {
                    env.router.path = [.record]
                }
            } else {
                await env.session.load()
            }
            #else
            await env.session.load()
            #endif
            // A `.join` link does not wait on a round — joining is a session-level concern.
            env.router.consume(session: env.session.state, roundIsLoaded: false)
        }
        // Join links are session-level work, so they do not wait for a round reload. Round and
        // Record links remain pending here and are consumed by `RoundStore` only after it has a
        // server-authorized context to render.
        .onChange(of: env.router.pending) { _, pending in
            guard pending != nil else { return }
            env.router.consume(session: env.session.state, roundIsLoaded: false)
        }
        .onChange(of: env.session.state) { _, state in
            // A direct invitation received while signed out survives Apple sign-in and naming;
            // this is the first point it can be proved against the recipient's account.
            env.router.consume(session: state, roundIsLoaded: false)
        }
        .onChange(of: scenePhase) { _, phase in
            // docs/13 §5 rule 5: the monotonic anchor does not advance while the device is
            // asleep, so any background period leaves it stale. Invalidate on the way back in;
            // a countdown must never render from a stale anchor.
            if phase == .active {
                env.clock.invalidate()
                // A launch that failed offline is not a dead end. Returning to the app is a
                // natural, bounded retry point and the button above remains available while the
                // app stays foregrounded.
                if env.session.loadFailure != nil { loadToken += 1 }
            }
        }
        .sheet(
            isPresented: Binding(
                get: { env.router.pendingInvitationID != nil },
                set: { if !$0 { env.router.clearPendingInvitation() } }
            )
        ) {
            if let id = env.router.pendingInvitationID {
                InvitationJoinSheet(invitationID: id) {
                    env.router.clearPendingInvitation()
                }
            }
        }
    }
}

private struct SessionLoadingView: View {
    let error: APIError?
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.blockGap) {
            RoundSkeleton()
            if let error {
                Text(error == .offline ? "error.offline" : "error.generic")
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.inkDim)
                PrimaryButton("error.retry", fill: .neutral, action: retry)
            }
        }
        .padding(Layout.screenInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Palette.paper)
    }
}
