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

    /// Whether the deadline has passed, or `nil` while the clock is unanchored.
    ///
    /// The screen refetches on `true`; it does **not** move the round itself. Phase
    /// transitions belong to the server and to nothing else (`CLAUDE.md` §2.2), and a client
    /// that flipped its own state at zero would show a reveal that had not happened.
    ///
    /// **A stored property, written by `refresh()`, not computed on read.** It used to be
    /// computed — `deadline` and `clock`'s anchor read fresh on every access — which is correct
    /// for *value* but wrong for *notification*: those are the only two things Observation
    /// tracks here, and neither one changes merely because a second passed. The ticker's own
    /// tick writes `display` (a stored property), which is why the visible digits update every
    /// second; it never touched anything `hasElapsed` depended on, so nothing ever told a
    /// screen watching `hasElapsed` — as `RoundScreen`'s `.onChange(of: timer.hasElapsed)` does —
    /// that the moment had arrived. The countdown kept ticking correctly right in front of the
    /// user while the screen behind it never re-read the clock, because nothing woke it up to.
    ///
    /// Writing it here, from `refresh()` on the tick where it actually changes, fixes that at the
    /// root: the tick that already updates `display` now also updates this, and updating a stored
    /// `@Observable` property is itself the notification — every reader of `hasElapsed`, on
    /// whatever screen, is invalidated on the very next tick that flips it, the same cadence the
    /// visible digits already use. This is not a poll bolted on beside the countdown; it is the
    /// countdown's own tick finally reaching the one other thing it was supposed to.
    ///
    /// `refresh()` only performs the write when the value actually changes — `@Observable`
    /// notifies on every `set` regardless of whether the new value differs, so an unconditional
    /// write here would re-invalidate every `hasElapsed` reader once a tick, for as long as a
    /// countdown is on screen, which is the exact cost class this file's tick-cadence comment
    /// above already cares about avoiding.
    private(set) var hasElapsed: Bool?

    init(clock: ServerClock) {
        self.clock = clock
    }

    /// **One observer arriving.** Takes a hold, points the timer, and starts ticking. Safe to
    /// call from more than one `CountdownView` at once, which is the case this timer is actually
    /// built for — see `activeObservers`.
    ///
    /// It is paired with `stop()` one-for-one, and that pairing is the whole of the reference
    /// count's correctness. A view that is already on screen and merely wants the timer aimed
    /// somewhere else calls `repoint(until:form:)` instead: it has already taken its hold, and
    /// taking a second one it will never release is a hold that never reaches zero, which is a
    /// ticker that outlives every screen that ever wanted it — the exact thing `stop()`'s note
    /// says cannot happen.
    func start(until deadline: Date, form: CountdownForm) {
        activeObservers += 1
        repoint(until: deadline, form: form)
    }

    /// **Aims an already-observed timer somewhere else**, without touching the reference count.
    ///
    /// `CountdownView` re-points on two changes it can see without appearing or disappearing:
    /// the round moved to a phase that counts to a different instant, and the Dynamic Type size
    /// crossed the threshold that changes the tick cadence (`docs/12` §1). Neither is a new
    /// observer — it is the same view, still on screen, still holding the one hold it took on
    /// appear — so neither may increment.
    ///
    /// A genuinely new deadline clears the display back to `.unknown` before refreshing: the
    /// previous phase's number is not a cached value for *this* countdown, and carrying it over
    /// would show the wrong event's time (`revealed in 0:03`, frozen, under a screen that has
    /// already moved on to `scored`). Re-pointing at the **same** deadline it already had — the
    /// ordinary tick, or a redundant call — does not clear it, which is what lets `refresh()`
    /// hold a value across a loading gap instead of blanking to `--:--:--`.
    func repoint(until deadline: Date, form: CountdownForm) {
        if self.deadline != deadline {
            display = .unknown
        }
        self.deadline = deadline
        let cadenceChanged = self.form != form
        self.form = form
        refresh()

        // The ticker is rebuilt only when it is not running or when its interval is now wrong.
        // Rebuilding it on every call restarts the second from *this instant* instead of from
        // the one the countdown has been keeping, so a second observer arriving 900ms into a
        // second pushed the next visible digit change out by nearly a whole extra second — a
        // hitch in the one thing on the screen that is supposed to be metronomic.
        guard ticker == nil || cadenceChanged else { return }
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
    ///
    /// `hasElapsed` is only ever *written* on an actual transition, including into and out of
    /// the unanchored `nil` — not because a same-value write would be wrong, but because
    /// `@Observable` notifies on every `set`, value-change or not. Writing it unconditionally
    /// on every tick would re-invalidate every reader of `hasElapsed` once a second (or once a
    /// minute, coarse) for as long as a Sealed/Open/Reveal/Voided screen is on screen — a real,
    /// continuous cost this fix would have introduced, in the same file that already reasons
    /// carefully about waking the CPU only when something the display shows actually changes
    /// (see the tick-cadence comment above). Guarding the write still notifies on the one tick
    /// that matters — the one where the value actually flips — which is all `RoundScreen`'s
    /// `.onChange(of: timer.hasElapsed)` needs.
    ///
    /// Unlike `display`, which is worth freezing at its last true value for a moment so the
    /// digits do not flicker, "has the deadline passed" has no honest frozen answer to show:
    /// `docs/13` §5 rule 3 says the app admits what it does not know, and mid-gap it does not
    /// know this either — so the unanchored branch still writes through to `nil` whenever it
    /// was not already `nil`.
    func refresh() {
        guard let deadline else {
            display = .unknown
            if hasElapsed != nil { hasElapsed = nil }
            return
        }
        guard let remaining = clock.timeRemaining(until: deadline) else {
            if hasElapsed != nil { hasElapsed = nil }
            return
        }
        display = CountdownDisplay(remaining: remaining, form: form)
        let elapsed = remaining <= 0
        if hasElapsed != elapsed { hasElapsed = elapsed }
    }
}
