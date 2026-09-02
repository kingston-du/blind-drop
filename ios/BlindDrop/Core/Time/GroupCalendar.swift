import Foundation

/// The two calendar questions the round screens ask, on the **group's** clock
/// (`docs/13` §5 rule 6).
///
/// An extension rather than a second type: `GroupCalendar` already exists for formatting on the
/// group's zone (`Core/Time/ServerClock.swift`), and a round's day and a round's tomorrow are the
/// same concern. What they add is a *calendar* — `Foundation.Calendar` rather than a
/// `FormatStyle` — because both of them are arithmetic on days rather than on instants:
///
/// 1. **Writing a round's day down.** `docs/08` §2 puts *"Monday 10 August"* under the header. The
///    round carries `local_date` as a `YYYY-MM-DD` string precisely because it is a calendar day
///    rather than an instant, so turning it into words needs a calendar and a zone.
/// 2. **Naming the next window.** A `voided` round counts to *tomorrow's* open (`docs/08` §5) and
///    the payload carries only today's. One day added in the group's zone is the honest
///    derivation: `Calendar` moves the **wall clock**, so a group that crosses a DST boundary
///    tonight still opens at 10:00 their time rather than at 09:00.
///
/// **Nothing here reads the current time.** Both are pure functions of their arguments, which is
/// why `Date()` never appears and why neither needs a clock to be tested (`docs/13` §5 rule 1).
extension GroupCalendar {

    /// A `Calendar` on the group's zone.
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// `"2026-08-10"` → *"Monday 10 August"* (`docs/08` §2).
    ///
    /// `nil` for a string that is not a calendar date, rather than a substitute. A header line
    /// that is simply absent is better than one that is confidently wrong about what day it is.
    func headline(localDate: String, locale: Locale = .current) -> String? {
        guard let day = instant(atNoonOn: localDate) else { return nil }
        return day.formatted(
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone)
                .weekday(.wide)
                .day(.defaultDigits)
                .month(.wide)
        )
    }

    /// `"2026-08-10"` → *"Mon, Aug 10"* — the header's date when the full one will not share a
    /// row with the badge (`docs/08` §2).
    ///
    /// Every part of `headline` is still here; only the two long words are abbreviated, and by
    /// `Date.FormatStyle` rather than by truncating strings, so a locale that orders or names
    /// them differently gets its own abbreviation instead of an English one cut short. The
    /// header picks between the two by measuring — see `RoundHeader.standing` — and VoiceOver is
    /// read the full form either way, because a screen reader has no width problem to solve.
    func shortHeadline(localDate: String, locale: Locale = .current) -> String? {
        guard let day = instant(atNoonOn: localDate) else { return nil }
        return day.formatted(
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone)
                .weekday(.abbreviated)
                .day(.defaultDigits)
                .month(.abbreviated)
        )
    }

    /// `"2026-08-10"` → *"10 August"* (`docs/10` §2).
    ///
    /// The share card's date, which is the same day the header names with the weekday dropped.
    /// A card that has left the group is read days or weeks later, and *"Monday"* is the part of
    /// that sentence that stops being useful first — the date is what says which night this was.
    func shareDate(localDate: String, locale: Locale = .current) -> String? {
        guard let day = instant(atNoonOn: localDate) else { return nil }
        return day.formatted(
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone)
                .day(.defaultDigits)
                .month(.wide)
        )
    }

    /// Midday on a `YYYY-MM-DD` day, in the group's zone.
    ///
    /// Built from components rather than parsed by a formatter, and taken at **noon** rather than
    /// midnight: on a spring-forward day midnight itself can be a time that did not happen, and
    /// asking for it gets an answer an hour into the wrong day.
    func instant(atNoonOn localDate: String) -> Date? {
        let parts = localDate.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return calendar.date(from: components)
    }

    /// The same wall-clock time, one day later (`docs/08` §5).
    ///
    /// `addingTimeInterval(86_400)` would be a different thing and wrong twice a year: on the day
    /// a zone gains an hour it lands at 09:00, and the voided screen's countdown would be an hour
    /// out for everybody in that group.
    func nextDay(_ instant: Date) -> Date {
        calendar.date(byAdding: .day, value: 1, to: instant) ?? instant
    }
}
