import Foundation
import Testing
@testable import BlindDrop

/// The four names a card offers, as the client resolves them.
///
/// The *choosing* is the server's (`_shared/shortlist.ts`, tested there). What lives here is
/// everything the client decides on top of it: which pool order they come back in, and what
/// happens when the list is empty, unknown, or has been outlived by the people in it. Each of
/// those is a case where a wrong answer looks like an ordinary sheet rather than like a bug —
/// four names in a different order on every card is a memory test nobody asked for, and a card
/// that narrows to nothing is a card that cannot be played and does not say so.
@MainActor
@Suite struct ShortlistTests {

    /// Pool order, always — not the order the server shuffled them into.
    @Test func theFourComeBackInPoolOrder() {
        let store = RevealFixture.store(
            cardCount: 3,
            shortlists: [1: ["u4", "u0", "u2", "u1"]]
        )
        // The pool is Ana, Ben, Cal, Dee, Eli… so u0, u1, u2, u4 in that order, whatever the
        // server sent. Ana is left of Ben on every card she appears on.
        #expect(store.shortlist(for: 1).map(\.displayName) == ["Ana", "Ben", "Cal", "Eli"])
    }

    /// The narrowing is a narrowing. Everyone else stays out.
    @Test func aNarrowedCardOffersOnlyItsOwnNames() {
        let store = RevealFixture.store(
            cardCount: 3,
            shortlists: [2: ["u0", "u3", "u7", "u9"]]
        )
        #expect(store.shortlist(for: 2).count == 4)
        #expect(store.pool.count > 4, "the fixture pool has to be bigger than a shortlist")
    }

    /// An empty shortlist means the server had no opinion, and the sheet is what it always was.
    /// This is the shape every payload had before the field existed, so it is also the answer to
    /// a stale client and to a small circle where four names *is* the pool.
    @Test func noShortlistMeansTheWholePool() {
        let store = RevealFixture.store(cardCount: 3)
        #expect(store.shortlist(for: 1).map(\.userID) == store.pool.map(\.userID))
    }

    /// A card that is not in the round at all. `focusedCard` cannot normally hold one, but the
    /// pool must not vanish if it ever does.
    @Test func anUnknownCardFallsBackToTheWholePool() {
        let store = RevealFixture.store(cardCount: 3, shortlists: [1: ["u0", "u1"]])
        #expect(store.shortlist(for: 99).count == store.pool.count)
    }

    /// Names the pool has never heard of are dropped rather than rendered as blanks…
    @Test func namesOutsideThePoolAreDropped() {
        let store = RevealFixture.store(
            cardCount: 3,
            shortlists: [1: ["u0", "u1", "ghost", "another-ghost"]]
        )
        #expect(store.shortlist(for: 1).map(\.displayName) == ["Ana", "Ben"])
    }

    /// …but a card left with nothing widens back out. Four unknown names would otherwise render
    /// as a card with no way to answer it, on a screen with a countdown running.
    @Test func aCardThatNarrowsToNothingWidensBackOut() {
        let store = RevealFixture.store(cardCount: 3, shortlists: [1: ["ghost", "phantom"]])
        #expect(store.shortlist(for: 1).map(\.userID) == store.pool.map(\.userID))
    }

    /// The caller is never among their own candidates — the server excludes them, and the store
    /// filters the pool by `me` besides. Both locks, because the payload is the one that can
    /// change without this target being rebuilt.
    @Test func theCallerIsNeverOffered() {
        let store = RevealFixture.store(
            cardCount: 3,
            shortlists: [1: ["u0", "me", "u1", "u2"]]
        )
        #expect(!store.shortlist(for: 1).contains { $0.userID == "me" })
    }

    /// A name placed from the full pool that is not one of the four stays on the card and is
    /// **not** padded into the pool. Clearing it is the card's job — the `✕` on the inline chip
    /// — and a fifth chip appearing only for people who had already guessed would make the
    /// candidate count depend on what you had done rather than on the round.
    @Test func anOutsideAssignmentIsNotPaddedIn() {
        let store = RevealFixture.store(cardCount: 3, shortlists: [1: ["u0", "u1", "u2", "u3"]])
        store.tapName("u9")
        store.tapCard(1)

        #expect(store.viewState.assignment(for: 1) == .guessed(name: "Jo"))
        #expect(store.shortlist(for: 1).count == 4)
        #expect(!store.shortlist(for: 1).contains { $0.userID == "u9" })
    }

    /// …and clearing the card is what removes it, exactly as for a name from the four.
    @Test func clearingTheCardRemovesAnOutsideAssignment() {
        let store = RevealFixture.store(cardCount: 3, shortlists: [1: ["u0", "u1", "u2", "u3"]])
        store.tapName("u9")
        store.tapCard(1)
        store.clearGuess(on: 1)

        #expect(store.viewState.assignment(for: 1) == .unguessed)
    }

    /// Naming one of the four over an outside name replaces it, in one tap, with no clear first.
    @Test func oneOfTheFourReplacesAnOutsideAssignment() {
        let store = RevealFixture.store(cardCount: 3, shortlists: [1: ["u0", "u1", "u2", "u3"]])
        store.tapName("u9")
        store.tapCard(1)
        store.tapCard(1)
        store.tapName("u0")

        #expect(store.viewState.assignment(for: 1) == .guessed(name: "Ana"))
    }
}
