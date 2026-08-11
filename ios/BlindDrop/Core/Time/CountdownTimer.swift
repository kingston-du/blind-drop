import Foundation

/// What a countdown reads, at a moment (`docs/12` §1, `docs/13` §5 rule 3).
///
/// A **value**, not a string. The words live in `docs/11` and are applied by the view; a
/// formatter down here would be a second place copy is written and the one place nobody
/// translating the app would think to look.
enum CountdownDisplay: Sendable, Equatable {
    /// The clock has no anchor: before the first response, and after a background period until
    /// the refetch lands. Renders `--:--:--` — the app says it does not know rather than
    /// guessing (`docs/13` §5 rule 3).
    case unknown
    /// `HH:MM:SS`, ticking every second, in `monoXL` with tabular figures.
    case precise(hours: Int, minutes: Int, seconds: Int)
    /// The coarse form, above `.accessibility2` (`docs/12` §1). Updates every minute.
    case coarse(Coarse)

    enum Coarse: Sendable, Equatable {
        case hours(Int)
        case minutes(Int)
        /// `docs/11` `countdown.coarse.soon` — *"under a minute"*.
        case underAMinute
    }

    /// The deadline has passed. A countdown does not go negative and it does not decide a
    /// phase transition either (`CLAUDE.md` §2.2): the screen refetches and the **server**
    /// says what happens next.
    static let elapsed = CountdownDisplay.precise(hours: 0, minutes: 0, seconds: 0)

    /// Builds the display for a number of seconds remaining, in the requested form.
    init(remaining: TimeInterval?, form: CountdownForm) {
        guard let remaining else { self = .unknown; return }
        let seconds = Int(max(0, remaining.rounded(.down)))
        switch form {
        case .precise:
            self = .precise(
                hours: seconds / 3600,
                minutes: (seconds % 3600) / 60,
                seconds: seconds % 60
            )
        case .coarse:
            // Rounded down, deliberately: "3 hours" while three hours and fifty minutes remain
            // is a countdown that under-promises. Saying "4 hours" and then jumping to "3"
            // eleven minutes later is the version that feels broken.
            if seconds >= 3600 {
                self = .coarse(.hours(seconds / 3600))
            } else if seconds >= 60 {
                self = .coarse(.minutes(seconds / 60))
            } else {
                self = .coarse(.underAMinute)
            }
        }
    }
}

/// The thing a countdown view watches. One per countdown on screen; it owns its tick and
/// stops when the view goes away.
///
/// **It never reads `Date()`.** Every value it publishes comes from `ServerClock`, which is
/// anchored to the server and to a monotonic uptime reading — so a device clock set five years
/// wrong, or a timezone change mid-flight, moves nothing here (`docs/13` §5, AC-2).
///
/// The cadence follows the form, not the other way round: `precise` ticks every second because
/// its last digit changes every second, and `coarse` ticks every minute because its smallest
/// unit is a minute. A one-second tick behind a "3 hours" label would wake the CPU 3,599 times
/// to render the same string.
@Observable @MainActor
final class CountdownTimer {
    private let clock: ServerClock
    private var deadline: Date?
    private var form: CountdownForm = .precise
    private var ticker: Task<Void, Never>?

    /// What the view renders. `.unknown` until the clock has an anchor.
    private(set) var display: CountdownDisplay = .unknown

    init(clock: ServerClock) {
        self.clock = clock
    }

    /// Points the timer at a deadline and starts ticking. Calling it again re-points it — a
    /// screen whose round moved from `open` to `revealed` gets one timer, not two.
    func start(until deadline: Date, form: CountdownForm) {
        self.deadline = deadline
        self.form = form
        refresh()

        ticker?.cancel()
        let interval: Duration = form == .precise ? .seconds(1) : .seconds(60)
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self else { return }
                await MainActor.run { self.refresh() }
            }
        }
    }

    /// Stops ticking. A view calls this on disappear, and `.task(id:)` cancellation covers the
    /// rest (`docs/13` §6 — never a timer that outlives the screen).
    ///
    /// There is no `deinit` doing this: the tick holds a `weak self` and returns the moment it
    /// is gone, so an un-stopped timer costs one wake-up and then stops of its own accord.
    func stop() {
        ticker?.cancel()
        ticker = nil
    }

    /// Recomputes from the clock. Called by the tick, and by a screen the moment a response
    /// re-anchors — a countdown that only updated on its own schedule would show `--:--:--`
    /// for up to a second after the app had the answer.
    func refresh() {
        guard let deadline else {
            display = .unknown
            return
        }
        display = CountdownDisplay(remaining: clock.timeRemaining(until: deadline), form: form)
    }

    /// Whether the deadline has passed, or `nil` while the clock is unanchored.
    ///
    /// The screen refetches on `true`; it does **not** move the round itself. Phase
    /// transitions belong to the server and to nothing else (`CLAUDE.md` §2.2), and a client
    /// that flipped its own state at zero would show a reveal that had not happened.
    var hasElapsed: Bool? {
        guard let deadline, let remaining = clock.timeRemaining(until: deadline) else { return nil }
        return remaining <= 0
    }
}
