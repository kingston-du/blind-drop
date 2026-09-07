import SwiftUI
import Testing
@testable import BlindDrop

private let devices = SnapshotRenderer.Device.matrix

/// `E19-02`, redrawn by `E42-01`. The sheet has to suit one circle as well as three. At
/// `.accessibility1` and above the row stacks (`docs/12` §1: nothing truncates), which is the
/// layout this suite actually exists to catch — the single-line form let a name as short as
/// "Late Night Radio" truncate to four characters before this threshold existed.
///
/// `E42-01` gave these goldens a second job. A row now carries a **phase pip** whose colour is
/// `PhaseAccent(myState).mark` and whose fill is `needsAction`, so `threeCircles` below is
/// deliberately one of each: an amber filled pip (`drop`, wanting the caller), an amber ring
/// (`sealed`, settled) and an ultramarine ring (`answers`, past the reveal). That combination is
/// the `CLAUDE.md` §2.5 carve-out this sheet holds — **both accents on one screen** — and these
/// images are what stops it drifting past the bound: if a golden ever shows an accent on the
/// selection rail, on a state word, or on a button, the carve-out has been exceeded.
///
/// The stacked cases are the pip's own regression too. Centred against a wrapped two-line state
/// label it floats between the lines and reads as a bullet; `stateLabel` boxes it into the first
/// line to stop that, and `-accessibility5` is the size that proves it.
@MainActor
@Suite struct CircleSwitcherSnapshotTests {

    private func circle(_ name: String, needsAction: Bool = false, state: CircleState = .sealed) -> CircleSummaryDTO {
        CircleSummaryDTO(id: name, name: name, myState: state, needsAction: needsAction)
    }

    private var threeCircles: [CircleSummaryDTO] {
        // Already in switcher order — needs-action first — the same shape `CircleSwitcher` hands
        // the real sheet, so this golden is the row layout and not the sort.
        [
            circle("Late Night Radio", needsAction: true, state: .drop),
            circle("The Cove", state: .sealed),
            circle("Sunday Crew", state: .answers),
        ]
    }

    private var invitations: [InvitationDTO] {
        [
            InvitationDTO(
                id: "c0000000-0000-4000-8000-000000000001",
                group: InvitationGroupDTO(id: "g-invite", name: "After Hours"),
                invitedBy: MemberDTO(userID: "ana", displayName: "Ana")
            ),
        ]
    }

    @Test(arguments: devices, [DynamicTypeSize.large, .accessibility1, .accessibility5])
    func threeCirclesOneNeedingAction(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        let sheet = CircleSwitcherSheet(
            rows: threeCircles, activeID: "The Cove", select: { _ in }, close: {}
        )
        verify(named: "CircleSwitcher-three", device, size) { sheet.snapshotContent(typeSize: size) }
    }

    /// The one-circle case (`docs/08`: *"suits one circle as well as three"*) — no needs-action
    /// mark, and the only row is also the active one. Includes `.accessibility5` (review): the
    /// longest name at the largest size is the combination most likely to break the sheet's
    /// measured-height math, and it is the one the three-circle set's own `.accessibility5`
    /// cases do not stand in for — one row measures differently than three.
    @Test(arguments: devices, [DynamicTypeSize.large, .accessibility1, .accessibility5])
    func oneCircle(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        let sheet = CircleSwitcherSheet(
            rows: [circle("Late Night Radio")], activeID: "Late Night Radio", select: { _ in }, close: {}
        )
        verify(named: "CircleSwitcher-one", device, size) { sheet.snapshotContent(typeSize: size) }
    }

    /// **Two circles in the same phase, differing only in `needsAction`** (`E42-01`).
    ///
    /// The case the pip's fill/ring distinction exists for, and the one `threeCircles` above
    /// cannot stand in for: its three rows are three *different* hues, so a regression that
    /// quietly drew the ring as a slightly soft dot would still look correct there — you would
    /// read the difference off the colour without noticing the shape had stopped carrying it.
    /// Here both pips are ultramarine and the state word is `Guess` twice, so **shape and weight
    /// are the only two channels left**. If a golden of this ever shows two rows that look alike,
    /// the sighted half of `a11y.switcher.attention` has gone missing.
    ///
    /// `.large` and `.accessibility5` only: `.accessibility1` is the same stacked layout as
    /// `.accessibility5` and this test is about the pip, not the reflow threshold.
    @Test(arguments: devices, [DynamicTypeSize.large, .accessibility5])
    func sameStateDifferentAttention(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        let rows = [
            circle("Sunday Crew", needsAction: true, state: .guess),
            circle("The Cove", state: .guess),
        ]
        let sheet = CircleSwitcherSheet(
            rows: rows, activeID: "The Cove", select: { _ in }, close: {}
        )
        verify(named: "CircleSwitcher-attention", device, size) { sheet.snapshotContent(typeSize: size) }
    }

    /// Pending invitations are deliberately a separate headed section rather than a fourth
    /// circle row: the recipient has not joined yet, and the two available actions must still
    /// fit at the largest supported type size.
    @Test(arguments: devices, [DynamicTypeSize.large, .accessibility5])
    func pendingInvitation(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        let sheet = CircleSwitcherSheet(
            rows: threeCircles,
            activeID: "The Cove",
            select: { _ in },
            invitations: invitations,
            close: {}
        )
        verify(named: "CircleSwitcher-invite", device, size) { sheet.snapshotContent(typeSize: size) }
    }

    private func verify(
        named name: String,
        _ device: SnapshotRenderer.Device,
        _ size: DynamicTypeSize,
        sourceLocation: SourceLocation = #_sourceLocation,
        @ViewBuilder content: () -> some View
    ) {
        // The sheet loads invitations through the shared environment in production. Keep the
        // bare snapshot content equally complete; ImageRenderer does not run its `.task`.
        let image = SnapshotRenderer.image(
            of: content().environment(AppEnvironment()), device: device, typeSize: size
        )
        SnapshotRenderer.verify(
            image,
            named: "\(name)-\(device.name)-\(size.snapshotName)",
            in: "CircleSwitcher",
            sourceLocation: sourceLocation
        )
    }
}
