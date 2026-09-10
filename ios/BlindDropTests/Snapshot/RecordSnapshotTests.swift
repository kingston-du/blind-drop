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
                // The sticky night header the screen draws, background and rule included. It is
                // `paper` now, with a bottom `edge` rule instead of a darker fill — see
                // `RecordScreen.dateHeader`. A cued night carries its cue under the date in the
                // face the cue wears everywhere else (`docs/18-CUES.md` §7), and the trailing
                // chevron is the header's own: the whole strip is the button into that night's
                // results (owner, 2026-09-03). The `Button` itself is not reproduced, only its
                // label. What the golden checks is that the chevron and a 24pt date share a row
                // without either starving the other at `.accessibility5`, which is the layout
                // risk the change actually carries — and it carries more of it now than it did
                // when the date was 11pt.
                HStack(alignment: .center, spacing: Space.sm) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(verbatim: GroupCalendar(timezone: "America/New_York")
                            .shareDate(localDate: day.localDate) ?? day.localDate)
                            .typeStyle(.displayS)
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let cue = day.cue {
                            Text(verbatim: cue.text)
                                .typeStyle(.bodyLStrong)
                                .foregroundStyle(Palette.inkDim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(Font(Typography.uiFont(.bodyLStrong)))
                        .foregroundStyle(Palette.inkSubtle)
                }
                .padding(.top, Space.xl)
                .padding(.bottom, Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.paper)
                .overlay(alignment: .bottom) { Rule(color: Palette.edge) }

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
        }
    }
}
