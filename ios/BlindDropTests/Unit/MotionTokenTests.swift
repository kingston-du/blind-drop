import Foundation
import Testing
@testable import BlindDrop

/// `docs/09` §6's arithmetic rows, and `docs/09` §2's timeline read back as numbers.
///
/// The point of asserting a *token* rather than a rendered frame is that the spec is a table: if
/// somebody nudges the cover's curve or moves the stamp's landing by 20ms, the failure names the
/// phase and the number rather than showing a picture that is 0.3% different.
@Suite struct MotionTokenTests {

    // MARK: - The seal's timeline (`docs/09` §2)

    /// Every phase begins and ends where the diagram draws it.
    ///
    /// ```
    ///  A ██████                                      0–120
    ///  B    ████████████████████                     80–340
    ///  C                    ███                      320–400
    ///  D                       ████████████          360–540
    ///  E                              ███████████    480–640
    ///  F                                    ██████   560–680
    /// ```
    @Test func theSixPhasesRunAtTheTimesTheSpecDraws() {
        let expected: [(String, Double, Double)] = [
            ("A", 0, 120),
            ("B", 80, 340),
            ("C", 320, 400),
            ("D", 360, 540),
            ("E", 480, 680),
            ("F", 560, 680),
        ]
        for (stage, expectation) in zip(Motion.Seal.stages, expected) {
            #expect(stage.phase == expectation.0)
            #expect(stage.start == expectation.1, "phase \(stage.phase) starts late or early")
            #expect(stage.end == expectation.2, "phase \(stage.phase) ends late or early")
        }
    }

    /// The whole thing is ~600ms of motion with a 680ms tail, exactly as the diagram's right edge
    /// says. A seal that crept past 700ms would be a different moment.
    @Test func theSealEndsAt680Milliseconds() {
        #expect(Motion.Seal.end == 680)
    }

    /// **At contact, not at phase start** (`docs/09` §2). The stamp's phase begins at 360; the
    /// note fires at 380, when it touches down.
    @Test func theHapticsFireAtContact() {
        #expect(Motion.Seal.coverMovesAt == 100)
        #expect(Motion.Seal.stampLandsAt == 380)
        #expect(Motion.Seal.stampLandsAt > Motion.Seal.stamp.start,
                "the rigid note is contact, not the start of the phase that draws the stamp")
    }

    /// Reduced motion is a 240ms crossfade with its one note at the midpoint (`docs/09` §5).
    @Test func reducedMotionIsA240MillisecondCrossfade() {
        #expect(Motion.Seal.reduced.duration == 240)
        #expect(Motion.Seal.reducedHapticAt == 120)
    }

    // MARK: - The unseal (`docs/09` §3, §6)

    @Test func theFiveUnsealPhasesRunAtTheSpecifiedTimes() {
        let expected: [(String, Double, Double)] = [
            ("A", 0, 220),
            ("B", 60, 200),
            ("C", 140, 400),
            ("D", 200, 340),
            ("E", 260, 400),
        ]
        for (stage, expectation) in zip(Motion.Unseal.stages, expected) {
            #expect(stage.phase == expectation.0)
            #expect(stage.start == expectation.1)
            #expect(stage.end == expectation.2)
        }
        #expect(Motion.Unseal.end == 400)
    }

    /// `stagger(for: 6) == 80`, `stagger(for: 12) == 80`, `stagger(for: 30) == 31` — the three
    /// rows `docs/09` §6 asks for by name.
    @Test(arguments: [(6, 80), (12, 80), (30, 31)])
    func theStaggerClampsWhereTheSpecSaysItDoes(_ cards: Int, _ milliseconds: Int) {
        #expect(Motion.Unseal.stagger(cardCount: cards) == milliseconds)
    }

    /// One card is a sequence of one, and dividing by `cardCount - 1` would divide by zero. The
    /// `max(1,…)` in the formula is the reason this returns a number at all.
    @Test func aSingleCardStaggersByTheNominalAmount() {
        #expect(Motion.Unseal.stagger(cardCount: 1) == 80)
    }

    /// The whole sequence stays inside `docs/09` §3's budget: ~900ms of stagger plus a 380ms tail,
    /// at every group size the product allows (`docs/02` — up to twelve members).
    @Test func theFullSequenceNeverExceedsItsBudget() {
        for cards in 2...12 {
            let total = Motion.Unseal.stagger(cardCount: cards) * (cards - 1)
            #expect(total <= 900, "\(cards) cards would stagger for \(total)ms")
        }
    }

    @Test func reducedMotionEndsTheWholeSequenceWithinFourHundredMilliseconds() {
        for cards in 1...12 {
            let total = Motion.Unseal.reducedStagger(cardCount: cards) * (cards - 1)
                + Motion.Unseal.reducedDuration
            #expect(total <= Motion.Unseal.reducedSequenceLimit)
        }
        #expect(Motion.Unseal.reducedStagger(cardCount: 2) == 40)
        #expect(Motion.Unseal.reducedStagger(cardCount: 12) == 14)
    }
}
