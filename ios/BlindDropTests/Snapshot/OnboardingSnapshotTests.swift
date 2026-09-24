import SwiftUI
import Testing
@testable import BlindDrop

/// File-scope rather than members of the suite: `@Test(arguments:)` evaluates its arguments
/// outside the actor the suite is isolated to.
private let devices = SnapshotRenderer.Device.matrix
private let sizes = SnapshotRenderer.typeSizes

/// `E09-02`'s verify line — *"snapshot at three type sizes"* — extended across `docs/12` §8's
/// full matrix, plus the three screens `E09-03` and `E09-04` add.
///
/// Every screen's `snapshotContent` is rendered rather than its `body`: the screens supply
/// their own `Layout.screenInset` in `body`, and `SnapshotRenderer` supplies one too, so a
/// golden of the body would be indented 40pt and wrap titles that fit perfectly well on the
/// device.
///
/// What the matrix is for here is one claim: *"nothing truncates and nothing overlaps"*
/// (`docs/12` §1). These are the app's only form screens, and a form is where that claim is
/// hardest — a label, a control and a help line under it, three times, on a 375pt screen at
/// `.accessibility5`.
///
/// **What these goldens cannot show.** `ImageRenderer` draws `TextField` and `Menu` as a yellow
/// "unsupported view" placeholder rather than as themselves — they are UIKit-backed, and the
/// renderer has no host window to build them in. The placeholder occupies the control's **real
/// frame**, so everything these goldens are actually for still holds: the rhythm, the reflow,
/// the wrapping of every label and help line around them, and the fact that a row grows rather
/// than clips at `.accessibility5`. What is not covered is the glyphs *inside* those two
/// controls. The alternative — branching the components on a test-only flag so they draw a
/// `Text` instead — would mean the goldens were pictures of something the app never renders,
/// which is worse than a picture with two boxes in it.
@MainActor
@Suite struct OnboardingSnapshots {

    // MARK: - 1.1, sign in

