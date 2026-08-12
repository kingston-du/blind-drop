import Foundation

/// The hour a group's songs come out — `docs/02` §1's `reveal_hour`, and the only setting a
/// group has.
///
/// It is a wall-clock hour in the **group's** timezone, not an instant, which is why it is an
/// `Int` on the wire and why formatting it needs no clock at all. `ServerClock` is the source
/// of *time*; this is the source of *how an hour is written down*, and the two do not overlap —
/// nothing here reads the current time, and nothing here needs to.
enum RevealHour {

    /// `docs/04` §3: `reveal_hour` is optional, defaults to 20, range 18…21.
    static let allowed = 18...21
    static let `default` = 20

    /// Ten hours before the reveal, songs open (`docs/02` §1).
    static let openLeadHours = 10
    /// Two hours after, the answers land.
    static let scoreLagHours = 2

    /// The hour as a person reads it — *"8:00 PM"* in an en-US locale, *"20:00"* where that is
    /// how a clock is written.
    ///
    /// Built from a fixed reference instant rather than from today, so it is a pure function of
    /// the hour and the locale. `Date(timeIntervalSinceReferenceDate:)` is not `Date()`: it
    /// names an instant rather than asking the device what time it is, which is the distinction
    /// `docs/13` §5 rule 1 actually draws.
    static func formatted(_ hour: Int, locale: Locale = .current) -> String {
        // 2001-01-01 00:00:00 UTC, plus the hour. Formatted in UTC so the hour that comes out
        // is the hour that went in, whatever timezone the device is sitting in.
        let instant = Date(timeIntervalSinceReferenceDate: TimeInterval(hour) * 3600)
        return instant.formatted(
            Date.FormatStyle(locale: locale, timeZone: TimeZone(identifier: "UTC") ?? .gmt)
                .hour(.defaultDigits(amPM: .abbreviated))
                .minute(.twoDigits)
        )
    }

    /// The hour songs open, wrapped into the same day (`docs/02` §1: reveal at 20:00 means the
    /// window opens at 10:00).
    static func opensHour(revealHour: Int) -> Int {
        (revealHour - openLeadHours + 24) % 24
    }

    /// The hour the answers land.
    static func scoresHour(revealHour: Int) -> Int {
        (revealHour + scoreLagHours) % 24
    }
}
