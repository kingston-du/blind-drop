import Foundation
import Testing
@testable import BlindDrop

/// `CallSheetDetent.resolved` is the committing-drag decision `GuessSheet`'s `dragGesture` hands
/// off to on release (`E26-02`): whether a projected velocity crossed the open/peek threshold,
/// not whether the raw drag distance did. `E17-10` could only exercise the non-committing
/// (springback) case informally, on device; this pins all three cases — both committing
/// directions and the springback — directly against the function, plus the `Space.xxl` floor
/// that keeps a small sheet from committing on a hair-trigger threshold.
@Suite struct CallSheetDetentTests {

    /// A generous `collapseDistance` so `threshold` (`collapseDistance * 0.2`) sits well above
    /// the `Space.xxl` floor and the test is exercising the scaled threshold, not the floor.
    private let collapseDistance: CGFloat = 400 // threshold == 80

    @Test func openCommitsToPeekWhenProjectionCrossesTheThresholdDownward() {
        let resolved = CallSheetDetent.resolved(
            from: .open,
            predictedEndTranslation: 150,
            collapseDistance: collapseDistance
        )
        #expect(resolved == .peek)
    }

    @Test func peekCommitsToOpenWhenProjectionCrossesTheThresholdUpward() {
        let resolved = CallSheetDetent.resolved(
            from: .peek,
            predictedEndTranslation: -150,
            collapseDistance: collapseDistance
        )
        #expect(resolved == .open)
    }

    @Test func releaseThatDoesNotCrossTheThresholdSpringsBackUnchanged() {
        // Well inside the threshold in both directions and both starting detents — a short,
        // slow release that should never flip the sheet.
        #expect(CallSheetDetent.resolved(
            from: .open,
            predictedEndTranslation: 40,
            collapseDistance: collapseDistance
        ) == .open)
        #expect(CallSheetDetent.resolved(
            from: .peek,
            predictedEndTranslation: -40,
            collapseDistance: collapseDistance
        ) == .peek)
    }

    @Test func exactlyAtTheThresholdDoesNotCommit() {
        // The comparison is strict (`>` / `<`), not `>=` / `<=` — landing precisely on the
        // threshold is a springback, not a commit.
        #expect(CallSheetDetent.resolved(
            from: .open,
            predictedEndTranslation: 80,
            collapseDistance: collapseDistance
        ) == .open)
        #expect(CallSheetDetent.resolved(
            from: .peek,
            predictedEndTranslation: -80,
            collapseDistance: collapseDistance
        ) == .peek)
    }

    // MARK: - `E28-03`: the flick path

    @Test func aFastFlickCommitsEvenWhenTheProjectedDistanceDoesNot() {
        // Short, fast, well inside the distance threshold (80) — the flick this exists for.
        #expect(CallSheetDetent.resolved(
            from: .open,
            predictedEndTranslation: 20,
            collapseDistance: collapseDistance,
            velocity: 400
        ) == .peek)
        #expect(CallSheetDetent.resolved(
            from: .peek,
            predictedEndTranslation: -20,
            collapseDistance: collapseDistance,
            velocity: -400
        ) == .open)
    }

    @Test func aSlowDragBelowTheFlickThresholdStillNeedsDistance() {
        #expect(CallSheetDetent.resolved(
            from: .open,
            predictedEndTranslation: 20,
            collapseDistance: collapseDistance,
            velocity: 100
        ) == .open)
    }

    @Test func flickVelocityInTheWrongDirectionNeverCommits() {
        #expect(CallSheetDetent.resolved(
            from: .open,
            predictedEndTranslation: 20,
            collapseDistance: collapseDistance,
            velocity: -400
        ) == .open)
        #expect(CallSheetDetent.resolved(
            from: .peek,
            predictedEndTranslation: -20,
            collapseDistance: collapseDistance,
            velocity: 400
        ) == .peek)
    }

    @Test func aSmallSheetStillNeedsTheFullSpaceXXLFloorToCommit() {
        // `collapseDistance * 0.25` here is 10pt — far under `Space.xxl` (24pt) — so the floor,
        // not the scaled fraction, sets the threshold. A projection past the fraction but short
        // of the floor must still spring back.
        let smallCollapseDistance: CGFloat = 40
        #expect(CallSheetDetent.resolved(
            from: .open,
            predictedEndTranslation: 15,
            collapseDistance: smallCollapseDistance
        ) == .open)
        #expect(CallSheetDetent.resolved(
            from: .open,
            predictedEndTranslation: 30,
            collapseDistance: smallCollapseDistance
        ) == .peek)
    }

    @Test func wrongDirectionProjectionNeverCommitsRegardlessOfMagnitude() {
        // A huge projection in the direction that would already collapse the current detent
        // further does nothing — `.open` only commits on a positive (downward) projection, and
        // `.peek` only on a negative (upward) one.
        #expect(CallSheetDetent.resolved(
            from: .open,
            predictedEndTranslation: -500,
            collapseDistance: collapseDistance
        ) == .open)
        #expect(CallSheetDetent.resolved(
            from: .peek,
            predictedEndTranslation: 500,
            collapseDistance: collapseDistance
        ) == .peek)
    }
}
