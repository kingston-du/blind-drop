import Foundation
import Testing
@testable import BlindDrop

/// Dates on the **group's** clock (`docs/13` §5 rule 6), and the countdown's threshold reading.
@Suite struct GroupCalendarTests {

    /// *"Monday 10 August"* — `docs/08` §2's date line, from the round's `local_date`.
    @Test func alocalDateBecomesTheHeaderLine() throws {
        let calendar = GroupCalendar(timezone: "America/New_York")
        let headline = try #require(calendar.headline(localDate: "2026-08-10", locale: Locale(identifier: "en_GB")))
        #expect(headline == "Monday 10 August")
    }

    /// *"Mon 10 Aug"* — the same day with the two long words abbreviated, which is what the
    /// header falls back to rather than breaking its second row in two.
    ///
    /// The point of the assertion is that it is **shorter and still complete**: weekday, day and
    /// month all survive, so `RoundHeader`'s middle rung is a smaller version of the date rather
    /// than a truncated one. It is also what makes the `count <` guard in `standing` meaningful.
    @Test func alocalDateAlsoHasAShortForm() throws {
        let calendar = GroupCalendar(timezone: "America/New_York")
        let locale = Locale(identifier: "en_GB")
        let short = try #require(calendar.shortHeadline(localDate: "2026-08-10", locale: locale))
        let long = try #require(calendar.headline(localDate: "2026-08-10", locale: locale))
        #expect(short == "Mon 10 Aug")
        #expect(short.count < long.count)
    }

    /// The short form refuses a garbled date on the same terms the long one does.
    @Test(arguments: ["", "2026-08", "not-a-date", "2026/08/10"])
    func agarbledDateProducesNoShortLineEither(_ raw: String) {
        #expect(GroupCalendar(timezone: "UTC").shortHeadline(localDate: raw) == nil)
    }

    /// A string that is not a calendar date produces **nothing**, rather than a substitute. A
    /// header line that is absent is better than one confidently wrong about what day it is.
    @Test(arguments: ["", "2026-08", "not-a-date", "2026/08/10"])
    func agarbledDateProducesNoLine(_ raw: String) {
        #expect(GroupCalendar(timezone: "UTC").headline(localDate: raw) == nil)
    }

    /// The day is read in the **group's** zone, not the device's. 2026-08-10 in Auckland is a
    /// different instant from 2026-08-10 in New York, and both are Monday the 10th — which is the
    /// point: the *label* is the group's calendar day either way.
    @Test(arguments: ["America/New_York", "Pacific/Auckland", "Europe/Lisbon", "UTC"])
    func thedayIsTheGroupsDay(_ timezone: String) throws {
        let calendar = GroupCalendar(timezone: timezone)
        let headline = try #require(calendar.headline(localDate: "2026-08-10", locale: Locale(identifier: "en_GB")))
        #expect(headline == "Monday 10 August")
    }

    /// An unknown zone falls back to UTC — visibly wrong by hours rather than silently local
    /// (`ServerClock.swift`, `docs/05` §6).
    ///
    /// Asserted as an **offset** rather than as an identifier: Foundation resolves `"UTC"` to a zone
    /// that calls itself `GMT`, and a test comparing the name would be about Foundation's spelling
    /// rather than about the fallback being zero-offset.
    @Test func anunknownZoneFallsBackToUTC() {
        #expect(GroupCalendar(timezone: "Mars/Olympus").timeZone.secondsFromGMT() == 0)
    }

    /// **Tomorrow is a wall-clock day, not 86,400 seconds** (`docs/08` §5).
    ///
    /// New York's spring forward is 2026-03-08. A round that opened at 10:00 on the 7th opens at
    /// 10:00 on the 8th — 23 hours later, not 24. Adding a day of seconds would put the voided
    /// screen's countdown an hour out for everybody in that group.
    @Test func tomorrowFollowsTheWallClockAcrossADSTBoundary() throws {
        let calendar = GroupCalendar(timezone: "America/New_York")
        let openedAt = try #require(calendar.instant(atNoonOn: "2026-03-07"))
        let tomorrow = calendar.nextDay(openedAt)

        #expect(tomorrow.timeIntervalSince(openedAt) == 23 * 3600, "an hour shorter, as the clock is")
        // And it is the same time of day, which is the thing that matters to a person.
        let components = calendar.calendar.dateComponents([.hour, .day], from: tomorrow)
        #expect(components.hour == 12)
        #expect(components.day == 8)
    }

    /// The ordinary case, for contrast: a day is a day.
    @Test func tomorrowIsADayLaterTheRestOfTheYear() throws {
        let calendar = GroupCalendar(timezone: "America/New_York")
        let openedAt = try #require(calendar.instant(atNoonOn: "2026-08-10"))
        #expect(calendar.nextDay(openedAt).timeIntervalSince(openedAt) == 24 * 3600)
    }

    /// The day is taken at **noon**, so a spring-forward midnight that does not exist cannot land
    /// the header on the wrong day.
    @Test func thedayIsAnchoredAtNoon() throws {
        let calendar = GroupCalendar(timezone: "America/New_York")
        let instant = try #require(calendar.instant(atNoonOn: "2026-03-08"))
        #expect(calendar.calendar.component(.hour, from: instant) == 12)
        #expect(calendar.localDate(of: instant) == "2026-03-08")
    }

    // MARK: - The countdown's threshold

    /// `docs/08` §2's nudge reads its threshold off the **displayed** countdown, so that the line
    /// appears the second the visible number crosses two hours.
    @Test func thecountdownReportsWhatItIsShowing() {
        #expect(CountdownDisplay.unknown.secondsRemaining == nil, "an unanchored clock knows nothing")
        #expect(CountdownDisplay.precise(hours: 2, minutes: 0, seconds: 1).secondsRemaining == 7_201)
        #expect(CountdownDisplay.precise(hours: 1, minutes: 59, seconds: 59).secondsRemaining == 7_199)
        #expect(CountdownDisplay.coarse(.hours(3)).secondsRemaining == 10_800)
        #expect(CountdownDisplay.coarse(.minutes(12)).secondsRemaining == 720)
        #expect(CountdownDisplay.coarse(.underAMinute).secondsRemaining == 0)
    }

    /// The threshold itself is the same two hours `docs/05` §3 enqueues the push at, so the
    /// in-interface nudge and the push are about the same moment.
    @Test func thenudgeThresholdIsTwoHours() {
        #expect(SubmitScreen.nudgeThreshold == 7_200)
        #expect(CountdownDisplay.precise(hours: 1, minutes: 59, seconds: 59).secondsRemaining
                .map { $0 < SubmitScreen.nudgeThreshold } == true)
        #expect(CountdownDisplay.precise(hours: 2, minutes: 0, seconds: 1).secondsRemaining
                .map { $0 < SubmitScreen.nudgeThreshold } == false)
    }
}
