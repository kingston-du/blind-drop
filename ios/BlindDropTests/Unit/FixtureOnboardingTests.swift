import Foundation
import Testing
@testable import BlindDrop

/// E09-03's verification: *"both paths complete against the fixture server."*
///
/// `OnboardingStoreTests` is stubs — fast, exact, and unable to notice that the client builds a
/// body `POST /groups` would refuse or reads a field the contract does not send. This suite
/// runs the **real** `APIClient` and the **real** DTO decoding against
/// `ios/Fixtures/server.ts`, whose payloads are `docs/04` verbatim (E00-05).
///
/// Skipped unless `BLINDDROP_FIXTURE_API` is set, which `ios/scripts/verify-fixture.sh` does
/// after starting the server. A test that silently passes when its server is not running is
/// worse than no test.
@MainActor
@Suite(.enabled(if: FixtureServer.baseURL != nil))
struct FixtureOnboardingTests {

    /// A store pointed at the fixture server, with no credential — the fixture is a canned
    /// contract rather than an auth gate, so these routes answer anyone.
    private func store() throws -> (OnboardingStore, AppEnvironment) {
        let base = try #require(FixtureServer.baseURL)
        let env = AppEnvironment(
            configuration: AppConfiguration(apiBaseURL: base),
            secrets: Keychain(service: "app.blinddrop.tests.\(UUID().uuidString)")
        )
        return (OnboardingStore(api: env.api, session: env.session), env)
    }

    /// 1.2 — the name reaches the server and comes back as the server stored it.
    @Test func namingCompletesAgainstTheFixtureServer() async throws {
        let (store, env) = try store()

        store.name = "  Ana\u{200B}  Lee  "
        #expect(store.canContinue)
        await store.saveName()

        #expect(store.nameError == nil)
        // The fixture echoes the `display_name` it was sent, so this asserts the *cleaned*
        // string actually left the device — not merely that a request succeeded.
        #expect(env.session.user?.displayName == "Ana Lee")
        #expect(env.clock.now != nil, "every response anchors the clock")
    }

    /// 1.3 → 1.5, the joiner's path. `K7MQ2X` is the fixture's one real code.
    @Test func theJoinPathCompletesAgainstTheFixtureServer() async throws {
        let (store, env) = try store()

        store.code = "k7mq2x"
        #expect(store.code == "K7MQ2X", "normalised on the way in")
        #expect(store.canJoin)
        await store.join()

        #expect(store.joinFailure == nil)
        // Straight to the round: `docs/08` §1.5 — no confirmation, no welcome, no invite step.
        #expect(env.session.state == .ready)
        #expect(store.step == .joinOrCreate)
    }

    /// The code that does not exist, from the server rather than from a stub. This is the one
    /// that would catch a client sending `inviteCode` where the contract says `invite_code`.
    @Test func anUnknownCodeIsRefusedByTheFixtureServer() async throws {
        let (store, env) = try store()

        store.code = "ABCDEF"
        await store.join()

        #expect(store.joinFailure == "onboarding.group.code.error")
        #expect(env.session.state == .unknown, "a refused join routes nowhere")
    }

    /// 1.4 → 1.5, the creator's path: the form goes up, the invite code comes back, and the
    /// session moves on only when the creator taps through.
    @Test func theCreatePathCompletesAgainstTheFixtureServer() async throws {
        let (store, env) = try store()

        store.groupName = "The Cove"
        store.timezone = "America/New_York"
        store.revealHour = RevealHour.default
        #expect(store.canCreate)
        await store.create()

        #expect(store.createFailure == nil)
        guard case .invite(let group) = store.step else {
            Issue.record("expected the invite step, got \(store.step)")
            return
        }
        #expect(group.inviteCode == "K7MQ2X")
        #expect(group.timezone == "America/New_York")
        #expect(group.revealHour == 20)
        #expect(group.isAdmin)
        #expect(env.session.state == .unknown, "the creator has not tapped through yet")

        // And the URL the share sheet hands over is one the app itself parses back.
        let url = try #require(InviteCode.inviteURL(for: group.inviteCode))
        #expect(DeepLink(url) == .join(code: "K7MQ2X"))

        await store.finish()
        #expect(env.session.state == .ready)
    }
}
