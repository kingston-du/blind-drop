import SwiftUI
import Testing
@testable import BlindDrop

/// `E11-03`'s worst case: the iPhone SE with all twelve members and the largest supported text.
///
/// The flight and the pool are separate scrollers. The test asserts their entire addressable
/// sets, rather than a visible subset, because a bottom sheet that only exposes its first two
/// rows has not met the accessibility requirement merely because the first screenshot looks
/// orderly. `NameChip` and `FlightCard` use these stable identifiers in the UI hierarchy, so
/// E14's end-to-end VoiceOver pass can walk this same manifest without rediscovering names.
@MainActor
@Suite struct A11yReachabilityTests {

    @Test func seWithTwelveMembersAtAccessibilityFiveHasAnAddressForEveryCardAndChip() {
        let store = RevealFixture.store(cardCount: 12, myCardNumber: 7)
        let layout = NamePoolLayout(dynamicTypeSize: .accessibility5)

        #expect(layout == .verticalGrid)
        #expect(store.cards.map(\.cardNumber) == Array(1...12))
        #expect(store.pool.count == 11, "the caller is not in their own eleven-name pool")
        #expect(Set(store.pool.map(\.userID)).count == 11)
        #expect(store.pool.allSatisfy { !$0.userID.isEmpty })
        #expect(store.cards.allSatisfy { $0.cardNumber > 0 })

        // Both interactive shapes explicitly expand to 44pt. The grid does not shrink its
        // children, and the flight stays in its own scroll view above the capped pool.
        #expect(Layout.minimumTouchTarget >= 44)
        #expect(Layout.chipHeight < Layout.minimumTouchTarget)
        #expect(Layout.namePoolMaximumHeightFraction == 0.4)
    }

    @Test(arguments: [
        (DynamicTypeSize.large, NamePoolLayout.horizontalScroll),
        (.accessibility2, .horizontalScroll),
        (.accessibility3, .verticalGrid),
        (.accessibility5, .verticalGrid),
    ])
    func thePoolChangesOnlyAtTheAccessibilityThreeBoundary(
        size: DynamicTypeSize,
        expected: NamePoolLayout
    ) {
        #expect(NamePoolLayout(dynamicTypeSize: size) == expected)
    }
}
