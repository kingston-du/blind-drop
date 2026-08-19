import Foundation
import Testing
@testable import BlindDrop

/// `CircleSwitcher` — `E19-02`'s ordering and the header's attention mark, both pure so neither
/// needs a view to assert.
@Suite struct CircleSwitcherTests {

    private func circle(_ id: String, needsAction: Bool = false, state: CircleState = .sealed) -> CircleSummaryDTO {
        CircleSummaryDTO(id: id, name: id, myState: state, needsAction: needsAction)
    }

    /// Needs-action circles sort first, with no reshuffling beyond that — `docs/08`: *"the order
    /// is the signal"*, and there is no visible heading to tell the two halves apart.
    @Test func needsActionCirclesSortFirst() {
        let circles = [circle("a"), circle("b", needsAction: true), circle("c")]

        let switcher = CircleSwitcher(circles: circles, activeID: nil)

        #expect(switcher.rows.map(\.id) == ["b", "a", "c"])
    }

    /// Each half keeps the server's own order — a stable partition, not a re-sort. Two
    /// needs-action circles do not swap places between openings for no reason.
    @Test func eachHalfKeepsTheServersOrder() {
        let circles = [
            circle("a", needsAction: true), circle("b"), circle("c", needsAction: true), circle("d"),
        ]

        let switcher = CircleSwitcher(circles: circles, activeID: nil)

        #expect(switcher.rows.map(\.id) == ["a", "c", "b", "d"])
    }

    /// No circle needs the caller — the order is untouched.
    @Test func noneNeedingActionLeavesTheOrderAlone() {
        let circles = [circle("a"), circle("b"), circle("c")]

        let switcher = CircleSwitcher(circles: circles, activeID: nil)

        #expect(switcher.rows.map(\.id) == ["a", "b", "c"])
    }

    /// The header's mark is about **some other** circle — never the one already on screen, whose
    /// own badge already says what it is doing.
    @Test func otherNeedsActionIgnoresTheActiveCircle() {
        let circles = [circle("a", needsAction: true), circle("b")]

        #expect(CircleSwitcher(circles: circles, activeID: "a").otherNeedsAction == false)
        #expect(CircleSwitcher(circles: circles, activeID: "b").otherNeedsAction == true)
        #expect(CircleSwitcher(circles: circles, activeID: nil).otherNeedsAction == true)
    }

    /// Nothing needs attention anywhere — the mark stays off.
    @Test func otherNeedsActionIsFalseWhenNothingDoes() {
        let circles = [circle("a"), circle("b")]

        #expect(CircleSwitcher(circles: circles, activeID: "a").otherNeedsAction == false)
    }

    /// Every `CircleState` the server can send resolves to its own copy-deck word — the row's
    /// entire second column (`docs/11` §The switcher).
    @Test(arguments: [
        (CircleState.drop, "Drop a song"),
        (.sealed, "Sealed"),
        (.guess, "Guess"),
        (.answers, "Answers"),
        (.voided, "Voided"),
    ])
    func everyCircleStateHasARowWord(_ pair: (CircleState, String)) {
        #expect(Copy.switcherState(pair.0) == pair.1)
    }
}
