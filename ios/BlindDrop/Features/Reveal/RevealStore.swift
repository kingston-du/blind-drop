import Foundation

/// The guess sheet's state and the two ways a person fills it in (`docs/08` §6, `E11-02`).
///
/// > *"Two directions, both supported, because 16-year-olds will try both."*
///
/// Both directions are the same two facts — a focused card and a selected name — resolved in
/// whichever order they arrive. That is why this is one small machine rather than two code
/// paths: the moment both facts exist, the assignment happens and both are consumed. Tapping a
/// card when a name is already selected, and tapping a name when a card is already focused, run
/// through the identical `assign(_:to:)`.
///
/// **No gesture is the only way to do anything** (`docs/12` §5): every operation here is reached
/// by a tap, and each has a VoiceOver equivalent on the card or the chip. There is no
/// drag-and-drop, no swipe-to-assign, and no required long-press — which is also the faster
/// interaction for the ninety-second budget `docs/08` gives this screen.
@Observable @MainActor
final class RevealStore {

    // MARK: - The round

    /// Every card in the round, in the server's order. The caller's own card is here too — the
    /// numbering must not have a hole (`docs/08` §6).
    private(set) var cards: [CardDTO]

    /// The names that can be assigned: this round's submitters **minus the caller**.
    ///
    /// `docs/04` §4 returns the pool with the caller included, deliberately, so `S` is derivable
    /// without the client counting anything it should not. Removing themselves is the client's
    /// job and it happens once, here.
    private(set) var pool: [MemberDTO]

    /// The caller's own card, or `nil` if they did not drop tonight.
    private(set) var myCardNumber: Int?

    /// Whether the caller may guess at all. **Taken from the server and never derived**
    /// (`docs/04` §4, `E11-05`): "did they submit" is a fact about the round that the client is
    /// deliberately not able to compute during `open`, and it does not become the client's to
    /// compute afterwards.
    private(set) var canGuess: Bool

    // MARK: - The sheet

    /// Card number → the guessed member's `user_id`. The caller's own answer, and nobody else's.
    private(set) var assignments: [Int: String] = [:]

    // MARK: - The interaction

    /// The card wearing the `ultramarine` focus ring, if any.
    private(set) var focusedCard: Int?

    /// The selected chip's `user_id`, if any.
    private(set) var selectedMember: String?

    /// The last thing worth saying out loud, posted by the view as an `.announcement` and then
    /// cleared (`docs/12` §2). Held as state rather than posted from here so that the store
    /// stays free of UIKit and stays testable — the assertion is on this string.
    private(set) var announcement: String?

    init(cards: [CardDTO], pool: [MemberDTO], myCardNumber: Int?, canGuess: Bool, me: String?) {
        self.cards = cards
        self.pool = pool.filter { $0.userID != me }
        self.myCardNumber = myCardNumber
        self.canGuess = canGuess
    }

