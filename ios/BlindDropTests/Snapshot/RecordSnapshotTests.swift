import SwiftUI
import Testing
@testable import BlindDrop

@MainActor
@Suite struct RecordSnapshotTests {
    @Test(arguments: SnapshotRenderer.Device.matrix)
    func archiveMatrix(_ device: SnapshotRenderer.Device) throws {
        let record = try JSONDecoder.api.decode(
            RecordDTO.self,
            from: fixture("record")
        )
        for typeSize in SnapshotRenderer.typeSizes {
            let image = SnapshotRenderer.image(
                of: RecordSnapshotContent(days: Array(record.days.prefix(1))),
                device: device,
                typeSize: typeSize
            )
            SnapshotRenderer.verify(
                image,
                named: "Record-\(device.name)-\(name(typeSize))",
                in: "Record"
            )
        }
    }

    @Test(arguments: SnapshotRenderer.Device.matrix)
    func filteredEmptyMatrix(_ device: SnapshotRenderer.Device) {
        for typeSize in SnapshotRenderer.typeSizes {
            let image = SnapshotRenderer.image(
                of: Text(verbatim: Copy.format("record.empty.filtered", "Ana"))
                    .typeStyle(.displayM)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true),
                device: device,
                typeSize: typeSize
            )
            SnapshotRenderer.verify(
                image,
                named: "Record-empty-filtered-\(device.name)-\(name(typeSize))",
                in: "Record"
            )
        }
    }

    private func fixture(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try Data(contentsOf: root.appending(path: "Fixtures/payloads/\(name).json"))
    }

    private func name(_ size: DynamicTypeSize) -> String {
        switch size {
        case .large: "large"
        case .accessibility1: "accessibility1"
        case .accessibility5: "accessibility5"
        default: "other"
        }
    }
}

private struct RecordSnapshotContent: View {
    let days: [RecordDayDTO]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.none) {
            ForEach(days) { day in
                // The sticky strip the screen draws, background included: a header pinned over a
                // scrolling list has to be visibly on top of it rather than floating in it.
                SectionLabel(verbatim: GroupCalendar(timezone: "America/New_York")
                    .shareDate(localDate: day.localDate) ?? day.localDate)
                    .padding(.vertical, Space.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.paperSunk)

                let entries = Array(day.entries.prefix(3))
                ForEach(entries) { entry in
                    HStack(spacing: Space.sm) {
                        TrackRow(
                            track: entry.track,
                            preview: entry.track.previewURL.map { _ in
                                TrackRow.Preview(isPlaying: false) {}
                            },
                            attribution: entry.displayName
                        )
                        // `ImageRenderer` cannot host a live `Menu`; render the exact label so
                        // the golden checks the intended row layout without substituting its
                        // yellow "unsupported control" diagnostic for the ellipsis.
                        Image(systemName: "ellipsis")
                            .foregroundStyle(Palette.inkDim)
                            .minimumTouchTarget()
                    }
                    if entry.id != entries.last?.id { Rule(color: Palette.edge) }
                }
            }

            HStack(spacing: Space.sm) {
                OutlineButton("record.export.spotify") {}
                OutlineButton("record.export.apple") {}
            }
            .padding(.top, Layout.blockGap)
        }
    }
}
