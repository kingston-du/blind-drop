import Foundation

/// The one line on the share card that is about the night rather than about the songs
/// (`docs/10` §2).
///
/// > One line chosen by this precedence, **first match wins**:
/// >
/// > 1. A card **nobody** got → *"Nobody got No. 7"*
/// > 2. A card **everybody** got → *"Everybody got No. 3"*
/// > 3. Someone scored **100% ear** → *"Cal read the whole room"*
/// > 4. Lowest readability of the night → *"Gus was unreadable"*
/// > 5. Fallback → *"8 songs, 56 guesses"*
/// >
/// > Never more than one headline. Never a superlative that requires a comparison the viewer
/// > can't see on the card.
///
/// A pure function of the results, and deliberately not a view: the precedence is the thing that
/// has to be right, and a rule buried in a `ViewBuilder` is a rule tested by a golden PNG. Each
/// of the five has its own fixture in `ShareHeadlineTests`.
enum ShareHeadline {

    /// The headline for a night, already in words.
    static func line(for results: ResultsDTO) -> String {
        if let card = firstCard(where: { $0.correctGuessCount == 0 }) {
            return Copy.format("share.headline.nobody", card.cardNumber)
        }
        if let card = firstCard(where: { $0.correctGuessCount >= $0.eligibleGuesserCount }) {
            return Copy.format("share.headline.everybody", card.cardNumber)
        }
        if let person = results.people.first(where: { $0.ear == 1 }) {
            return Copy.format("share.headline.perfect", person.displayName)
        }
        if let person = leastReadable(results.people) {
            return Copy.format("share.headline.unreadable", person.displayName)
        }
        return Copy.format("share.headline.fallback", results.cards.count, guessCount(results))

        func firstCard(where matches: (ResultCardDTO) -> Bool) -> ResultCardDTO? {
            // **By `card_no`**, which is the order the array already carries (`docs/04` §4).
            // Two cards nobody got is a real night, and the one the card names is the first —
            // the same spine the flight rows are picked along, so the headline and the rows
            // cannot disagree about which night this was.
            results.cards.first(where: matches)
        }
    }

    /// Rule 4, with its sentence held to being true.
    ///
    /// `docs/10` §2 names it *"lowest readability of the night"* and gives it the words *"%@ was
    /// unreadable"*. On a night whose lowest readability is 71% those two are not the same
    /// claim, and §2's own guard — *"never a superlative that requires a comparison the viewer
    /// can't see"* — rules out the first reading anyway: nothing on the card shows anybody
    /// else's readability, so "lowest" is unverifiable and "unreadable" is simply wrong.
    ///
    /// So the rule fires only when the least readable person is genuinely in the `unreadable`
    /// band (`docs/02` §4.5). Otherwise the night falls through to the fallback, which states
    /// two numbers and judges nobody. See the open question in `tasks/E12-results-and-share.md`.
    ///
    /// Ties go to the server's order, which is the order `people` arrived in — arbitrary, but
    /// the *same* arbitrary on every render.
    private static func leastReadable(_ people: [PersonScoreDTO]) -> PersonScoreDTO? {
        let readable = people.compactMap { person in person.readability.map { (person, $0) } }
        guard let lowest = readable.map(\.1).min(),
              ReadabilityBand(readability: lowest) == .unreadable,
              let match = readable.first(where: { $0.1 == lowest })
        else { return nil }
        return match.0
    }

    /// *"56 guesses"* — every guess the night scored, which for the `docs/02` §4.4 round is
    /// 8 × 7.
    ///
    /// Summed from the cards' own denominators rather than from `submitter_count`, because
    /// `eligible_guesser_count` **is** the number of guesses in play on a card: `docs/02` §4.1
    /// keeps it at `S − 1` whether or not somebody opened their sheet, so a blank counts and the
    /// total does not shrink to a measure of enthusiasm.
    private static func guessCount(_ results: ResultsDTO) -> Int {
        results.cards.reduce(0) { $0 + $1.eligibleGuesserCount }
    }
}