    /// Adopts the caller's saved sheet — what `GET /rounds/current` returned in `my_guesses`.
    ///
    /// Separate from `init` because a re-fetch must not reset the interaction: a user mid-tap
    /// when a refresh lands keeps their focused card.
    func adopt(_ guesses: [GuessDTO]) {
        assignments = Dictionary(
            guesses.map { ($0.cardNumber, $0.guessedUserID) },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    // MARK: - Deriving the view

    /// The names as the cards print them. `E11-03` replaces this with the disambiguating
    /// version (`Sam B.` / `Sam K.`); everything downstream reads a resolved string either way.
    var displayNames: [String: String] {
        Dictionary(pool.map { ($0.userID, $0.displayName) }, uniquingKeysWith: { first, _ in first })
    }

    /// What `RevealScreen` draws.
    var viewState: RevealViewState {
        let names = displayNames
        return RevealViewState(
            cards: cards,
            myCardNumber: myCardNumber,
            canGuess: canGuess,
            guesses: assignments.compactMapValues { names[$0] },
            answersAt: answersAt
        )
    }

    /// When the answers land. Set by whoever loaded the round; `E11-06` wires the store to the
    /// API and this becomes part of that load.
    var answersAt: Date = .distantFuture

    /// Every card the caller could put a name on: all of them except their own.
    ///
    /// `docs/04` §4 calls this `assignable_count` and defines it as `S − 1`. Computed the same
    /// way here so the progress line agrees with the server's own arithmetic.
    var assignableCount: Int {
        cards.count - (myCardNumber == nil ? 0 : 1)
    }

    /// How many of them carry a name. Assignments to the caller's own card are impossible
    /// (`assign(_:to:)` refuses), so this needs no filtering.
    var assignedCount: Int { assignments.count }

    /// *"6 of 7 assigned"* (`docs/11` — `reveal.progress`).
    var progress: String {
        Copy.format("reveal.progress", assignedCount, assignableCount)
    }

    /// The chip states the pool renders (`docs/07` §5).
    func chipState(for member: MemberDTO) -> NameChip.State {
        if selectedMember == member.userID { return .selected }
        if let card = cardNumber(assignedTo: member.userID) { return .consumed(cardNumber: card) }
        return .unused
    }

    /// Which card a member is currently on, if any.
    func cardNumber(assignedTo userID: String) -> Int? {
        // Sorted, because `assignments` is a dictionary and a member who somehow sat on two
        // cards would otherwise make the chip's announced card number vary run to run.
        assignments.filter { $0.value == userID }.keys.min()
    }

    // MARK: - The two directions

    /// A card was tapped.
    ///
    /// If a chip is already selected this is the second half of *tap name → tap card* and the
    /// assignment lands. Otherwise the card takes the focus ring and waits for a name. Tapping
    /// the focused card again releases it — a focus ring with no way out is a trap.
    func tapCard(_ number: Int) {
        guard isGuessable(number) else { return }
        if let member = selectedMember {
            assign(member, to: number)
            return
        }
        focusedCard = focusedCard == number ? nil : number
    }

    /// A name chip was tapped.
    ///
    /// If a card is focused this is the second half of *tap card → tap name*. Otherwise the chip
    /// selects and waits for a card. Tapping the selected chip again deselects it.
    ///
    /// A **consumed** chip is tapped exactly like an unused one, and that is the rule `docs/08`
    /// §6 asks for: *"tapping a consumed name moves it, clearing its previous card"*. The move is
    /// the default behaviour rather than a blocked action, because blocking it would make the
    /// commonest correction — "no, Cal was the other one" — into two operations.
    func tapName(_ userID: String) {
        guard canGuess else { return }
        if let card = focusedCard {
            assign(userID, to: card)
            return
        }
        selectedMember = selectedMember == userID ? nil : userID
    }

    /// The `✕` on an inline chip (`docs/08` §6), and the card's "Clear guess" action.
    func clearGuess(on cardNumber: Int) {
        guard assignments.removeValue(forKey: cardNumber) != nil else { return }
        // The card that was just emptied takes the focus, because the overwhelmingly likely next
        // action is putting a different name on it.
        focusedCard = cardNumber
    }

    /// The view has spoken it; do not say it twice.
    func consumeAnnouncement() {
        announcement = nil
    }

    // MARK: - Assigning

    /// The one place an assignment happens, whichever direction reached it.
    private func assign(_ userID: String, to cardNumber: Int) {
        guard isGuessable(cardNumber), displayNames[userID] != nil else { return }

        // The move. A name lives on at most one card at a time in this UI, so putting it on a
        // new one takes it off the old one. The API permits the same name on two cards
        // (`docs/04` §4 rule 6 — "players are allowed to be wrong in that particular way"), and
        // this is the UI discouraging it without forbidding it: the user can still double up by
        // assigning, moving on, and coming back.
        for (card, member) in assignments where member == userID && card != cardNumber {
            assignments.removeValue(forKey: card)
        }

        assignments[cardNumber] = userID
        if let name = displayNames[userID] {
            announcement = Copy.A11y.guessAssigned(cardNumber: cardNumber, name: name)
        }

        selectedMember = nil
        // *"Assignment advances focus to the next unassigned card"* (`docs/08` §6) — the sheet
        // fills top to bottom without a tap in between.
        focusedCard = nextUnassignedCard(after: cardNumber)
    }

    /// The next card without a name, searching forward from `number` and wrapping once.
    ///
    /// Wrapping matters: a user who fills the sheet out of order and lands on the last card
    /// should be taken back to the gap near the top, not dropped out of the flow.
    func nextUnassignedCard(after number: Int) -> Int? {
        let numbers = cards.map(\.cardNumber)
        guard let index = numbers.firstIndex(of: number) else { return nil }
        let ordered = numbers[(index + 1)...] + numbers[..<index]
        return ordered.first { isGuessable($0) && assignments[$0] == nil }
    }

    /// A card the caller may put a name on: not theirs, and only if they may guess at all.
    func isGuessable(_ number: Int) -> Bool {
        canGuess && number != myCardNumber
    }
}
