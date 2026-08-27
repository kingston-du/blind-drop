import Foundation
import Testing
@testable import BlindDrop

/// `CallSheetDetent.resolved` is the committing-drag decision `GuessSheet`'s `dragGesture` hands
/// off to on release (`E26-02`): whether the finger's actual distance — or its flick velocity —
/// crossed the open/peek threshold. `E17-10` could only exercise the non-committing (springback)
/// case informally, on device; this pins the committing directions, the springback, the flick
/// path, and the `Space.xxl` floor that keeps a small sheet from committing on a hair-trigger
/// threshold — plus the deliberate-drag case `E32-01` re-keyed the decision onto.
@Suite struct CallSheetDetentTests {

    /// A generous `collapseDistance` so `threshold` (`collapseDistance * 0.2`) sits well above
    /// the `Space.xxl` floor and the test is exercising the scaled threshold, not the floor.
    private let collapseDistance: CGFloat = 400 // threshold == 80

    @Test func openCommitsToPeekWhenTranslationCrossesTheThresholdDownward() {
        let resolved = CallSheetDetent.resolved(
            from: .open,
            translation: 150,
            collapseDistance: collapseDistance
        )
        #expect(resolved == .peek)
    }

    @Test func peekCommitsToOpenWhenTranslationCrossesTheThresholdUpward() {
        let resolved = CallSheetDetent.resolved(
            from: .peek,
            translation: -150,
            collapseDistance: collapseDistance
        )
        #expect(resolved == .open)
    }

    @Test func releaseThatDoesNotCrossTheThresholdSpringsBackUnchanged() {
        // Well inside the threshold in both directions and both starting detents — a short,
        // slow release that should never flip the sheet.
        #expect(CallSheetDetent.resolved(
            from: .open,
            translation: 40,
            collapseDistance: collapseDistance
        ) == .open)
        #expect(CallSheetDetent.resolved(
            from: .peek,
            translation: -40,
            collapseDistance: collapseDistance
        ) == .peek)
    }

    @Test func exactlyAtTheThresholdDoesNotCommit() {
        // The comparison is strict (`>` / `<`), not `>=` / `<=` — landing precisely on the
        // threshold is a springback, not a commit.
        #expect(CallSheetDetent.resolved(
            from: .open,
            translation: 80,
            collapseDistance: collapseDistance
        ) == .open)
        #expect(CallSheetDetent.resolved(
            from: .peek,
            translation: -80,
            collapseDistance: collapseDistance
        ) == .peek)
    }

    // MARK: - `E28-03`: the flick path

    @Test func aFastFlickCommitsEvenWhenTheDistanceDoesNot() {
        // Short, fast, well inside the distance threshold (80) — the flick this exists for.
        #expect(CallSheetDetent.resolved(
            from: .open,
            translation: 20,
            collapseDistance: collapseDistance,
            velocity: 400
        ) == .peek)
        #expect(CallSheetDetent.resolved(
            from: .peek,
            translation: -20,
            collapseDistance: collapseDistance,
            velocity: -400
        ) == .open)
    }

    @Test func aSlowDragBelowTheFlickThresholdStillNeedsDistance() {
        #expect(CallSheetDetent.resolved(
            from: .open,
            translation: 20,
            collapseDistance: collapseDistance,
            velocity: 100
        ) == .open)
    }

    @Test func flickVelocityInTheWrongDirectionNeverCommits() {
        #expect(CallSheetDetent.resolved(
            from: .open,
            translation: 20,
            collapseDistance: collapseDistance,
            velocity: -400
        ) == .open)
        #expect(CallSheetDetent.resolved(
            from: .peek,
            translation: -20,
            collapseDistance: collapseDistance,
            velocity: 400
        ) == .peek)
    }

    @Test func aSmallSheetStillNeedsTheFullSpaceXXLFloorToCommit() {
        // `collapseDistance * 0.2` here is 8pt — far under `Space.xxl` (24pt) — so the floor,
        // not the scaled fraction, sets the threshold. A translation past the fraction but short
        // of the floor must still spring back.
        let smallCollapseDistance: CGFloat = 40
        #expect(CallSheetDetent.resolved(
            from: .open,
            translation: 15,
            collapseDistance: smallCollapseDistance
        ) == .open)
        #expect(CallSheetDetent.resolved(
            from: .open,
            translation: 30,
            collapseDistance: smallCollapseDistance
        ) == .peek)
    }

    @Test func wrongDirectionTranslationNeverCommitsRegardlessOfMagnitude() {
        // A huge translation in the direction that would already collapse the current detent
        // further does nothing — `.open` only commits on a positive (downward) translation, and
        // `.peek` only on a negative (upward) one.
        #expect(CallSheetDetent.resolved(
            from: .open,
            translation: -500,
            collapseDistance: collapseDistance
        ) == .open)
        #expect(CallSheetDetent.resolved(
            from: .peek,
            translation: 500,
            collapseDistance: collapseDistance
        ) == .peek)
    }

    // MARK: - `E32-01`: a deliberate drag commits on distance

    @Test func aDeliberatePartialDragCommitsOnDistanceAlone() {
        // A purposeful, moderate drag — past the threshold, released with no flick. The old
        // projected-distance decision could read a decelerating release as short of where the
        // finger actually went; the actual translation is what a deliberate drag is.
        #expect(CallSheetDetent.resolved(
            from: .open,
            translation: 100,
            collapseDistance: collapseDistance,
            velocity: 60
        ) == .peek)
        #expect(CallSheetDetent.resolved(
            from: .peek,
            translation: -100,
            collapseDistance: collapseDistance,
            velocity: -60
        ) == .open)
    }

    @Test func aDragReleasedAgainstItsOwnDirectionStillCommitsOnDistance() {
        // The finger travelled down past the threshold and then settled back a touch on release
        // (velocity slightly negative). A projection reads that release as a shorter distance and
        // springs back; the actual translation is what `E32-01` re-keyed the decision onto.
        #expect(CallSheetDetent.resolved(
            from: .open,
            translation: 100,
            collapseDistance: collapseDistance,
            velocity: -40
        ) == .peek)
        #expect(CallSheetDetent.resolved(
            from: .peek,
            translation: -100,
            collapseDistance: collapseDistance,
            velocity: 40
        ) == .open)
    }
}
