import SwiftUI
import Testing
@testable import BlindDrop

@MainActor
@Suite struct InsightsSnapshotTests {

    @Test(arguments: SnapshotRenderer.Device.matrix, SnapshotRenderer.typeSizes)
    func populated(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) throws {
        let insights = try populatedInsights()
        verify(named: "Insights-populated", device, size) {
            InsightsContent(insights: insights)
        }
    }

    @Test(arguments: SnapshotRenderer.Device.matrix, SnapshotRenderer.typeSizes)
    func empty(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "Insights-empty", device, size) {
            InsightsContent(
                insights: InsightsDTO(
                    yourReads: [],
                    readsYou: [],
                    mutualRecognition: [],
                    mutualMisses: [],
                    confusion: InsightConfusionDTO(scoredRounds: 0, minimumRounds: 36, pairs: [])
                )
            )
        }
    }

    private func verify(
        named name: String,
        _ device: SnapshotRenderer.Device,
        _ size: DynamicTypeSize,
        sourceLocation: SourceLocation = #_sourceLocation,
        @ViewBuilder content: () -> some View
    ) {
        SnapshotRenderer.verify(
            SnapshotRenderer.image(of: content(), device: device, typeSize: size),
            named: "\(name)-\(device.name)-\(size.snapshotName)",
            in: "Insights",
            sourceLocation: sourceLocation
        )
    }

    private func populatedInsights() throws -> InsightsDTO {
        let json = """
        {
          "your_reads":[
            {"member":{"user_id":"u_cal","display_name":"Cal"},"correct":10,"possible":14,"lower_bound":0.4535,"upper_bound":0.8828},
            {"member":{"user_id":"u_gus","display_name":"Gus"},"correct":2,"possible":14,"lower_bound":0.0401,"upper_bound":0.3994}
          ],
          "reads_you":[
            {"member":{"user_id":"u_hal","display_name":"Hal"},"correct":11,"possible":14,"lower_bound":0.5241,"upper_bound":0.9243}
          ],
          "mutual_recognition":[{"members":[{"user_id":"u_ana","display_name":"Ana"},{"user_id":"u_hal","display_name":"Hal"}],"correct":19,"possible":28}],
          "mutual_misses":[{"members":[{"user_id":"u_dee","display_name":"Dee"},{"user_id":"u_gus","display_name":"Gus"}],"correct":0,"possible":28}],
          "confusion":{"scored_rounds":36,"minimum_rounds":36,"pairs":[{"actual_member":{"user_id":"u_dee","display_name":"Dee"},"mistaken_for_member":{"user_id":"u_gus","display_name":"Gus"},"count":8}]}
        }
        """
        return try JSONDecoder.api.decode(InsightsDTO.self, from: Data(json.utf8))
    }
}
