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

    typealias GuessSaver = @Sendable ([GuessAssignment]) async throws -> GuessSheetDTO
    static let saveDebounce = Duration.milliseconds(600)

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

    /// Why not, when `canGuess` is false (`docs/04` §4). Set exactly when it is.
    private(set) var cannotGuessReason: CannotGuessReason?

    /// The line that replaces the button (`docs/11` — `reveal.blocked.*`), or `nil` when the
    /// caller can play.
    ///
    /// The two reasons get **distinct copy** because they are distinct situations: one is a
    /// consequence of something the user did not do, the other of when they arrived, and telling
    /// a person who joined this afternoon that they *"didn't drop tonight"* would be blaming
    /// them for a round they were never in.
    var blockedReason: String? {
        guard !canGuess else { return nil }
        return switch cannotGuessReason {
        case .notASubmitter: Copy.string("reveal.blocked.notsubmitter")
        case .joinedLate: Copy.string("reveal.blocked.joinedlate")
        // `can_guess: false` with no reason is a server the client does not argue with: it still
        // withholds the apparatus, and says the one thing that is true in every such case.
        case nil: Copy.string("reveal.blocked.canview")
        }
    }

    // MARK: - The sheet

    /// Card number → the guessed member's `user_id`. The caller's own answer, and nobody else's.
    private(set) var assignments: [Int: String] = [:]

    /// `nil` is quiet; a key is rendered inline under the apparatus. A failed save never locks
    /// the sheet and never discards the local assignments.
    private(set) var saveErrorKey: String?
    private(set) var isSaving = false
    private(set) var isLocked = false

    // MARK: - The interaction

    /// The card wearing the `ultramarine` focus ring, if any.
    private(set) var focusedCard: Int?

    /// The selected chip's `user_id`, if any.
    private(set) var selectedMember: String?

    /// The last thing worth saying out loud, posted by the view as an `.announcement` and then
    /// cleared (`docs/12` §2). Held as state rather than posted from here so that the store
    /// stays free of UIKit and stays testable — the assertion is on this string.
    private(set) var announcement: String?

    private let saveGuesses: GuessSaver?
    private let haptics: HapticEngine?
    private let onLockInSaved: (() -> Void)?
    private var saveTask: Task<Void, Never>?
    private var editRevision = 0

    var hasPendingSave: Bool { saveTask != nil }

    init(
        cards: [CardDTO],
        pool: [MemberDTO],
        myCardNumber: Int?,
        canGuess: Bool,
        cannotGuessReason: CannotGuessReason? = nil,
        me: String?,
        saveGuesses: GuessSaver? = nil,
        haptics: HapticEngine? = nil,
        onLockInSaved: (() -> Void)? = nil
    ) {
        self.cards = cards
        self.pool = pool.filter { $0.userID != me }
        self.myCardNumber = myCardNumber
        self.canGuess = canGuess
        self.cannotGuessReason = cannotGuessReason
        self.saveGuesses = saveGuesses
        self.haptics = haptics
        self.onLockInSaved = onLockInSaved
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

    /// The names as the cards and the pool print them. A `user_id` remains the identity through
    /// assignment; this is presentation only, resolved once so a chip and its matching card can
    /// never disagree about whether it is *Sam B.* or *Sam K.*.
    var displayNames: [String: String] {
        NameDisambiguator.labels(for: pool)
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

    /// When the answers land. Set from the server-owned round loaded by `RoundStore`.
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
        guard canGuess, !isLocked else { return }
        if let card = focusedCard {
            assign(userID, to: card)
            return
        }
        selectedMember = selectedMember == userID ? nil : userID
    }

    /// The `✕` on an inline chip (`docs/08` §6), and the card's "Clear guess" action.
    func clearGuess(on cardNumber: Int) {
        guard canGuess, !isLocked else { return }
        guard assignments.removeValue(forKey: cardNumber) != nil else { return }
        // The card that was just emptied takes the focus, because the overwhelmingly likely next
        // action is putting a different name on it.
        focusedCard = cardNumber
        didEdit()
    }

    /// Confirms the current sheet and dismisses its active focus. Saving has already happened on
    /// every edit; this also replaces a pending debounce with an immediate final whole-sheet PUT.
    ///
    /// **Clears `saveErrorKey` first, like `didEdit()` does.** `RevealScreen` collapses the sheet
    /// to peek the moment this is called (`lockIn?()`, optimistic), and `GuessSheet` forces it
    /// back open on `saveErrorKey`'s `onChange`. That only fires on a *change of value* — retry
    /// after an offline failure and fail again the same way, and an uncleared key would still
    /// read `"error.offline"` before and after, so the view never sees a transition and the sheet
    /// stays collapsed on a failure nobody can see. Starting from `nil` here guarantees the next
    /// failure, identical or not, is a real `nil → key` change and reopens the sheet every time.
    func lockIn() {
        guard canGuess, !assignments.isEmpty else { return }
        isLocked = true
        saveErrorKey = nil
        focusedCard = nil
        selectedMember = nil
        haptics?.fire(.stampLands)
        scheduleSave(debounce: false)
    }

    /// Locked is a presentation state, not a deadline. The server remains open until `scores_at`,
    /// so this affordance restores the ordinary editable sheet and the countdown keeps running.
    func changeAGuess() {
        isLocked = false
        saveErrorKey = nil
        focusedCard = cards.lazy.map(\.cardNumber).first { isAssignable($0) }
    }

    /// Warms the two notes this screen can play, once, when it appears.
    ///
    /// The reveal fires `.nameLands` on every assignment and `.stampLands` on the lock-in, and
    /// until this existed both of them played on a cold generator — the exact frame-or-two lag
    /// `SystemHaptics` was written to avoid, and the one the seal already guards against by
    /// warming at the top of its run. An assignment is a single tap with no lead-in, so there is
    /// no moment inside the interaction late enough to warm at and early enough to matter.
    func prepareHaptics() {
        haptics?.prepare(.nameLands)
        haptics?.prepare(.stampLands)
    }

    /// Collapsing the call sheet releases a half-completed tap without changing any assignment.
    func dismissSheet() {
        focusedCard = nil
        selectedMember = nil
    }

    /// The view owns the lifetime boundary. There is one task and it does not survive the screen.
    func cancelPendingSave() {
        saveTask?.cancel()
        saveTask = nil
        isSaving = false
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
        // (`docs/04` §4 rule 6 — "players are allowed to be wrong in that particular way"), while
        // this interaction deliberately makes moving a consumed chip the default correction.
        for (card, member) in assignments where member == userID && card != cardNumber {
            assignments.removeValue(forKey: card)
        }

        assignments[cardNumber] = userID
        haptics?.fire(.nameLands)
        if let name = displayNames[userID] {
            announcement = Copy.A11y.guessAssigned(cardNumber: cardNumber, name: name)
        }

        selectedMember = nil
        // *"Assignment advances focus to the next unassigned card"* (`docs/08` §6) — the sheet
        // fills top to bottom without a tap in between.
        focusedCard = nextUnassignedCard(after: cardNumber)
        didEdit()
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
        canGuess && !isLocked && isAssignable(number)
    }

    // MARK: - Saving

    private func didEdit() {
        editRevision += 1
        isLocked = false
        saveErrorKey = nil
        scheduleSave(debounce: true)
    }

    private func scheduleSave(debounce: Bool) {
        guard let saveGuesses else { return }
        saveTask?.cancel()

        let revision = editRevision
        let sheet = wholeSheet
        isSaving = true
        saveTask = Task { [weak self] in
            if debounce {
                do {
                    try await Task.sleep(for: Self.saveDebounce)
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }

            do {
                _ = try await saveGuesses(sheet)
                guard !Task.isCancelled else { return }
                self?.finishSave(revision: revision)
            } catch {
                guard !Task.isCancelled else { return }
                self?.failSave(error)
            }
        }
    }

    private var wholeSheet: [GuessAssignment] {
        cards.compactMap { card in
            guard isAssignable(card.cardNumber) else { return nil }
            return GuessAssignment(
                cardNumber: card.cardNumber,
                guessedUserID: assignments[card.cardNumber]
            )
        }
    }

    private func finishSave(revision: Int) {
        if revision == editRevision {
            saveErrorKey = nil
            if isLocked { onLockInSaved?() }
        }
        saveTask = nil
        isSaving = false
    }

    private func failSave(_ error: any Error) {
        saveErrorKey = (error as? APIError)?.copyKey ?? APIError.unreadable.copyKey
        isLocked = false
        saveTask = nil
        isSaving = false
    }

    private func isAssignable(_ number: Int) -> Bool {
        number != myCardNumber
    }
}

/// Resolves the one ambiguity a name-only guessing game cannot leave to chance.
///
/// A member may choose a multi-word display name. When two people share its leading word, the
/// pool contracts them to `Sam B.` / `Sam K.` from the next word's initial. If no distinct
/// initial is available — identical one-word names, or two `Sam B…` names — an ordinal is
/// appended to later occurrences: `Sam`, `Sam (2)`. The latter is intentionally a fallback:
/// exposing more of somebody's name just to make a label unique would defeat the point of a
/// display name in the first place.
enum NameDisambiguator {
    static func labels(for members: [MemberDTO]) -> [String: String] {
        let groups = Dictionary(grouping: members, by: baseName)
        var labels = Dictionary(uniqueKeysWithValues: members.map { ($0.userID, $0.displayName) })

        for group in groups.values where group.count > 1 {
            let initials = group.map(suffixInitial)
            let hasDistinctInitials = initials.allSatisfy { $0 != nil }
                && Set(initials.compactMap { $0 }).count == group.count

            if hasDistinctInitials {
                for (member, initial) in zip(group, initials.compactMap { $0 }) {
                    labels[member.userID] = "\(baseName(member)) \(initial)."
                }
            } else {
                for (index, member) in group.enumerated() {
                    let base = baseName(member)
                    labels[member.userID] = index == 0 ? base : "\(base) (\(index + 1))"
                }
            }
        }
        return labels
    }

    private static func baseName(_ member: MemberDTO) -> String {
        member.displayName.split(whereSeparator: \.isWhitespace).first.map(String.init)
            ?? member.displayName
    }

    private static func suffixInitial(_ member: MemberDTO) -> String? {
        let words = member.displayName.split(whereSeparator: \.isWhitespace)
        guard words.count > 1, let scalar = words[1].unicodeScalars.first else { return nil }
        return String(scalar).uppercased()
    }
}
