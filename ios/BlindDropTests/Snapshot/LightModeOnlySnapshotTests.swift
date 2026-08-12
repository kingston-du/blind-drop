import SwiftUI
import Testing
@testable import BlindDrop

/// **Light mode only** (`CLAUDE.md` §2.4, `docs/07` intro), proven rather than asserted.
///
/// `PaletteContrastTests` already scans the source for a `colorScheme` branch and
/// `ios/scripts/lint.sh` rule 4 fails the build on one. Both are checks on the *text* of the
/// app. This is the check on its *output*: hand every component the environment of a phone in
/// dark mode and require the same pixels back.
///
/// It catches what a grep cannot. A system semantic colour — `Color.primary`, `.secondary`,
/// `.label`, an unstyled `Button`'s default tint, a `Material`, a `TextField`'s background —
/// carries a dark appearance without the word `colorScheme` appearing anywhere near it. Every
/// one of those would pass the lint and ship a component that quietly inverts on somebody's
/// phone at night. There is no test cheaper than this one that would notice.
///
/// It compares two renders rather than a render and a golden, deliberately: the goldens can be
/// re-recorded, and a re-record with a bug in it would take this assertion with it. Two renders
/// in the same process cannot drift apart for any reason except the thing being tested.
@MainActor
@Suite struct LightModeOnlySnapshots {

    /// One `@Test` per component would be nine copies of four lines; the components differ only
    /// in which view is built, and the builder cannot be an argument to `@Test(arguments:)`
    /// because a `some View` is not `Sendable`. The names are here so a failure says which one.
    @Test func nothingInTheComponentLibraryHasADarkAppearance() {
        assertIdentical("PrimaryButton") {
            VStack(spacing: Space.lg) {
                PrimaryButton("submit.action", accent: .sealed) {}
                PrimaryButton("reveal.action", accent: .revealed) {}
                PrimaryButton("reveal.action", accent: .revealed, isEnabled: false) {}
            }
        }
        assertIdentical("SecondaryButton") {
            SecondaryButton("sealed.replace") {}
        }
        assertIdentical("TrackRow") {
            TrackRow(track: .ribs, preview: .init(isPlaying: false) {}) {}
        }
        assertIdentical("FlightCard") {
            FlightCard(
                number: 4,
                track: .motionSickness,
                accent: .revealed,
                assignment: .unguessed,
                preview: .init(isPlaying: false) {},
                chooseGuess: {}
            )
        }
        assertIdentical("SealedCard") {
            SealedCard(track: .ribs, groupInitial: "H", remaining: "02:01:05")
        }
        assertIdentical("NameChip") {
            VStack(alignment: .leading, spacing: Space.sm) {
                NameChip(member: .cal, state: .unused) {}
                NameChip(member: .priya, state: .consumed(cardNumber: 3)) {}
                NameChip(member: .theo, state: .selected) {}
            }
        }
        assertIdentical("StatMeter") {
            StatMeter(value: 0.86, band: .openBook)
        }
        assertIdentical("ArtworkView") {
            ArtworkView(.ribs, size: Layout.Artwork.flightCard)
        }
        assertIdentical("EmptyState") {
            EmptyState(
                headline: "submit.headline",
                message: "submit.subhead",
                action: .init(title: "submit.action", accent: .sealed) {}
            )
        }
        assertIdentical("CountdownView") {
            CountdownFixture.view(remaining: 7265, size: .large)
        }
    }

    /// The control for the test above.
    ///
    /// A test that cannot fail is worse than no test, and this one guards a product-defining
    /// rule (`CLAUDE.md` §2.4) — so it is worth proving that the harness would notice. A single
    /// `Color.primary`, which is the most likely way a dark appearance would actually get into
    /// this app, has to come out different. If this ever passes at zero difference, the
    /// environment is not reaching `ImageRenderer` and every assertion above has quietly become
    /// a comparison of two identical light renders.
    @Test func theDarkModeCheckCanFail() {
        let semantic = Text(verbatim: "Sealed").foregroundStyle(Color.primary)
        let light = SnapshotRenderer.image(
            of: semantic, device: .iPhoneSE, typeSize: .large, colorScheme: .light
        )
        let dark = SnapshotRenderer.image(
            of: semantic, device: .iPhoneSE, typeSize: .large, colorScheme: .dark
        )
        let difference = SnapshotRenderer.differingFraction(light, dark)
        #expect((difference ?? 0) > 0, "a system semantic colour rendered identically in both appearances")
    }

    /// Renders the same view in both appearances and requires the bytes to match exactly.
    ///
    /// **Zero tolerance**, unlike the golden comparison. The two renders come out of the same
    /// process, the same fonts and the same layout pass, so there is no antialiasing drift to
    /// absorb: any difference at all is a colour that changed, which is the whole finding.
    private func assertIdentical(
        _ name: String,
        sourceLocation: SourceLocation = #_sourceLocation,
        @ViewBuilder content: () -> some View
    ) {
        let light = SnapshotRenderer.image(
            of: content(), device: .iPhoneSE, typeSize: .large, colorScheme: .light
        )
        let dark = SnapshotRenderer.image(
            of: content(), device: .iPhoneSE, typeSize: .large, colorScheme: .dark
        )
        guard let difference = SnapshotRenderer.differingFraction(light, dark) else {
            Issue.record("\(name): the two renders are different sizes", sourceLocation: sourceLocation)
            return
        }
        #expect(
            difference == 0,
            """
            \(name) renders differently in dark mode — \(difference * 100)% of pixels. A system \
            semantic colour has got in; every colour must come from Palette (docs/07 §2).
            """,
            sourceLocation: sourceLocation
        )
    }
}
