import SwiftUI
import Testing
@testable import BlindDrop

private let devices = SnapshotRenderer.Device.matrix

/// The second-group form is deliberately a short sheet: name, a stated timezone, and reveal
/// hour. This pins its long timezone help at the standard Dynamic Type matrix before keyboard
/// interaction is exercised on the simulator.
@MainActor
@Suite struct StartGroupSnapshotTests {
    @Test(arguments: devices, [DynamicTypeSize.large, .accessibility1, .accessibility5])
    func startGroup(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        let env = AppEnvironment()
        let store = StartGroupStore(api: env.api, circles: env.circles)
        store.name = "Late Night Radio"
        let image = SnapshotRenderer.image(
            of: StartGroupForm(store: store, close: {}).snapshotContent,
            device: device,
            typeSize: size
        )
        SnapshotRenderer.verify(
            image,
            named: "StartGroup-\(device.name)-\(size.snapshotName)",
            in: "Onboarding",
            sourceLocation: #_sourceLocation
        )
    }
}
