import Foundation
import Testing
@testable import BlindDrop

/// `docs/10` §6: *"Headline precedence — unit test over five fixtures, one per rule in §2."*
///
/// One test per rule, plus the two things the precedence is really about: that a night matching
/// several rules produces **only the first**, and that the sentence on the card is never a claim
/// the card cannot support.
@MainActor
@Suite struct ShareHeadlineTests {

    // MARK: - The five rules

    /// **1 — a card nobody got.** Beats everything, including a perfect ear in the same round.
    @Test func nobodyGotACardWins() {
        let night = ShareHeadlineFixture.night(
            cards: [(1, 4), (2, 5), (7, 0)],
            people: [("Cal", readability: 0.4, ear: 1.0), ("Gus", readability: 0.05, ear: 0.2)]
        )
        #expect(ShareHeadline.line(for: night) == "Nobody got No. 7")
    }

    /// **2 — a card everybody got.**
    @Test func everybodyGotACardIsSecond() {
        let night = ShareHeadlineFixture.night(
            cards: [(1, 4), (3, 7), (5, 2)],
            people: [("Cal", readability: 0.4, ear: 1.0)]
        )
        #expect(ShareHeadline.line(for: night) == "Everybody got No. 3")
    }

    /// **3 — a perfect ear.**
    @Test func aPerfectEarIsThird() {
        let night = ShareHeadlineFixture.night(
            cards: [(1, 4), (2, 3)],
            people: [("Ana", readability: 0.9, ear: 0.5), ("Cal", readability: 0.4, ear: 1.0)]
        )
        #expect(ShareHeadline.line(for: night) == "Cal read the whole room")
    }

    /// **4 — the least readable person of the night**, when the word is actually true of them.
    @Test func theLeastReadableIsFourth() {
        let night = ShareHeadlineFixture.night(
            cards: [(1, 4), (2, 3)],
            people: [("Ana", readability: 0.9, ear: 0.5), ("Gus", readability: 0.1, ear: 0.2)]
        )
        #expect(ShareHeadline.line(for: night) == "Gus was unreadable")
    }

    /// **5 — the fallback.** Two numbers and a judgement of nobody.
    ///
    /// *"56 guesses"* is the `docs/02` §4.4 round's own arithmetic: eight cards, each with seven
    /// eligible guessers.
    @Test func theFallbackCountsSongsAndGuesses() throws {
        let night = try ShareHeadlineFixture.fortyFour()
        // The §4.4 night matches rule 3 — Cal's ear is 1.0 — so the fallback is checked on a
        // night stripped of every earlier match.
        // Rule 4 fires on any readability at all, so the fallback is only reachable on a night
        // where nobody has one — a round of people who all joined after the reveal.
        let ordinary = ShareHeadlineFixture.night(
            cards: (1...8).map { ($0, 3) },
            people: [("Ana", readability: nil, ear: 0.5), ("Ben", readability: nil, ear: 0.4)]
        )

        #expect(ShareHeadline.line(for: ordinary) == "8 songs, 56 guesses")
        #expect(ShareHeadline.line(for: night) == "Cal read the whole room")
    }

    // MARK: - Never more than one

    /// A night can match four rules at once. Exactly one sentence comes out, and it is the
    /// first — *"never more than one headline"* (`docs/10` §2).
    @Test func onlyTheFirstMatchIsUsed() {
        let night = ShareHeadlineFixture.night(
            cards: [(1, 0), (2, 7)],
            people: [("Cal", readability: 0.4, ear: 1.0), ("Gus", readability: 0.05, ear: 0.1)]
        )
        let line = ShareHeadline.line(for: night)

        #expect(line == "Nobody got No. 1")
        #expect(!line.contains("Everybody"))
        #expect(!line.contains("whole room"))
        #expect(!line.contains("unreadable"))
    }

    /// **The first by `card_no`**, when two cards match the same rule. The rows on the card are
    /// picked along the same spine, so the headline can never name a night the rows contradict.
    @Test func theFirstCardByNumberWins() {
        let night = ShareHeadlineFixture.night(
            cards: [(2, 0), (5, 0)],
            people: [("Ana", readability: 0.9, ear: 0.5)]
        )
        #expect(ShareHeadline.line(for: night) == "Nobody got No. 2")
    }

    // MARK: - The sentence has to be true

    /// **Rule 4 fires on the lowest readability, whatever it is** — the owner's decision on the
    /// question `tasks/E12-results-and-share.md` records.
    ///
    /// The alternative reading narrowed it to people actually in the `unreadable` band, so this
    /// is the test that names the choice: a night whose least readable person is on 71% still
    /// gets rule 4, and does **not** fall through to the fallback.
    @Test func theLowestReadabilityWinsEvenWhenItIsNotLow() {
        let night = ShareHeadlineFixture.night(
            cards: [(1, 4), (2, 3)],
            people: [("Ana", readability: 0.9, ear: 0.5), ("Ben", readability: 0.71, ear: 0.4)]
        )
        #expect(ShareHeadline.line(for: night) == "Ben was unreadable")
    }

