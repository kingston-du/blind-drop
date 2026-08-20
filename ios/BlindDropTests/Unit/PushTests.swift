import Foundation
import Testing
@testable import BlindDrop

/// `E10-07` — the ask lands after the first seal, once, and a decline is remembered
/// (`docs/05` §4).
///
/// Each test gets its own stubbed environment for `POST /devices`, and its own scratch
/// `UserDefaults` for the flags — a suite that wrote the real ones would decide whether the *next*
/// suite thinks the user has been asked (`RoundFixture.environment`).
@MainActor
@Suite struct PushTests {

    private func makeRegistrar(
        status: FakeNotificationAuthority.Status = .notDetermined,
        grants: Bool = true
    ) -> (PushRegistrar, FakeNotificationAuthority, LocalFlags, StubSession) {
        let (env, stub) = RoundFixture.environment(responses: [RoundStub.Response(status: 204)])
        let center = FakeNotificationAuthority(status: status, grants: grants)
        let flags = LocalFlags(defaults: RoundFixture.scratchDefaults())
        return (PushRegistrar(api: env.api, flags: flags, center: center), center, flags, stub)
    }

    // MARK: - When the ask happens

    /// **Never at launch.** A launch registers only if permission already exists; it does not ask.
    @Test func launchNeverPrompts() async {
        let (registrar, center, _, _) = makeRegistrar()

        await registrar.registerIfAuthorized()

        #expect(!center.didRequestAuthorization, "launch must never spend the system's one dialog")
        #expect(!center.didRegister, "and there is no token to ask for without permission")
        #expect(!registrar.isPrompting)
    }

    /// With permission already granted, launch does the cheap half: register, which lands a token
    /// and a `POST /devices` upsert (`docs/05` §4).
    @Test func launchRegistersWhenPermissionAlreadyExists() async {
        let (registrar, center, _, _) = makeRegistrar(status: .authorized)

        await registrar.registerIfAuthorized()

        #expect(center.didRegister)
        #expect(!center.didRequestAuthorization)
    }

    /// After the first seal, the pre-prompt comes up — **the app's own**, before the system's.
    @Test func thefirstSealBringsUpThePrePrompt() async {
        let (registrar, center, flags, _) = makeRegistrar()

        await registrar.promptAfterFirstSeal()

        #expect(registrar.isPrompting)
        #expect(!center.didRequestAuthorization, "the system dialog is not spent by the pre-prompt")
        #expect(!flags.hasAskedAboutNotifications, "not until they answer")
    }

    /// **Declining is remembered; never re-prompted in v1.**
    @Test func decliningIsRememberedForever() async {
        let (registrar, _, flags, _) = makeRegistrar()
        await registrar.promptAfterFirstSeal()

        registrar.skip()
        #expect(!registrar.isPrompting)
        #expect(flags.hasDeclinedNotifications)

        await registrar.promptAfterFirstSeal()
        #expect(!registrar.isPrompting, "a second seal does not ask again")
    }

    /// Granting spends the system dialog and registers for a token.
    @Test func allowingRequestsAuthorizationAndRegisters() async {
        let (registrar, center, flags, _) = makeRegistrar()
        await registrar.promptAfterFirstSeal()

        await registrar.allow()

        #expect(center.didRequestAuthorization)
        #expect(center.didRegister)
        #expect(flags.hasAskedAboutNotifications)
        #expect(!flags.hasDeclinedNotifications)
    }

    /// A refusal at the **system** dialog is a decline too, and is remembered the same way. There
    /// is no second chance to offer: iOS shows that dialog once per install.
    @Test func refusingTheSystemDialogIsRemembered() async {
        let (registrar, _, flags, _) = makeRegistrar(grants: false)
        await registrar.promptAfterFirstSeal()

        await registrar.allow()

        #expect(flags.hasDeclinedNotifications)
    }

    /// Somebody who has already answered at the system level is not pre-prompted about a dialog
    /// that will never appear.
    @Test func analreadyDecidedUserIsNotPrePrompted() async {
        let (registrar, _, flags, _) = makeRegistrar(status: .denied)

        await registrar.promptAfterFirstSeal()

        #expect(!registrar.isPrompting)
        #expect(flags.hasAskedAboutNotifications)
    }

    /// The token reaches `POST /devices` as hex, with the environment this build talks to.
    @Test func thetokenIsUpsertedAsHex() async {
        let (registrar, _, _, stub) = makeRegistrar()

        await registrar.adopt(deviceToken: Data([0x0f, 0xa0, 0xff]))

        let request = stub.requests.last
        #expect(request?.url?.path().contains("/devices") == true)
        #expect(request?.httpMethod == "POST")
    }

