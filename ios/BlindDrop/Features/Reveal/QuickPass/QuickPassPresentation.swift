import Foundation

/// Whether the quick pass should open itself (`E41-02`).
///
/// A pure function over five facts, rather than a condition spelled out inside `RevealHost`'s
/// body, because it is the rule most likely to be wrong in a way nobody notices: a modal that
/// presents itself once too often is not a shortcut, it is an obstruction, and a modal that
/// presents itself once too rarely quietly undoes the whole feature. Both failures are silent in
/// a screenshot and obvious in a test.
enum QuickPassPresentation {

    /// What the host knows when it is deciding.
    struct Conditions: Equatable, Sendable {
        /// `false` for a non-submitter and for somebody who joined after the reveal. They are
        /// shown the flight with the apparatus disabled but whole (`docs/08` §6) and never this.
        var canGuess: Bool
        /// Whether any card is still without a name. A full sheet has nothing to open onto.
        var hasUnnamedCards: Bool
        /// Whether the round's once-a-night unseal has had its run.
        ///
        /// The reason this is in the rule at all: the unseal is one of the two moments carrying
        /// the app's entire motion budget (`docs/09` §1) and it plays once per round. Covering it
        /// with a modal on a round's first arrival spends the signature moment on nothing, so the
        /// quick pass waits for it and presents when it settles. Every later arrival — the flag
        /// is already set by then — is immediate.
        var unsealHasRun: Bool
        /// Whether a deep link for this circle's round is waiting to be consumed. A push tap, or
        /// a link: an explicit intent, and the one input that overrides having been dismissed.
        var arrivedFromLink: Bool
        /// Whether the cover has already opened itself for this round on this install
        /// (`LocalFlags.beginQuickPass(roundID:)`).
        var alreadyOfferedThisRound: Bool
    }

    /// The three clauses, in priority order.
    static func shouldPresent(_ c: Conditions) -> Bool {
        // 1. Never, on any of these. A blocked caller has nothing to name; a full sheet has
        //    nothing to open onto; and the unseal gets its night.
        guard c.canGuess, c.hasUnnamedCards, c.unsealHasRun else { return false }
        // 2. Always, on an explicit intent. Somebody who tapped a notification asked for this
        //    screen and may ask again as often as they like — dismissing it yesterday, or ten
        //    minutes ago, is not an answer to a question they have just re-asked.
        if c.arrivedFromLink { return true }
        // 3. Once otherwise. Opening the app during the guess window offers it; dismissing it to
        //    browse the flight is a thing the person said, and it is remembered.
        return !c.alreadyOfferedThisRound
    }
}
