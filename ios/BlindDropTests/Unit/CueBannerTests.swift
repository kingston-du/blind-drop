import Foundation
import SwiftUI
import Testing
@testable import BlindDrop

/// `CueBanner.prominentLabelWidth`, and the one screen that spends it.
///
/// The quick pass sizes its album artwork from what the cue has left to wrap into, so the inline
/// *"Cue"* label is not decoration there — it is an input to a layout. Get the number wrong and
/// nothing looks broken: the cue simply wraps one line further than the artwork was sized for,
/// on the nights with a long cue, at the text sizes nobody is testing by hand. So the number is
/// measured rather than assumed, and measured against what SwiftUI actually draws.
@MainActor
@Suite struct CueBannerTests {

    /// The measurement agrees with the rendered label.
    ///
    /// The whole risk in `prominentLabelWidth` is that it reproduces `TypeStyleModifier` by hand:
    /// uppercasing, the mono face, and tracking scaled with the point size. Any of the three left
    /// out reads short — tracking alone by about four points on a three-character word. This
    /// renders the real `SectionLabel` and compares, so the reproduction cannot drift from the
    /// thing it reproduces without failing here.
    ///
    /// The size is driven through `\.dynamicTypeSize` rather than the hosting controller's
    /// `traitOverrides`, because `TypeStyleModifier` resolves its font from that environment key
    /// and nothing else. Overriding the UIKit trait leaves the SwiftUI value alone: the first
    /// version of this test did exactly that and measured the same 24.3pt at all three sizes,
    /// which looked like a broken measurement and was a broken harness.
    @Test(arguments: [DynamicTypeSize.large, .xxxLarge, .accessibility5])
    func theMeasurementMatchesTheRenderedLabel(_ size: DynamicTypeSize) {
        let host = UIHostingController(
            rootView: SectionLabel(LocalizedStringKey("round.cue.label.short"))
                .fixedSize()
                .environment(\.dynamicTypeSize, size)
        )
        let rendered = host.sizeThatFits(in: CGSize(width: 1000, height: 1000)).width
        let measured = CueBanner.prominentLabelWidth(for: UIContentSizeCategory(size))

        #expect(abs(rendered - measured) <= 1.5,
                """
                The inline cue label draws \(rendered)pt at \(size) but prominentLabelWidth \
                says \(measured)pt. QuickPassScreen reserves artwork from the second number, so \
                the cue will wrap into a width that is not the one it has.
                """)
    }

    /// It scales. A constant would have frozen the label at its 11pt width and starved the cue
    /// of about forty points at the largest accessibility size.
    @Test func theLabelGrowsWithDynamicType() {
        #expect(CueBanner.prominentLabelWidth(for: UIContentSizeCategory(.accessibility5))
                > CueBanner.prominentLabelWidth(for: UIContentSizeCategory(.large)))
    }

    /// The label costs width **or** height, never both and never neither.
    ///
    /// This is the invariant `QuickPassScreen` leans on: it subtracts `width` from the column and
    /// adds `height` to the strip unconditionally, which is only correct because exactly one of
    /// them is zero at any given size. A change that made both non-zero would take the cost twice
    /// and shrink the artwork on every cued night.
    @Test(arguments: DynamicTypeSize.allCases)
    func theLabelCostsWidthOrHeightButNeverBoth(_ size: DynamicTypeSize) {
        let cost = CueBanner.prominentLabelCost(for: size)

        if CueBanner.prominentStacksLabel(at: size) {
            #expect(cost.width == 0)
            #expect(cost.height > 0, "a stacked label occupies a line the reserve has to pay for")
        } else {
            #expect(cost.height == 0)
            #expect(cost.width > 0, "an inline label narrows the column the cue wraps into")
        }
    }

    /// The boundary is the one the quick pass reflows at, not a second one beside it.
    ///
    /// Two thresholds a point apart would mean a size at which the strip has moved under the
    /// close button but the label still thinks it is sharing a row with one.
    @Test func theLabelStacksExactlyWhereTheStripDoes() {
        #expect(CueBanner.prominentStacksLabel(at: .xxxLarge) == false)
        #expect(CueBanner.prominentStacksLabel(at: .accessibility1))
    }

    /// The key resolves to copy rather than printing itself onto the strip.
    @Test func theShortLabelIsInTheDeck() {
        #expect(Copy.string("round.cue.label.short") == "Cue")
    }

    /// The quick pass actually spends the width the component publishes.
    ///
    /// A source scan, in the shape `RoundChromeTests` already uses, because `cueReserve` is
    /// private to a `View` and the coupling it guards is exactly the kind that rots silently:
    /// the reserve subtracting a label the strip no longer draws, or drawing one it never
    /// subtracted, both compile and both only show up as an album cover that is the wrong size
    /// on cued nights.
    @Test func theQuickPassReservesWidthForTheLabel() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Unit
            .deletingLastPathComponent()   // BlindDropTests
            .deletingLastPathComponent()   // ios
            .appending(path: "BlindDrop/Features/Reveal/QuickPass/QuickPassScreen.swift")
        let source = try String(contentsOf: file, encoding: .utf8)

        #expect(source.contains("CueBanner.prominentLabelCost"),
                """
                QuickPassScreen no longer spends CueBanner's published label cost. Either the \
                label is gone from CueBanner.prominent — in which case delete this test with it — \
                or the artwork is being sized against a column the cue does not have.
                """)
    }
}
