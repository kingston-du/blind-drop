import Foundation
import Testing
@testable import BlindDrop

/// No string states a clock time the circle did not choose.
///
/// `reveal_hour` is the one scheduling setting a circle owns (`docs/02` §1), and it is set to
/// something other than the 20:00 default often enough that a sentence with *"8:00 PM"* typed
/// into it is not a cosmetic slip — it tells a member of a 6:00 PM circle the wrong hour, in the
/// one place on the submit screen whose whole job is to teach them when the blind window closes.
/// It shipped that way: `submit.subhead` and `onboarding.subtitle` both carried the default hour
/// as a literal, and neither moved when the owner of *Kingston's friends* moved the circle to
/// 18:00.
///
/// The deck is scanned rather than a list of known-parameterised keys being asserted, because the
/// failure mode is somebody **adding** a string, not somebody editing one of these two. A key with
/// an hour in it has to be caught the day it is written; by the time it is on a list, it is
/// already correct.
@Suite struct RevealHourCopyTests {

    /// Every value in `Localizable.strings`, keyed. Parsed rather than enumerated because the
    /// point of the test below is to see keys nobody has thought about.
    private static let deck: [String: String] = {
        guard let url = Copy.bundle.url(forResource: "Localizable", withExtension: "strings"),
              let raw = try? Data(contentsOf: url),
              let parsed = try? PropertyListSerialization.propertyList(
                  from: raw, format: nil
              ) as? [String: String]
        else { return [:] }
        return parsed
    }()

    @Test func theDeckIsReadable() {
        #expect(!Self.deck.isEmpty, "Localizable.strings did not parse — the scan below is vacuous")
    }

    /// A clock time is `8:00`, `18:00`, `8 PM`. The countdown's own formats are not in the deck
    /// (`Copy.countdown` assembles `HH:MM:SS` in code, deliberately — see `Copy`), so anything
    /// matching here is a wall-clock hour written down as a fact, which only the server knows.
    @Test func noStringStatesAnHourTheCircleDidNotChoose() {
        let clock = /\d{1,2}:\d{2}|\b\d{1,2}\s?(AM|PM|am|pm)\b/
        let offenders = Self.deck
            .filter { $0.value.contains(clock) }
            .keys
            .sorted()
        #expect(
            offenders.isEmpty,
            """
            \(offenders.joined(separator: ", ")) — a circle's reveal hour is 18…21 and set by \
            its admin (docs/02 §1). Take the hour as a `%@` and pass `RoundContext.revealTime`, \
            or drop it from the sentence.
            """
        )
    }

    /// And the one that was wrong, from the other side: a 6:00 PM circle reads 6:00 PM.
    @Test func theSubmitSubheadTakesTheCirclesOwnHour() {
        let english = Locale(identifier: "en_US")
        let sixPM = RevealHour.formatted(18, locale: english)
        let filled = Copy.format("submit.subhead", sixPM)

        #expect(filled.contains(sixPM))
        #expect(!filled.contains("8:00"))
        #expect(!filled.contains("%@"), "submit.subhead lost its placeholder")
    }
}
