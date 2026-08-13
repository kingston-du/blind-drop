import SwiftUI

/// How far through its arrival one results card is (`docs/09` §4).
///
/// Two facts rather than one, because the mark is deliberately late: the name lands, and 80ms
/// later the check or the strike lands beneath it. A single `isResolved` would either show both
/// at once or push the delay into the view.
struct ResolvePresentation: Equatable, Sendable {
    /// Whether the owner's name has arrived.
    let hasName: Bool
    /// Whether the mark on the caller's own guess has arrived.
    let hasMark: Bool
    let reducedMotion: Bool

    /// Everything already in place — what a re-opened round renders, and what a completed or
    /// skipped sequence settles to.
    static let settled = ResolvePresentation(hasName: true, hasMark: true, reducedMotion: false)
}

/// Runs the results name-resolve, once per round, and lets any scroll gesture end it.
///
/// > *"Any scroll gesture completes the entire sequence immediately. A user who already knows
/// > what they want to see must never be made to wait for an animation."* (`docs/09` §4)
///
/// That sentence is why the method is `skip()` and not `cancel()`: the sequence's **end state**
/// is the screen, so interrupting it fast-forwards rather than aborts. It is also why the
/// sequence is one awaited `run(reducedMotion:)` rather than a task per card — `ResultsScreen`'s
/// `.task` owns its lifetime, so leaving the results cancels the remaining sleeps instead of
/// leaving timers ticking behind a screen nobody is looking at.
///
/// Unlike `UnsealAnimation` there is no visibility gate. The unseal has one because a sealed
/// card that scrolled into view already unsealed would look pre-opened; a results card that
/// resolved off-screen just looks like a results card, and gating it here would fight the skip
/// rule above rather than serve it.
@Observable @MainActor
final class ResolveAnimation {

    /// The cards whose owner is showing.
    private(set) var namedCards: Set<Int> = []
    /// The cards whose mark is showing.
    private(set) var markedCards: Set<Int> = []

    private let cardNumbers: [Int]
    private let roundID: String
    private let flags: LocalFlags
    private var started = false

    init(roundID: String, cardNumbers: [Int], flags: LocalFlags) {
        self.roundID = roundID
        self.cardNumbers = cardNumbers
        self.flags = flags
        // A round already resolved on this install opens with its answers in place. The flag is
        // only *read* here and claimed in `run`, so constructing the animation twice — which a
        // body re-evaluation can do — never burns the one run.
        if flags.hasSeenResolve(roundID: roundID) { finish() }
    }

    // MARK: - What a card draws

    func presentation(for cardNumber: Int, reducedMotion: Bool) -> ResolvePresentation {
        ResolvePresentation(
            hasName: namedCards.contains(cardNumber),
            hasMark: markedCards.contains(cardNumber),
            reducedMotion: reducedMotion
        )
    }

    /// Whether anything is still on its way. The screen stops arming the skip gesture once there
    /// is nothing left to skip.
    var isRunning: Bool { markedCards.count < cardNumbers.count }

    // MARK: - The sequence

    /// One thing arriving, and when.
    ///
    /// The sequence is expressed as a **timeline rather than a loop with a nested delay** so the
    /// whole of `docs/09` §4's cadence — 120ms between names, each mark 80ms after its own name
    /// — is one sorted list a test can read, and so every wait belongs to the single structured
    /// task the screen awaits.
    struct Event: Equatable, Sendable {
        enum Kind: Equatable, Sendable { case name, mark }

        /// Milliseconds from the start of the sequence.
        let at: Int
        let cardNumber: Int
        let kind: Kind
    }

    /// The events in the order they happen. Ties put the name before its mark, which is the
    /// order they mean something in and keeps the list deterministic if the two numbers in
    /// `Motion.Resolve` ever meet.
    static func timeline(cardNumbers: [Int]) -> [Event] {
        cardNumbers.enumerated()
            .flatMap { index, number -> [Event] in
                let start = index * Motion.Resolve.stagger
                return [
                    Event(at: start, cardNumber: number, kind: .name),
                    Event(at: start + Motion.Resolve.markDelay, cardNumber: number, kind: .mark),
                ]
            }
            .sorted { left, right in
                left.at == right.at ? left.kind == .name && right.kind == .mark : left.at < right.at
            }
    }

    /// Top to bottom, once per round.
    ///
    /// Under reduced motion `docs/09` §5 asks for *"all names at once, no stagger"*, which is
    /// the second guard: the whole set lands in one mutation and the crossfade the card applies
    /// is what remains of the moment. Reduced motion removes the movement, not the arrival.
    func run(reducedMotion: Bool) async {
        guard !started else { return }
        started = true
        guard flags.beginResolve(roundID: roundID), !reducedMotion else {
            finish()
            return
        }

        var elapsed = 0
        for event in Self.timeline(cardNumbers: cardNumbers) {
            if event.at > elapsed {
                guard await wait(.milliseconds(event.at - elapsed)) else { return }
                elapsed = event.at
            }
            switch event.kind {
            case .name: namedCards.insert(event.cardNumber)
            case .mark: markedCards.insert(event.cardNumber)
            }
        }
    }

    /// A scroll gesture, or anything else that means *"I am done waiting"*.
    ///
    /// Idempotent, because a drag delivers many changes and the screen calls this on each one.
    func skip() {
        guard isRunning else { return }
        finish()
    }

    /// - Returns: `false` when the sequence must stop — the task was cancelled, or a scroll
    ///   settled everything while this sleep was in flight. Both end at the same screen, so
    ///   neither needs to be told apart from the other by the caller.
    private func wait(_ duration: Duration) async -> Bool {
        do {
            try await Task.sleep(for: duration)
        } catch {
            finish()
            return false
        }
        return isRunning
    }

    private func finish() {
        namedCards = Set(cardNumbers)
        markedCards = Set(cardNumbers)
    }
}
