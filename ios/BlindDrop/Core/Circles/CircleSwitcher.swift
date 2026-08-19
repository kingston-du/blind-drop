import Foundation

/// The switcher's own read of `CircleStore.circles` (`E19-02`): which order the rows print in,
/// and whether the header needs its small mark. A value rather than logic inlined in the sheet,
/// so both are testable without a view.
struct CircleSwitcher: Equatable, Sendable {
    /// Needs-action circles first, **no visible section** — the order is the signal (`E19-02`).
    /// `Array.filter` preserves relative order, so each half keeps `CircleStore`'s own
    /// oldest-active-first order: two same-priority circles never swap places between openings
    /// for no reason.
    let rows: [CircleSummaryDTO]
    /// Whether some circle **other than** the one on screen wants the caller's attention — the
    /// header's mark never lights for the circle already in front of the caller, whose own
    /// badge already says what it is doing.
    let otherNeedsAction: Bool

    /// - Parameters:
    ///   - circles: `CircleStore.circles`, in the server's oldest-active-first order.
    ///   - activeID: the circle currently on screen.
    init(circles: [CircleSummaryDTO], activeID: String?) {
        rows = circles.filter(\.needsAction) + circles.filter { !$0.needsAction }
        otherNeedsAction = circles.contains { $0.needsAction && $0.id != activeID }
    }
}
