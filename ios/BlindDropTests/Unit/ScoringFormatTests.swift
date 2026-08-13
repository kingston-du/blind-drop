import Foundation
import Testing
@testable import BlindDrop

/// `E12-02`. *"The one place a formatting bug becomes a product bug."*
///
/// Two rules, and only one of them is arithmetic. The rounding has to be stable so a label and
/// the `%lld` VoiceOver announces never disagree; the `nil` has to stay a dash, because a `0%`
/// under **Ear** is the app telling somebody who spent the evening elsewhere that they scored
/// nothing (`docs/04` §4).
@Suite struct ScoringFormatTests {

    // MARK: - null is not zero

    /// **The rule this file exists for.**
    @Test func anAbsentRateIsADashAndNeverAZero() {
        #expect(ScoringFormat.percent(nil) == "—")
        #expect(ScoringFormat.percent(nil) != "0%")
    }

    /// And a real zero is still a zero. Somebody who guessed and got none of them right has a
    /// score; refusing to print it would be a different lie from the one above.
    @Test func aGenuineZeroStillPrintsAsZero() {
        #expect(ScoringFormat.percent(0) == "0%")
    }

    // MARK: - Rounding

    /// The §4.4 numbers, which is what the results screen actually renders.
    @Test(arguments: [
        (0.857, "86%"),
        (0.714, "71%"),
        (0.571, "57%"),
        (0.429, "43%"),
        (0.286, "29%"),
        (0.143, "14%"),
        (1.0, "100%"),
    ])
    func aRateRendersAsAWholePercentage(_ rate: Double, _ expected: String) {
        #expect(ScoringFormat.percent(rate) == expected)
    }

    /// The label and the announcement are the same number. They are produced by two calls, and
    /// a rounding difference between them would show *86%* and say *"85 percent"*.
    @Test(arguments: [0.0, 0.005, 0.115, 0.5, 0.855, 0.857, 0.995, 1.0])
    func theSpokenNumberMatchesThePrintedOne(_ rate: Double) {
        #expect(ScoringFormat.percent(rate).hasPrefix("\(ScoringFormat.percentValue(rate))"))
    }

    /// A rate outside `0…1` is a bug upstream. It must not become a label reading `140%` or a
    /// meter marker drawn off the end of its track.
    @Test func anOutOfRangeRateIsClamped() {
        #expect(ScoringFormat.percentValue(1.4) == 100)
        #expect(ScoringFormat.percentValue(-0.2) == 0)
    }

    // MARK: - Bands (docs/02 §4.5)

    /// The boundaries, exactly. A `>` written for a `>=` moves somebody a band down and nothing
    /// else about the screen looks wrong.
    @Test(arguments: [
        (1.0, ReadabilityBand.openBook),
        (0.80, .openBook),
        (0.799, .legible),
        (0.60, .legible),
        (0.599, .mixedSignals),
        (0.40, .mixedSignals),
        (0.399, .hardToPlace),
        (0.20, .hardToPlace),
        (0.199, .unreadable),
        (0.0, .unreadable),
    ])
    func aRateFallsInTheBandDocsTwoNames(_ rate: Double, _ band: ReadabilityBand) {
        #expect(ReadabilityBand(readability: rate) == band)
    }

    /// **No band is framed as good or bad** (`docs/11`). Nothing in the five words congratulates
    /// or commiserates, and none of them is empty — a missing row would render as the key.
    @Test func everyBandHasAWordAndNoneOfThemJudges() {
        let words = ReadabilityBand.allCases.map(Copy.band)
        #expect(words == ["Clear", "Legible", "Mixed", "Elusive", "Unreadable"])
    }
}
