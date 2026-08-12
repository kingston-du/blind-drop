import Foundation
import Testing
@testable import BlindDrop

/// Every string `SubmitScreen` can render, in both of its states.
///
/// File scope because `@Test(arguments:)` evaluates its arguments outside the actor the suite is
/// isolated to. A list rather than something derived, because the point is that somebody adding a
/// string to this screen has to add it here too — and if they add one with a count in it, the test
/// below fails.
private let submitScreenCopy = [
    "submit.headline",
    "submit.subhead",
    "submit.countdown.label",
    "submit.action",
    "submit.nudge",
    "submit.closed.headline",
    "submit.closed.subhead",
    "submit.closed.countdown.label",
    // The header, which is on this screen too.
    "menu.title",
    // And the VoiceOver format the countdown announces itself with.
    "a11y.countdown",
]

/// `E10-01`'s last checklist line, and AC-1's client half:
///
/// > *"Test: no accessibility label on this screen contains a digit other than the countdown."*
///
/// The reason it is a **digit** test rather than a "does it say how many people dropped" test is
/// `docs/12` §2: *"Do not add accessibility labels that expose anything the visual UI does not —
/// no '4 of 8 submitted' in a hidden label."* Any count that leaked onto this screen, visibly or
/// as a label, would arrive as a numeral. So the assertion is that the only numerals on the submit
/// screen are a **time of day** and the countdown itself — both facts about the clock, which is the
/// one thing the blind window is not hiding.
///
/// It reads the strings the screen renders rather than walking a rendered hierarchy, and that is
/// deliberate: an `XCUITest` sweep would assert what one build happened to draw, while this asserts
/// the *copy* — which is where a count would have to be written down before it could ever reach a
/// label.
@MainActor
@Suite struct SubmitLeakTests {

    /// **The assertion.** Times of day are struck out first — *"Nobody sees it until 8:00 PM."* is
    /// the tutorial, and *"The next one opens at %@."* takes one — and then nothing numeric may be
    /// left anywhere.
    @Test(arguments: submitScreenCopy)
    func noSubmitScreenStringCarriesACount(_ key: String) {
        let resolved = Copy.string(key)
        #expect(resolved != key, "\(key) is missing from Localizable.strings")

        let withoutClockTimes = resolved.replacing(/\d{1,2}:\d{2}/, with: "")
        let digits = withoutClockTimes.filter(\.isNumber)
        #expect(
            digits.isEmpty,
            """
            \(key) — "\(resolved)" — carries a numeral that is not a time of day. \
            On the submit screen a number can only be a count, and a count is the leak \
            (docs/08 §2, docs/12 §2).
            """
        )
    }

    /// The screen's rendered form of the dark-hours line, with a real hour substituted, still has
    /// no count in it. The format is checked above; this checks the *result*, because `%@` is where
    /// a value arrives and a value is what could carry one.
    @Test func theDarkHoursLineCarriesOnlyAnHour() throws {
        let context = try RoundFixture.context()
        let line = Copy.format("submit.closed.subhead", context.opensTime)

        let withoutClockTimes = line.replacing(/\d{1,2}:\d{2}/, with: "")
        #expect(withoutClockTimes.filter(\.isNumber).isEmpty)
    }

    /// And the payload behind the screen cannot express one either — which is the half of AC-1 the
    /// UI could not fix if it were wrong.
    ///
    /// `docs/04` §4: *"The golden test asserts the key set is exactly `{round_id, local_date,
    /// state, opens_at, reveals_at, scores_at, my_submission}`."* The server's own golden asserts
    /// that; this asserts the **client** has nowhere to put anything else, by decoding the fixture
    /// and finding only the caller's own song on it.
    @Test func anOpenRoundHoldsNothingAboutAnybodyElse() throws {
        let context = try RoundFixture.context()
        guard case let .open(mySubmission) = context.round.phase else {
            Issue.record("the fixture is not an open round")
            return
        }
        // The caller's own song, and there is no other property on this phase to read: `cards`,
        // `name_pool` and `my_guesses` live on `revealed` and are unreachable from here — the
        // compiler enforces the blind window (`docs/13` §3).
        #expect(mySubmission?.track.title == "Kill Bill")
    }
}