    /// Sign out detaches the token before the session bearer disappears, and always clears old
    /// notifications from Notification Center even if that best-effort request cannot land.
    @Test func signOutUnregistersTheTokenAndClearsDeliveredNotifications() async {
        let (registrar, center, _, stub) = makeRegistrar()
        await registrar.adopt(deviceToken: Data(repeating: 0xab, count: 32))

        await registrar.unregisterCurrentDevice()

        let request = stub.requests.last
        #expect(request?.url?.path().contains("/devices") == true)
        #expect(request?.httpMethod == "DELETE")
        #expect(center.didClearDeliveredNotifications)
    }

    // MARK: - Where a push lands (`docs/05` §5)

    /// The payload's `deep_link` is parsed by the **same** grammar the URL scheme uses.
    @Test func thepayloadsLinkIsTheSameGrammar() {
        #expect(PushRouter.link(from: ["deep_link": "blinddrop://round/current"]) == .round(groupID: nil))
        #expect(PushRouter.link(from: ["deep_link": "blinddrop://round/current/results"])
                == .results(groupID: nil))
        #expect(PushRouter.link(from: ["deep_link": "blinddrop://record"]) == .record(groupID: nil))
        // `E19-03`: a reveal or results push for a non-active circle carries the same circle
        // prefix the URL scheme does (`docs/05` §5).
        #expect(PushRouter.link(from: ["deep_link": "blinddrop://circle/g_1/round/current"])
                == .round(groupID: "g_1"))
    }

    /// A payload with nothing we recognise does **nothing**, rather than falling back to the round.
    ///
    /// The cases are built inside the test rather than passed as `@Test(arguments:)`: an APNs
    /// payload is `[AnyHashable: Any]`, which is not `Sendable` and so cannot cross into a
    /// parameterised test — the same wall the app delegate hits, and the reason it lifts the link
    /// out as a `String` before hopping actors.
    @Test func anunrecognisedPayloadRoutesNowhere() {
        let payloads: [[AnyHashable: Any]] = [
            [:],
            ["deep_link": "blinddrop://nowhere"],
            ["deep_link": ""],
            ["deep_link": 7],
            ["kind": "reveal"],
        ]
        for payload in payloads {
            #expect(PushRouter.link(from: payload) == nil, "\(payload) should route nowhere")
        }
    }

    /// **A deep link never shortcuts a phase gate** (`docs/05` §5).
    ///
    /// A results push tapped at 21:30 does not push a results screen: it pops to the root and lets
    /// the server's phase decide what renders. And until the round has loaded it does nothing at
    /// all — which is the property that makes "never shortcuts" true rather than merely intended.
    @Test func aresultsPushDoesNotOpenResults() {
        let router = Router()
        PushRouter.receive(.results(groupID: nil), into: router, session: .ready)
        #expect(router.path.isEmpty, "nothing is pushed before the round has loaded")

        router.consume(session: .ready, roundIsLoaded: true)
        #expect(router.path.isEmpty, "and `results` is a phase of the round screen, never a push")
    }

    /// The Record is a real destination, and it still waits for the round.
    @Test func arecordPushWaitsForTheRoundAndThenPushes() {
        let router = Router()
        PushRouter.receive(.record(groupID: nil), into: router, session: .ready)
        #expect(router.path.isEmpty)

        router.consume(session: .ready, roundIsLoaded: true)
        #expect(router.path == [.record])
    }
}

/// A notification centre that answers from memory and shows nobody a dialog.
@MainActor
final class FakeNotificationAuthority: NotificationAuthority {
    enum Status { case notDetermined, authorized, denied }

    private let status: Status
    private let grants: Bool
    private(set) var didRequestAuthorization = false
    private(set) var didRegister = false
    private(set) var didClearDeliveredNotifications = false

    init(status: Status, grants: Bool) {
        self.status = status
        self.grants = grants
    }

    var isAuthorized: Bool { get async { status == .authorized } }
    var isNotDetermined: Bool { get async { status == .notDetermined } }

    func requestAuthorization() async -> Bool {
        didRequestAuthorization = true
        return grants
    }

    func registerForRemoteNotifications() {
        didRegister = true
    }

    func clearDeliveredNotifications() {
        didClearDeliveredNotifications = true
    }
}
