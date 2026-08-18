import SwiftUI
import Testing
@testable import BlindDrop

private let devices = SnapshotRenderer.Device.matrix

/// `docs/08` §2, §8: the explainer reached from every phase's `[?]` and from sign-in.
///
/// No `RoundContext` to key a fixture off, and no accent to vary — the page carries **both**
/// accents at once and always the same way round, because it is the legend (`CLAUDE.md` §2.5's
/// second exception): step 1 is amber, steps 2–4 are ultramarine, on every golden here. The one
/// thing that changes the page at all is the group's `reveal_hour`, and every golden is the
/// default (`RevealHour.default`, 20:00). `HowToTests` covers the arithmetic for a group with a
/// different one; this suite is only asking whether the words at that arithmetic's result lay
/// out (`docs/12` §1 — nothing truncates, nothing overlaps).
///
/// `HowTo-steps` is therefore the golden that has to be *looked at* rather than merely diffed:
/// it is the only picture of the two accents beside each other, and the only one where the
/// hairline down the numeral column either holds the four steps together or does not. The
/// contrast ratios behind that colouring are asserted separately, in `PaletteContrastTests`.
///
/// **The full page and `.accessibility5` never share a golden.** At that size the whole column
/// is over 9,800px tall on an SE and past 12,000px on the wide device — long enough that the
/// encoder cannot write the PNG at all (`SnapshotRenderer`'s `pngData`, and confirmed recording
/// this suite the first time: *"Could not encode … at 750×9806px"*). So the full page is only
/// asserted at the two sizes that fit, and `.accessibility5` is asserted block by block —
/// `HowToSheet.intro`, `.stepsCard`, `.scoringCard`, `.notesCard` are exposed for exactly this.
@MainActor
@Suite struct HowToSnapshotTests {

    /// The whole page, against `snapshotContent` — `ImageRenderer` drops everything inside a
    /// `ScrollView` silently rather than clipping it, so this points at the bare column the way
    /// every other scrolling screen's suite does (`SnapshotRenderer`).
    @Test(arguments: devices, [DynamicTypeSize.large, .accessibility1])
    func howToPlay(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "HowTo", device, size) { HowToSheet(close: {}).snapshotContent }
    }

    /// `.accessibility5`, one block at a time — the size `.accessibility1` and `.large` do not
    /// prove, and the size the full page cannot be one image at.
    @Test(arguments: devices)
    func howToPlayAtTheLargestSize(_ device: SnapshotRenderer.Device) {
        let sheet = HowToSheet(close: {})
        verify(named: "HowTo-intro", device, .accessibility5) { sheet.intro }
        verify(named: "HowTo-steps", device, .accessibility5) { sheet.stepsCard }
        verify(named: "HowTo-scoring", device, .accessibility5) { sheet.scoringCard }
        verify(named: "HowTo-notes", device, .accessibility5) { sheet.notesCard }
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
            in: "HowTo",
            sourceLocation: sourceLocation
        )
    }
}
