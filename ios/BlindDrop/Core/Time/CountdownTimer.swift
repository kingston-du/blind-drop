import Foundation

/// What a countdown reads, at a moment (`docs/12` §1, `docs/13` §5 rule 3).
///
/// A **value**, not a string. The words live in `docs/11` and are applied by the view; a
/// formatter down here would be a second place copy is written and the one place nobody
/// translating the app would think to look.
enum CountdownDisplay: Sendable, Equatable {
    /// The countdown has never shown a value for its current deadline: before the first
    /// response, or right after a phase transition points it at a new one. Renders `--:--:--`
    /// — the app says it does not know rather than guessing (`docs/13` §5 rule 3). A background
    /// period does *not* land here on its own: `CountdownTimer.refresh()` holds the last value
    /// it already showed for the same deadline through a loading gap rather than blanking it,
    /// and jumps to the correct one the moment the clock re-anchors.
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

    /// Roughly how long is left, as the display itself knows it, or `nil` while the clock has no
    /// anchor.
    ///
    /// It exists so a screen can react to a **threshold** without keeping a second clock of its
    /// own: `docs/08` §2's nudge appears under two hours, and the honest way to notice that is to
    /// read the countdown that is already ticking. A screen computing its own remainder from
    /// `ServerClock` would not re-render when the timer ticked — SwiftUI observes what the body
    /// reads, and the body reads this.
    ///
    /// It is the **displayed** remainder, not the exact one: the coarse form has already rounded
    /// down to the minute, and a threshold measured against what the user can see is the one that
    /// agrees with the screen.
    var secondsRemaining: Int? {
        switch self {
        case .unknown: nil
        case let .precise(hours, minutes, seconds): hours * 3600 + minutes * 60 + seconds
        case let .coarse(.hours(hours)): hours * 3600
        case let .coarse(.minutes(minutes)): minutes * 60
        case .coarse(.underAMinute): 0
        }
    }

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

    /// How many `CountdownView`s are currently pointing at this timer.
    ///
    /// `RoundScreen` hands **one** `CountdownTimer` to every phase screen (`docs/13` §2), and
    /// two of them can be mounted at once for exactly one frame — the header badge disappearing
    /// the instant a submission is sealed, as the sealed screen's own countdown appears in the
    /// same render. Each independently calls `start()` on appear and `stop()` on disappear, and
    /// SwiftUI does not promise which fires first when they belong to different subviews in one
    /// transaction. A plain "cancel on disappear" stop let the outgoing badge win that race and
    /// kill the ticker the incoming countdown had just started — the countdown froze, and only
    /// a background/foreground cycle's invalidate-and-refetch (`docs/13` §5 rule 5) ever moved
    /// it again, which is what "sometimes shows `--:--:--`" was. Counting observers instead of
    /// tracking a single on/off bit means `stop()` only ever cancels the ticker when the last
    /// observer has genuinely left, whichever order the two calls arrive in.
    private var activeObservers = 0

    /// What the view renders. `.unknown` until the clock has an anchor.
    private(set) var display: CountdownDisplay = .unknown

    init(clock: ServerClock) {
        self.clock = clock
    }

    /// Points the timer at a deadline and starts ticking. Calling it again re-points it — a
    /// screen whose round moved from `open` to `revealed` gets one timer, not two — and it is
    /// safe to call from more than one `CountdownView` at once, which is the case this timer is
    /// actually built for.
    ///
    /// A genuinely new deadline clears the display back to `.unknown` before refreshing: the
    /// previous phase's number is not a cached value for *this* countdown, and carrying it over
    /// would show the wrong event's time (`revealed in 0:03`, frozen, under a screen that has
    /// already moved on to `scored`). Re-pointing at the **same** deadline it already had — the
    /// ordinary tick, or a redundant `start()` — does not clear it, which is what lets `refresh()`
    /// hold a value across a loading gap instead of blanking to `--:--:--`.
    func start(until deadline: Date, form: CountdownForm) {
        activeObservers += 1
        if self.deadline != deadline {
            display = .unknown
        }
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

    /// Releases one observer's hold and stops ticking only once none are left. A view calls
    /// this on disappear, and `.task(id:)` cancellation covers the rest (`docs/13` §6 — never a
    /// timer that outlives the screen).
    ///
    /// There is no `deinit` doing the final stop: the tick holds a `weak self` and returns the
    /// moment it is gone, so an un-stopped timer costs one wake-up and then stops of its own
    /// accord.
    func stop() {
        activeObservers = max(0, activeObservers - 1)
        guard activeObservers == 0 else { return }
        ticker?.cancel()
        ticker = nil
    }

    /// Recomputes from the clock. Called by the tick, and by a screen the moment a response
    /// re-anchors — a countdown that only updated on its own schedule would show the wrong
    /// value for up to a second after the app had the answer.
    ///
    /// When the clock has no anchor for this deadline — mid-refetch after `willEnterForeground`
    /// invalidates it, most often — `display` is simply left alone rather than reset to
    /// `.unknown`. It already holds either the last value this exact countdown showed, or
    /// `.unknown` if it never had one (a brand-new deadline; see `start()`). Holding a number the
    /// app already knew to be correct a moment ago is not the guess `docs/13` §5 rule 3 forbids —
    /// showing a number for a deadline the app has *never* confirmed would be. The next tick after
    /// the clock re-anchors falls through to the line below and the display jumps to the true
    /// value; there is no separate "snap" step.
    func refresh() {
        guard let deadline else {
            display = .unknown
            return
        }
        guard let remaining = clock.timeRemaining(until: deadline) else { return }
        display = CountdownDisplay(remaining: remaining, form: form)
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