    /// The one screen before there is a session, so it has no `snapshotContent` to skip a
    /// container's inset — nothing wraps it yet. What the golden is actually for is the title
    /// block's position: capped rather than plain leading spacer (`SignInScreen`'s own doc),
    /// so it sits close under the help button rather than centred low by however much taller
    /// the App Review link's row is than the help row's.
    @Test(arguments: devices, sizes)
    func signIn(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "SignIn", device, size) {
            SignInScreen().environment(AppEnvironment())
        }
    }

    // MARK: - 1.2, the name

    @Test(arguments: devices, sizes)
    func displayName(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "DisplayName", device, size) {
            DisplayNameScreen(store: OnboardingFixture.store()).snapshotContent
        }
    }

    /// The state the inline error is drawn in (`docs/08` §1.2 — under the field, in `alert`,
    /// never a modal). A typed name past 24 characters, which is the one error the screen shows
    /// without having asked the server anything.
    @Test(arguments: devices, sizes)
    func displayNameTooLong(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "DisplayName-toolong", device, size) {
            DisplayNameScreen(store: OnboardingFixture.store {
                $0.name = String(repeating: "a", count: 25)
            }).snapshotContent
        }
    }

    // MARK: - 1.3, join or create

    @Test(arguments: devices, sizes)
    func joinOrCreate(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "JoinOrCreate", device, size) {
            JoinOrCreateScreen(store: OnboardingFixture.store()).snapshotContent
        }
    }

    /// **The common case since App Review's guideline 4 fix**: the name came from Apple, 1.2
    /// was skipped, and this is the first screen that shows the name the circle will guess
    /// with. What this golden proves is that the row reads as a quiet statement under the title
    /// rather than a second control competing with the code field — and, at `.accessibility5`,
    /// that it reflows to two lines rather than floating **Change** beside a wrapped sentence.
    @Test(arguments: devices, sizes)
    func joinOrCreatePlayingAs(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "JoinOrCreate-playingas", device, size) {
            JoinOrCreateScreen(store: OnboardingFixture.store(), playingAs: "Ana").snapshotContent
        }
    }

    /// The other end of the row: a name at `DisplayName.maximumLength`, which is the longest one
    /// the server will store and therefore the longest this row can ever be asked to draw.
    ///
    /// A separate golden rather than a longer fixture on the one above, because the two are
    /// different claims. That one is what almost everybody sees; this one is the reflow doing
    /// its job at `.large`, where nothing else on the screen is under pressure and a row that
    /// simply ran off the edge would be easy to miss.
    @Test(arguments: devices, sizes)
    func joinOrCreatePlayingAsLongName(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "JoinOrCreate-playingas-long", device, size) {
            JoinOrCreateScreen(
                store: OnboardingFixture.store(),
                playingAs: String(repeating: "a", count: DisplayName.maximumLength)
            ).snapshotContent
        }
    }

    /// Arrived by link: the code is in the field and the button is live (`docs/05` §5). The
    /// golden is what somebody who tapped an invite actually sees before touching anything.
    @Test(arguments: devices, sizes)
    func joinOrCreatePrefilled(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "JoinOrCreate-prefilled", device, size) {
            JoinOrCreateScreen(store: OnboardingFixture.store {
                $0.prefill(code: "K7MQ2X")
            }).snapshotContent
        }
    }

    // The `NOT_FOUND` state has no golden of its own on purpose. Its line is drawn by the same
    // treatment `DisplayName-toolong` already pins — an `alert`-coloured line under the field —
    // and reaching it needs a stubbed transport, which is a lot of apparatus for a picture that
    // would prove something a unit test already proves (`OnboardingStoreTests`). A golden that
    // needs a test-only hook in production code to exist is a golden that costs more than it
    // is worth.

    // MARK: - 1.4, create and invite

    /// Three labelled controls, each with its consequence underneath. The `.accessibility5`
    /// golden is the one that matters: the timezone help line is the longest string in
    /// onboarding, and it sits between two controls that both have to stay reachable.
    @Test(arguments: devices, sizes)
    func createGroup(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "CreateGroup", device, size) {
            CreateGroupScreen(store: OnboardingFixture.store {
                $0.groupName = "The Cove"
                $0.timezone = "America/New_York"
                $0.revealHour = RevealHour.default
            }).snapshotContent
        }
    }

    /// The code in `displayL` (`docs/08` §1.4). Six characters of the display face is the
    /// largest type in onboarding, and the SE at `.accessibility5` is where it either fits on
    /// one line or does not.
    @Test(arguments: devices, sizes)
    func inviteCode(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "InviteCode", device, size) {
            InviteCodeScreen(store: OnboardingFixture.store(), group: OnboardingFixture.group)
                .snapshotContent
        }
    }

    // MARK: - Rendering

    private func verify(
        named name: String,
        _ device: SnapshotRenderer.Device,
        _ size: DynamicTypeSize,
        sourceLocation: SourceLocation = #_sourceLocation,
        @ViewBuilder content: () -> some View
    ) {
        let image = SnapshotRenderer.image(of: content(), device: device, typeSize: size)
        SnapshotRenderer.verify(
            image,
            named: "\(name)-\(device.name)-\(size.snapshotName)",
            in: "Onboarding",
            sourceLocation: sourceLocation
        )
    }
}

// MARK: - Fixtures

/// Stores in the states the goldens are pictures of.
///
/// Built on a real `AppEnvironment`, which touches no network and no keychain until something
/// asks it to — and nothing here asks. That is cheaper than a second set of auth doubles in a
/// target whose whole job is to draw pictures.
@MainActor
enum OnboardingFixture {

    static func store(_ configure: (OnboardingStore) -> Void = { _ in }) -> OnboardingStore {
        let env = AppEnvironment()
        let store = OnboardingStore(api: env.api, session: env.session)
        configure(store)
        return store
    }

    static let group = GroupDTO(
        id: "g_1",
        name: "The Cove",
        timezone: "America/New_York",
        revealHour: 20,
        inviteCode: "K7MQ2X",
        isAdmin: true,
        members: [MemberDTO(userID: "u_ana", displayName: "Ana")]
    )
}
