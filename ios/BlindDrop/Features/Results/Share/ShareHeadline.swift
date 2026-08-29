import Foundation

/// The one line on the share card that is about the night rather than about the songs
/// (`docs/10` §2).
///
/// > One line chosen by this precedence, **first match wins**:
/// >
/// > 1. The caller's **own** card, and nobody got it → *"Nobody got you"*
/// > 2. The caller's own card, and **everybody** got it → *"Everybody got you"*
/// > 3. The caller scored **100% ear** → *"You read the whole room"*
/// > 4. The caller was in the `unreadable` band → *"You were unreadable"*
/// > 5. A card **nobody** got → *"Nobody got No. 7"*
/// > 6. A card **everybody** got → *"Everybody got No. 3"*
/// > 7. Someone scored **100% ear** → *"Cal read the whole room"*
/// > 8. Lowest readability of the night → *"Gus was unreadable"*
/// > 9. Fallback → *"8 songs, 56 guesses"*
/// >
/// > Never more than one headline. Never a superlative that requires a comparison the viewer
/// > can't see on the card.
///
/// `E36-01` put four personal rules **in front of** the original five (`docs/17` §4's rules,
/// unchanged below as 5–9): the card is now the sharer's account of the night first, and only
/// falls back to a fact about the group when nothing personal is true to say. Rules 1–4 fire
/// only when the caller actually has a night to report — see `ownCard(in:)`.
///
/// A pure function of the results, and deliberately not a view: the precedence is the thing that
/// has to be right, and a rule buried in a `ViewBuilder` is a rule tested by a golden PNG. Each
/// rule has its own fixture in `ShareHeadlineTests`.
enum ShareHeadline {

    /// The headline for a night, already in words.
    static func line(for results: ResultsDTO) -> String {
        if let card = ownCard(in: results) {
            if card.correctGuessCount == 0, card.eligibleGuesserCount > 0 {
                return Copy.string("share.headline.you.nobody")
            }
            if card.correctGuessCount > 0, card.correctGuessCount >= card.eligibleGuesserCount {
                return Copy.string("share.headline.you.everybody")
            }
        }
        if results.me.ear == 1, (results.me.earPossible ?? 0) > 0 {
            return Copy.string("share.headline.you.perfect")
        }
        if let readability = results.me.readability,
           ReadabilityBand(readability: readability) == .unreadable {
            return Copy.string("share.headline.you.unreadable")
        }
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

    /// The caller's own card — the one card `guesses` arrives non-`nil` on (`docs/04` §4,
    /// `ResultCardDTO`'s own doc comment). `nil` for anybody who did not submit, which is also
    /// exactly when `docs/02` §4.1 keeps `me.readability` and `me.ear` `nil` — a non-submitter
    /// reaches no personal rule at all, by construction, not by a second check here.
    static func ownCard(in results: ResultsDTO) -> ResultCardDTO? {
        results.cards.first { $0.guesses != nil }
    }

    /// Rule 8 (was rule 4): **the lowest readability of the night**, whatever it is.
    ///
    /// Read literally, and that is the owner's call rather than an inference — an earlier pass
    /// narrowed it to people actually in the `unreadable` band, on the grounds that *"%@ was
    /// unreadable"* is false of somebody on 71%. The decision came back the other way, and it is
    /// recorded in `tasks/E12-results-and-share.md`. **Rule 4's personal counterpart is stricter
    /// on purpose** — see its own comment above — but that owner decision governs this group rule
    /// unchanged.
    ///
    /// So the rule stands as `docs/10` §2 writes it. Two things about it are worth knowing when
    /// reading the card: on a night where everybody is legible the headline still names the
    /// least legible person, and it only ever gets that far — rules 1 through 7 take almost
    /// every interesting night before it.
    ///
    /// `nil` only when nobody has a readability at all, which is a round of people who all
    /// joined after the reveal.
    ///
    /// Ties go to the server's order, which is the order `people` arrived in — arbitrary, but
    /// the *same* arbitrary on every render, so two people on 0.14 do not swap places between
    /// the thumbnail and the file.
    private static func leastReadable(_ people: [PersonScoreDTO]) -> PersonScoreDTO? {
        let readable = people.compactMap { person in person.readability.map { (person, $0) } }
        guard let lowest = readable.map(\.1).min() else { return nil }
        return readable.first(where: { $0.1 == lowest })?.0
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
