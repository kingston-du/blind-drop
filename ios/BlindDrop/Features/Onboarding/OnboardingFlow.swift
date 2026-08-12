import SwiftUI

/// Steps 1.2 to 1.5 of `docs/08` §1, and the one place `OnboardingStore` is constructed.
///
/// `RootView` routes `.noProfile` and `.noGroup` here rather than to two screens, so the store
/// survives the transition between them. That is not tidiness: the group step has one piece of
/// state that is **not** in `SessionState` — whether the creator has seen their invite code yet
/// — and a store rebuilt on every session change would lose it at exactly the moment it
/// matters. See `OnboardingStore`'s note.
///
/// No accent (`CLAUDE.md` §2.5), for the reason `SignInScreen` gives: amber means sealed and
/// ultramarine means revealed, and a person who has not joined a group yet is in neither state.
struct OnboardingFlow: View {
    @Environment(AppEnvironment.self) private var env

    /// Built once, on first appearance, because it needs the environment and `@State` cannot
    /// read one at initialisation. `nil` renders nothing for exactly one frame — the same
    /// "render nothing rather than guess" rule the root applies to identity (`docs/13` §5).
    @State private var store: OnboardingStore?

    var body: some View {
        Group {
            if let store {
                content(store)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.paper)
        .task {
            let store = store ?? OnboardingStore(api: env.api, session: env.session)
            self.store = store
            adoptPendingInviteCode(into: store)
        }
        // A link can arrive while the flow is already on screen — the user is staring at the
        // join field when a friend's message lands. `Router` parks the code; this picks it up.
        .onChange(of: env.router.pendingInviteCode) {
            if let store { adoptPendingInviteCode(into: store) }
        }
    }

    @ViewBuilder private func content(_ store: OnboardingStore) -> some View {
        switch env.session.state {
        case .noProfile:
            DisplayNameScreen(store: store)
        default:
            // Every other state that reaches this view is `.noGroup`. `RootView` renders the
            // flow for exactly two states and this is the second; a session that has moved on
            // is already being replaced by the root's own switch, and rendering the group step
            // for one frame is better than rendering a blank.
            switch store.step {
            case .joinOrCreate:
                JoinOrCreateScreen(store: store)
            case .create:
                CreateGroupScreen(store: store)
            case .invite(let group):
                InviteCodeScreen(store: store, group: group)
            }
        }
    }

    /// Moves a deep link's code from the router into the field, once (`docs/05` §5).
    ///
    /// Cleared on the router straight away so that coming back to this screen later does not
    /// re-prefill a code the user deliberately cleared.
    private func adoptPendingInviteCode(into store: OnboardingStore) {
        guard let code = env.router.pendingInviteCode else { return }
        store.prefill(code: code)
        env.router.clearPendingInviteCode()
    }
}
