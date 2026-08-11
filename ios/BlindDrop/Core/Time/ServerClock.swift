import Foundation

/// The only source of time in the app (`docs/13` §5, AC-2).
///
/// The device wall clock is not a source of truth. The *value* comes from the server's
/// `server_now`; the *elapsed time since that value* comes from `ProcessInfo.systemUptime`,
/// which is monotonic. Setting the phone to 2029, changing its timezone, or crossing a date
/// line changes no countdown in this app, because none of them moves an uptime reading.
///
/// Three rules from `docs/13` §5 are visible in the shape of this type rather than in its
/// comments:
///
/// - `now` is **optional**. Before the first response the app does not know what time it is
///   and says `--:--:--` rather than guessing. A non-optional `now` would make the guess
///   unavoidable.
/// - The anchor is `(uptime, serverTime)` and nothing else, so there is no field a device
///   clock could be written into.
/// - `invalidate()` exists because `systemUptime` does not advance while the device is asleep.
///   After any background period the anchor is assumed stale, and a refetch precedes any
///   countdown render.
///
/// `Date()` appears nowhere in the app outside this file — `ios/scripts/lint.sh` fails the
/// build on one, in a view, a store, a formatter, or a log.
@Observable @MainActor
final class ServerClock {

    /// The reading the whole type is built on. `nil` until the first response.
    private var anchor: Anchor?

    private struct Anchor {
        let uptime: TimeInterval
        let serverTime: Date
    }

    /// Where "how long has it been" comes from. A parameter, so a test can advance time
    /// without sleeping — and specifically **not** a `Date` provider: there is no seam here
    /// through which the device wall clock could be substituted, which is the property AC-2
    /// is about.
    private let uptime: @Sendable () -> TimeInterval

    init(uptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.uptime = uptime
    }

    /// Re-anchors from a response's `server_now`. Called by `APIClient` on **every** response,
    /// success or failure, which is why drift never accumulates: the offset is never older
    /// than the last thing the app did (`docs/13` §5 rule 4).
    func sync(serverNow: Date) {
        anchor = Anchor(uptime: uptime(), serverTime: serverNow)
    }

    /// `docs/13` §5 rule 5: an uptime reading does not advance while the device is asleep, so
    /// after any background period the anchor is a lie of exactly the length of the nap.
    /// `RootView` invalidates on `willEnterForeground` and refetches before rendering a
    /// countdown, and until that response lands every countdown reads `nil`.
    func invalidate() {
        anchor = nil
    }

    /// The server's time, now — or `nil` when the app genuinely does not know.
    var now: Date? {
        guard let anchor else { return nil }
        return anchor.serverTime.addingTimeInterval(uptime() - anchor.uptime)
    }

    /// Seconds until a deadline, or `nil` when the clock is unanchored. Negative once the
    /// deadline has passed — the caller decides what that means, because "the reveal is behind
    /// us" is a refetch and "the countdown hit zero" is a render, and only the screen knows
    /// which it is looking at.
    func timeRemaining(until deadline: Date) -> TimeInterval? {
        now.map { deadline.timeIntervalSince($0) }
    }

    /// Whether the clock has an anchor at all. The screens ask this rather than comparing
    /// `now` against something.
    var isAnchored: Bool { anchor != nil }
}

/// Formatting on the **group's** clock (`docs/13` §5 rule 6).
///
/// Every date and hour the app prints is the group's, never the device's: a member who lands in
/// Lisbon still plays a round that opens and reveals on the group's wall clock, and a screen
/// that formatted `reveals_at` in `TimeZone.current` would tell them the reveal is at 3am.
///
/// `TimeZone.current` appears nowhere in this app. There is no fallback to it here either — an
/// unknown identifier falls back to UTC, which is visibly wrong in a way that a silently local
/// time is not.
struct GroupCalendar: Sendable, Equatable {
    let timeZone: TimeZone

    init(timezone identifier: String) {
        timeZone = TimeZone(identifier: identifier) ?? TimeZone(identifier: "UTC")!
    }

    /// The group-local calendar day of an instant, `YYYY-MM-DD` — the same string the server
    /// puts in `local_date`, so the two can be compared without reformatting either.
    ///
    /// Fixed format and a fixed locale: this is an identifier, not something anybody reads. The
    /// only thing about it that varies is the zone, which is the group's.
    func localDate(of instant: Date) -> String {
        instant.formatted(
            Date.FormatStyle(date: .numeric, time: .omitted, timeZone: timeZone)
                .year(.extended()).month(.twoDigits).day(.twoDigits)
                .locale(Locale(identifier: "en_US_POSIX"))
        )
        .split(separator: "/")
        .map(String.init)
        .reordered()
    }

    /// The wall clock of an instant in the group's zone — "8:00 PM" — in the reader's locale,
    /// because the *format* is theirs even though the *zone* is the group's.
    func timeOfDay(of instant: Date) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = timeZone
        return instant.formatted(style)
    }

    /// Whether two instants land on the same group-local day. The comparison the countdown
    /// copy needs — "tonight" is a group-local night, not a device-local one.
    func isSameDay(_ a: Date, _ b: Date) -> Bool {
        localDate(of: a) == localDate(of: b)
    }
}

private extension [String] {
    /// `MM/DD/YYYY` → `YYYY-MM-DD`. The POSIX numeric style is the one format Foundation will
    /// not vary on us; this puts its three parts back in the order `docs/04` uses.
    func reordered() -> String {
        guard count == 3 else { return joined(separator: "-") }
        return "\(self[2])-\(self[0])-\(self[1])"
    }
}
