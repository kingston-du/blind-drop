import SwiftUI
import Testing
@testable import BlindDrop

private let devices = SnapshotRenderer.Device.matrix

/// `E19-02`. The sheet has to suit one circle as well as three, and a row's needs-action mark is
/// the only thing that varies its look below `.accessibility1` — everything else is the same
/// three tokens (`rowSurface`, `bodyLStrong`, `bodyM`) every other list row in the app already
/// uses. At `.accessibility1` and above the row stacks (`docs/12` §1: nothing truncates), which
/// is the layout this suite actually exists to catch — the single-line form let a name as short
/// as "Late Night Radio" truncate to four characters before this threshold existed.
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
            in: "CircleSwitcher",
            sourceLocation: sourceLocation
        )
    }
}