    /// The band boundary is not a boundary for this rule. 0.199 and 0.20 sit either side of
    /// `unreadable` (`docs/02` §4.5) and both produce the same headline.
    @Test func theBandBoundaryDoesNotDecideRuleFour() {
        let just = ShareHeadlineFixture.night(
            cards: [(1, 4)], people: [("Gus", readability: 0.199, ear: 0.4)]
        )
        let notQuite = ShareHeadlineFixture.night(
            cards: [(1, 4)], people: [("Gus", readability: 0.20, ear: 0.4)]
        )

        #expect(ShareHeadline.line(for: just) == "Gus was unreadable")
        #expect(ShareHeadline.line(for: notQuite) == "Gus was unreadable")
    }

    /// Ties go to the server's order, so the thumbnail and the file name the same person.
    @Test func aTieOnTheLowestReadabilityTakesTheFirstOneSent() {
        let night = ShareHeadlineFixture.night(
            cards: [(1, 4)],
            people: [("Gus", readability: 0.14, ear: 0.4), ("Eli", readability: 0.14, ear: 0.3)]
        )
        #expect(ShareHeadline.line(for: night) == "Gus was unreadable")
    }

    /// A night nobody has a readability for — everybody joined late — reaches the fallback
    /// rather than crashing or naming somebody.
    @Test func aNightWithNoReadabilitiesFallsBack() {
        let night = ShareHeadlineFixture.night(
            cards: [(1, 4), (2, 3)], people: [("Ana", readability: nil, ear: 0.5)]
        )
        #expect(ShareHeadline.line(for: night) == "2 songs, 14 guesses")
    }

    /// And the fallback is genuinely last: a night with one readability, however ordinary,
    /// reaches rule 4 rather than the numbers.
    @Test func theFallbackIsOnlyReachedWhenEveryEarlierRuleIsSilent() {
        let night = ShareHeadlineFixture.night(
            cards: [(1, 4), (2, 3)],
            people: [("Ana", readability: 0.86, ear: 0.5)]
        )
        #expect(ShareHeadline.line(for: night) == "Ana was unreadable")
    }
}

/// Nights, built through the decoder.
///
/// The DTOs' initialiser is the decoder on purpose (`docs/13` §2), so a fixture is JSON. Which
/// is also the honest thing here: every one of these is a claim about what the **server** sends.
@MainActor
enum ShareHeadlineFixture {

    /// - Parameters:
    ///   - cards: `(card_no, correct_guess_count)`. Every card has seven eligible guessers, the
    ///     `docs/02` §4.4 round's own denominator.
    ///   - people: `(name, readability, ear)`.
    static func night(
        cards: [(Int, Int)],
        people: [(String, readability: Double?, ear: Double?)]
    ) -> ResultsDTO {
        let cardJSON = cards.map { number, correct -> [String: Any] in
            [
                "card_no": number,
                "track": track,
                "owner": ["user_id": "u\(number)", "display_name": "Owner \(number)"],
                "correct_guess_count": correct,
                "eligible_guesser_count": 7,
                "my_guess": NSNull(),
                "guesses": NSNull(),
            ]
        }
        let peopleJSON = people.map { name, readability, ear -> [String: Any] in
            [
                "user_id": "u_\(name)",
                "display_name": name,
                "readability": readability.map { $0 as Any } ?? NSNull(),
                "ear": ear.map { $0 as Any } ?? NSNull(),
            ]
        }
        let json: [String: Any] = [
            "round_id": "r",
            "local_date": "2026-08-10",
            "submitter_count": cards.count,
            "cards": cardJSON,
            "me": [
                "readability": NSNull(), "readability_correct": NSNull(),
                "readability_possible": NSNull(), "ear": NSNull(),
                "ear_correct": NSNull(), "ear_possible": NSNull(),
            ],
            "people": peopleJSON,
            "tonight_top_ear": [],
        ]
        // A fixture that will not decode is a broken test, and failing loudly here is more
        // useful than nine assertions failing for a reason none of them names.
        // swift-format-ignore
        return try! JSONDecoder.api.decode(
            ResultsDTO.self, from: try! JSONSerialization.data(withJSONObject: json)
        )
    }

    /// The real `docs/02` §4.4 night, from the payload the fixture server serves.
    static func fortyFour() throws -> ResultsDTO {
        try JSONDecoder.api.decode(ResultsDTO.self, from: RoundFixture.payload("results"))
    }

    /// The shape `docs/04` §6 sends. `apple_music_id` and `apple_music_url` are **not** nullable
    /// — a track the app can show is a track it resolved in the Apple catalog (`docs/06` §1) —
    /// so a fixture that nulled them would be a payload the decoder is right to reject.
    private static let track: [String: Any] = [
        "track_key": "isrc:USUM71311296",
        "isrc": "USUM71311296",
        "title": "Ribs",
        "artist": "Lorde",
        "album": "Pure Heroine",
        "artwork_url": NSNull(),
        "artwork_bg_color": NSNull(),
        "duration_ms": 249_000,
        "preview_url": NSNull(),
        "apple_music_id": "1440818664",
        "apple_music_url": "https://music.apple.com/us/song/1440818664",
        "spotify_id": NSNull(),
        "spotify_url": NSNull(),
    ]
}
