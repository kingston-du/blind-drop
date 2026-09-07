import Foundation
import Observation
import Testing
@testable import BlindDrop

/// AC-2, client half: *"the client renders countdowns from `server_now` + a monotonic clock
/// offset, never from `Date()` alone, and never decides a phase transition"* (`CLAUDE.md` §2.2,
/// `docs/13` §5).
///
/// All six rules in `docs/13` §5 are testable, and this file tests all six. The last one is the
/// unusual one: it reads the app's own source and fails if `Date()` appears outside
/// `ServerClock.swift`. `ios/scripts/lint.sh` checks the same thing in CI, and the rule is worth
/// two guards — a lint script can be skipped by a developer in a hurry, and `docs/15` §7 wants
/// a passing test rather than a manual check.
@Suite struct ServerClockTests {

    /// A clock whose uptime this test drives by hand. The parameter is deliberately an
    /// *uptime* provider and not a `Date` provider: there is no seam in this type through
    /// which the device wall clock could be substituted, which is the property being asserted.
    @MainActor
    private final class Uptime {
        var value: TimeInterval = 1_000
        func advance(_ seconds: TimeInterval) { value += seconds }
    }

    @MainActor
    private func makeClock() -> (ServerClock, Uptime) {
        let uptime = Uptime()
        let clock = ServerClock(uptime: { MainActor.assumeIsolated { uptime.value } })
        return (clock, uptime)
    }

    private func instant(_ iso: String) throws -> Date {
        try Date(iso, strategy: .iso8601)
    }

    // MARK: - Rule 3 — before the first response, the app does not know

    @MainActor
    @Test func anUnanchoredClockKnowsNothingAndSaysSo() throws {
        let (clock, _) = makeClock()

        #expect(clock.now == nil)
        #expect(clock.isAnchored == false)
        #expect(clock.timeRemaining(until: try instant("2026-08-11T00:00:00Z")) == nil)
        // The countdown says `--:--:--`, which is what `.unknown` renders as. It does not say
        // 00:00:00, and it does not guess from the device.
        #expect(CountdownDisplay(remaining: nil, form: .precise) == .unknown)
    }

    // MARK: - Rules 1 and 2 — the device clock is not a source of truth

    /// A device clock five years out changes nothing, because nothing here reads it. The test
    /// states that structurally: the clock is anchored to a server instant and an uptime
    /// reading, and `now` is a pure function of those two.
    @MainActor
    @Test func onlyTheServerInstantAndTheUptimeReadingDecideTheTime() throws {
        let (clock, uptime) = makeClock()
        let serverNow = try instant("2026-08-10T18:42:07Z")
        clock.sync(serverNow: serverNow)

        #expect(clock.now == serverNow)

        uptime.advance(90)
        #expect(clock.now == serverNow.addingTimeInterval(90))

        // The device's own idea of the time — five years off in either direction — is not an
        // input to any of this. If it were, these equalities could not hold.
        let deviceIsFiveYearsFast = serverNow.addingTimeInterval(5 * 365 * 86_400)
        let deviceIsFiveYearsSlow = serverNow.addingTimeInterval(-5 * 365 * 86_400)
        #expect(clock.now != deviceIsFiveYearsFast)
        #expect(clock.now != deviceIsFiveYearsSlow)
    }

    /// The countdown a screen renders is a function of the anchor alone, so the same round at
    /// the same uptime produces the same digits on a phone set to 2031 as on one set correctly.
    @MainActor
    @Test func aWrongDeviceClockChangesNoCountdown() throws {
        let (clock, uptime) = makeClock()
        clock.sync(serverNow: try instant("2026-08-10T18:00:00Z"))
        let reveal = try instant("2026-08-11T00:00:00Z")

        uptime.advance(45 * 60)
        let remaining = try #require(clock.timeRemaining(until: reveal))
        #expect(remaining == 5 * 3600 + 15 * 60)
        #expect(CountdownDisplay(remaining: remaining, form: .precise)
            == .precise(hours: 5, minutes: 15, seconds: 0))
    }

    // MARK: - Rule 4 — re-anchoring means drift never accumulates

    /// Two hours of a session, ticked a second at a time, and the clock is still exact. There
    /// is no accumulation to drift: `now` is computed from the anchor each time rather than
    /// incremented.
    @MainActor
    @Test func driftOverATwoHourSessionIsNotJustSmallButAbsent() throws {
        let (clock, uptime) = makeClock()
        let start = try instant("2026-08-10T18:00:00Z")
        clock.sync(serverNow: start)

        for _ in 0..<7_200 { uptime.advance(1) }

        let elapsed = try #require(clock.now).timeIntervalSince(start)
        #expect(abs(elapsed - 7_200) < 1, "docs/13 §5: under a second over two hours")
        #expect(elapsed == 7_200, "and in fact exactly zero, because nothing is accumulated")
    }

    /// Every response re-anchors, and a re-anchor overrides whatever the previous one implied —
    /// which is how a phone that spent ten minutes wrong is right again on the next request.
    @MainActor
    @Test func everyResponseReanchors() throws {
        let (clock, uptime) = makeClock()
        clock.sync(serverNow: try instant("2026-08-10T18:00:00Z"))
        uptime.advance(600)

        let corrected = try instant("2026-08-10T18:03:00Z")
        clock.sync(serverNow: corrected)
        #expect(clock.now == corrected)
    }

    // MARK: - Rule 5 — a stale anchor is no anchor

    /// `systemUptime` does not advance while the device is asleep, so after any background
    /// period the anchor is a lie of exactly the length of the nap. `RootView` invalidates on
    /// `willEnterForeground`; until the refetch lands, every countdown reads `--:--:--`.
    @MainActor
    @Test func aBackgroundedAnchorIsThrownAwayRatherThanTrusted() throws {
        let (clock, uptime) = makeClock()
        clock.sync(serverNow: try instant("2026-08-10T18:00:00Z"))
        uptime.advance(30)
        #expect(clock.now != nil)

        clock.invalidate()

        #expect(clock.now == nil, "a stale anchor returns nil, not a stale time")
        #expect(clock.isAnchored == false)
        #expect(clock.timeRemaining(until: try instant("2026-08-11T00:00:00Z")) == nil)

        // And it comes back only when a response says what time it is.
        let fresh = try instant("2026-08-10T21:14:00Z")
        clock.sync(serverNow: fresh)
        #expect(clock.now == fresh)
    }

    // MARK: - Rule 6 — the group's timezone, never the device's

    /// A member on a plane still plays on the group's clock. The formatted day and hour depend
    /// on the group's zone and on nothing about the device.
    @MainActor
    @Test func everythingIsFormattedOnTheGroupsClock() throws {
        // 2026-08-11T00:00:00Z is 20:00 on 2026-08-10 in New York: the reveal, on the round's
        // own local date, which is exactly the pairing `local_date` encodes.
        let reveal = try instant("2026-08-11T00:00:00Z")
        let cove = GroupCalendar(timezone: "America/New_York")

        #expect(cove.localDate(of: reveal) == "2026-08-10")
        #expect(cove.timeOfDay(of: reveal).contains("8") || cove.timeOfDay(of: reveal).contains("20"))

        // The same instant, in the group's zone, is the same string whatever the traveller's
        // own zone is — because the traveller's zone is not consulted.
        let tokyo = GroupCalendar(timezone: "Asia/Tokyo")
        #expect(tokyo.localDate(of: reveal) == "2026-08-11")
        #expect(cove.localDate(of: reveal) != tokyo.localDate(of: reveal))
        #expect(cove.isSameDay(reveal, reveal.addingTimeInterval(-3600)))

        // An identifier nobody recognises falls back to UTC — visibly wrong, rather than
        // silently local. A silent `TimeZone.current` is the bug this rule exists to prevent.
        // Asserted by offset rather than by name: Foundation normalises "UTC" to "GMT", and
        // what matters is that the fallback is zero-offset and not the device's.
        let unknown = GroupCalendar(timezone: "Middle/Earth").timeZone
        #expect(unknown.secondsFromGMT() == 0)
    }

    // MARK: - Rule 1, structurally — Date() appears nowhere else

    /// The lint rule, as a test. `ios/scripts/lint.sh` enforces it in CI; this asserts it from
    /// inside the suite that owns the rule, so a developer who has not run the shell script
    /// still finds out.
    @Test func dateIsNeverConstructedOutsideServerClock() throws {
        let app = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Unit
            .deletingLastPathComponent()   // BlindDropTests
            .appending(path: "BlindDrop")

        var offenders: [String] = []
        let files = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift", url.lastPathComponent != "ServerClock.swift" else {
                continue
            }
            for (number, line) in try String(contentsOf: url, encoding: .utf8)
                .components(separatedBy: .newlines).enumerated() {
                // Comments may discuss the rule without tripping it, the same exemption the
                // shell lint makes.
                let code = line.components(separatedBy: "//").first ?? line
                if code.contains("Date()") {
                    offenders.append("\(url.lastPathComponent):\(number + 1)")
                }
            }
        }
        #expect(offenders.isEmpty, "docs/13 §5 rule 1: \(offenders.joined(separator: ", "))")
    }

    // MARK: - The two countdown forms

    /// `docs/12` §1: the coarse form rounds down and never shows a unit smaller than a minute.
    @Test func theCoarseFormRoundsDownAndStopsAtAMinute() {
        func coarse(_ seconds: TimeInterval) -> CountdownDisplay {
            CountdownDisplay(remaining: seconds, form: .coarse)
        }
        #expect(coarse(3 * 3600 + 50 * 60) == .coarse(.hours(3)), "rounded down; 4 then 3 reads broken")
        #expect(coarse(3600) == .coarse(.hours(1)))
        #expect(coarse(3599) == .coarse(.minutes(59)))
        #expect(coarse(12 * 60 + 30) == .coarse(.minutes(12)))
        #expect(coarse(59) == .coarse(.underAMinute))
        #expect(coarse(0) == .coarse(.underAMinute))
    }

    /// A countdown does not go negative, and reaching zero is not a phase change — the screen
    /// refetches and the server says what happens next (`CLAUDE.md` §2.2).
    @MainActor
    @Test func zeroIsARefetchAndNotATransition() throws {
        let (clock, uptime) = makeClock()
        clock.sync(serverNow: try instant("2026-08-10T23:59:30Z"))
        let reveal = try instant("2026-08-11T00:00:00Z")

        let timer = CountdownTimer(clock: clock)
        timer.start(until: reveal, form: .precise)
        #expect(timer.display == .precise(hours: 0, minutes: 0, seconds: 30))
        #expect(timer.hasElapsed == false)

        uptime.advance(45)
        timer.refresh()
        #expect(timer.display == .elapsed, "it stops at zero rather than counting backwards")
        #expect(timer.hasElapsed == true)
        timer.stop()
    }

    /// A timer on an unanchored clock renders `--:--:--`, whatever deadline it was given.
    @MainActor
    @Test func aTimerWithoutAnAnchorShowsNothing() throws {
        let (clock, _) = makeClock()
        let timer = CountdownTimer(clock: clock)
        timer.start(until: try instant("2026-08-11T00:00:00Z"), form: .precise)

        #expect(timer.display == .unknown)
        #expect(timer.hasElapsed == nil, "not false — unknown")
        timer.stop()
    }

    /// `docs/13` §5a: a countdown that already has a value for its current deadline holds that
    /// value through a loading gap — a background/foreground cycle invalidating the clock —
    /// rather than blanking to `--:--:--`, and jumps to the true value the moment the clock
    /// re-anchors. This is the behaviour `--:--:--sometimes` complaints traced back to before
    /// §5a: the countdown does not need to lie to avoid looking broken, it needs to remember.
    @MainActor
    @Test func aRunningTimerHoldsItsLastValueThroughALoadingGapThenJumps() throws {
        let (clock, uptime) = makeClock()
        clock.sync(serverNow: try instant("2026-08-10T18:00:00Z"))
        let deadline = try instant("2026-08-10T18:01:00Z")

        let timer = CountdownTimer(clock: clock)
        timer.start(until: deadline, form: .precise)
        #expect(timer.display == .precise(hours: 0, minutes: 1, seconds: 0))

        // The device sleeps for a while, `RootView` invalidates on `willEnterForeground`, and a
        // refetch is in flight — the exact gap this rule covers.
        uptime.advance(20)
        clock.invalidate()
        timer.refresh()

        #expect(
            timer.display == .precise(hours: 0, minutes: 1, seconds: 0),
            "held at the last known value, not reset to --:--:--"
        )
        #expect(timer.hasElapsed == nil, "the clock itself is honestly unsure during the gap")

        // The refetch response re-anchors the clock. The very next tick's refresh() is the
        // "jump" — there is no separate step that writes the corrected value.
        clock.sync(serverNow: try instant("2026-08-10T18:00:20Z"))
        timer.refresh()
        #expect(timer.display == .precise(hours: 0, minutes: 0, seconds: 40))
        timer.stop()
    }

    /// The hold in the test above is scoped to *the same deadline*. A phase transition — `open`
    /// moving to `revealed`, the same `CountdownTimer` re-pointed at a new deadline — must not
    /// carry the old phase's number onto the new screen even if the clock happens to be
    /// unanchored at that exact instant.
    @MainActor
    @Test func aNewDeadlineClearsTheHeldValueEvenWhenUnanchored() throws {
        let (clock, uptime) = makeClock()
        clock.sync(serverNow: try instant("2026-08-10T18:00:00Z"))
        let timer = CountdownTimer(clock: clock)
        timer.start(until: try instant("2026-08-10T18:00:03Z"), form: .precise)
        #expect(timer.display == .precise(hours: 0, minutes: 0, seconds: 3))

        uptime.advance(3)
        clock.invalidate()

        // Re-pointed at a *different* deadline — e.g. the round just revealed — while the clock
        // is still unanchored from the same background cycle.
        timer.start(until: try instant("2026-08-11T00:00:00Z"), form: .precise)
        #expect(
            timer.display == .unknown,
            "the old phase's 0:00:03 is not a cached value for this new countdown"
        )
        timer.stop()
    }

    /// The other half of the reference count: re-pointing an already-observed timer must **not**
    /// take a second hold.
    ///
    /// `CountdownView` re-points on two changes it sees without appearing or disappearing — the
    /// round moving to a phase that counts to a different instant, and a Dynamic Type size that
    /// changes the tick cadence. Both used to call `start(until:form:)`, which increments, while
    /// only `onDisappear` decrements. One deadline change was enough to put the count permanently
    /// above zero, so `stop()` never cancelled the ticker and it ran on at 1Hz for the rest of the
    /// process — writing `hasElapsed` behind a screen nobody was looking at, which `RoundScreen`
    /// reads to decide whether to refetch.
    ///
    /// A stopped ticker is asserted the only way it is observable from out here: advance the
    /// clock past the point where a running one would have redrawn, and require the digits not to
    /// have moved.
    @MainActor
    @Test func repointingDoesNotTakeASecondHold() async throws {
        let (clock, uptime) = makeClock()
        clock.sync(serverNow: try instant("2026-08-10T18:00:00Z"))
        let timer = CountdownTimer(clock: clock)

        // One view appears, and is later re-pointed twice — the dark hours giving way to the
        // blind window, then the round revealing — without ever leaving the screen. Precise
        // throughout, so a ticker still alive at the end would visibly move within a second.
        timer.start(until: try instant("2026-08-10T18:00:30Z"), form: .precise)
        timer.repoint(until: try instant("2026-08-11T00:00:00Z"), form: .precise)
        timer.repoint(until: try instant("2026-08-11T02:00:00Z"), form: .precise)
        #expect(timer.display == .precise(hours: 8, minutes: 0, seconds: 0))

        // That one view goes away. It took one hold, so this releases the last one.
        timer.stop()

        uptime.advance(5)
        try await Task.sleep(for: .seconds(1.3))
        #expect(
            timer.display == .precise(hours: 8, minutes: 0, seconds: 0),
            "the ticker must be cancelled once the only view watching it has gone"
        )
    }

    /// `RoundScreen` hands one `CountdownTimer` to every phase screen, and two `CountdownView`s
    /// can be mounted on it for a single frame — the header badge disappearing the instant a
    /// submission is sealed, as the sealed card's own countdown appears in the same render.
    /// Before this was reference-counted, whichever of the two called `stop()` last cancelled
    /// the ticker outright, and if that happened to be the one leaving rather than the one
    /// arriving, the countdown froze until a background/foreground cycle forced a refetch. This
    /// is that race, forced deterministically: two `start()`s, one `stop()`, and the ticker must
    /// still be running for the observer that did not leave.
    @MainActor
    @Test func oneObserverLeavingDoesNotStopATimerAnotherStillWants() async throws {
        let (clock, uptime) = makeClock()
        clock.sync(serverNow: try instant("2026-08-10T18:00:00Z"))
        let reveal = try instant("2026-08-11T00:00:00Z")

        let timer = CountdownTimer(clock: clock)
        // The badge and the sealed card, both pointing at the same timer at once.
        timer.start(until: reveal, form: .precise)
        timer.start(until: reveal, form: .precise)
        #expect(timer.display == .precise(hours: 6, minutes: 0, seconds: 0))

        // The badge disappears — one of the two observers leaves.
        timer.stop()

        // The uptime the ticker's next tick will read already reflects a second having passed;
        // the real sleep just gives that tick room to actually fire.
        uptime.advance(1)
        try await Task.sleep(for: .seconds(1.3))
        #expect(timer.display == .precise(hours: 5, minutes: 59, seconds: 59),
                "the sealed card's countdown must still be ticking after the badge alone left")

        // The second, and last, observer leaves — only now does it really stop.
        timer.stop()
    }

    // MARK: - E26-04 — sitting on screen through a deadline must turn the page, not just leaving

    /// Reproduces the reported bug at the level Observation actually operates: staying on screen
    /// through a phase deadline did not turn the page; leaving and returning did. `RoundScreen`
    /// detects the deadline with `.onChange(of: timer.hasElapsed)`, and SwiftUI's Observation only
    /// re-evaluates a reader when a property it *touched* is later *written*. Every test above
    /// calls `timer.hasElapsed` directly and would pass whether that property is computed or
    /// stored, because a direct call always re-evaluates it — that is precisely why the old,
    /// computed `hasElapsed` slipped past every one of them while still never waking a real
    /// observer. `withObservationTracking` is the one seam that tells the two apart without a
    /// SwiftUI view in the loop: it records what a read actually depended on, and reports whether
    /// a later write touched any of it.
    ///
    /// Before the fix, `hasElapsed` was computed from `deadline` and the clock's anchor — neither
    /// of which the ordinary tick's `refresh()` call ever wrote, only `display` did — so a reader
    /// that had only ever asked about `hasElapsed` was never told a tick happened at all, only
    /// that a *new* deadline (`start()`) or a fresh `sync()` had landed. Sitting on screen through
    /// a deadline produces neither: the round does not change and the app makes no incidental
    /// request. This test drives exactly that: one `start()`, then nothing but the passage of
    /// time and the ticker's own `refresh()` — the same two calls a foregrounded, idle screen
    /// sees between phase transitions.
    @MainActor
    @Test func hasElapsedNotifiesAnObserverOnTheOrdinaryTickAlone() throws {
        let (clock, uptime) = makeClock()
        clock.sync(serverNow: try instant("2026-08-10T23:59:59Z"))
        let deadline = try instant("2026-08-11T00:00:00Z")

        let timer = CountdownTimer(clock: clock)
        timer.start(until: deadline, form: .precise)
        #expect(timer.hasElapsed == false)

        // `withObservationTracking`'s `onChange` is `@Sendable`, so a plain captured `var` is
        // rejected under strict concurrency even though the mutation below happens synchronously,
        // inside `refresh()`'s write, on the `@MainActor` this whole test is isolated to. Unlike
        // `ArtworkView.cache`'s narrowly-scoped `nonisolated(unsafe)` on one field — the tighter
        // escape, preferred when there is a single field to mark — this box exists only to give
        // the closure something to capture at all, so the class-wide `@unchecked Sendable` here
        // is the right-sized tool for a single-purpose test type, not a looser stand-in for it.
        let notified = ObservationFlag()
        withObservationTracking {
            _ = timer.hasElapsed
        } onChange: {
            notified.value = true
        }

        // No new deadline, no `sync()` — only the uptime advancing and the ordinary tick's own
        // `refresh()`, which is what `CountdownTimer.start()`'s `Task` calls every second on a
        // screen nobody touched.
        uptime.advance(1)
        timer.refresh()

        #expect(
            notified.value,
            "a reader watching hasElapsed alone must be woken by the ordinary tick, not only by a new deadline or a fresh sync() — this is the E26-04 regression: RoundScreen's onChange(of: timer.hasElapsed) never fired while the app just sat on screen"
        )
        #expect(timer.hasElapsed == true)
        timer.stop()
    }

    /// The coarse form's tick is deliberately once a minute (`docs/12` §1) — that lag already has
    /// a name and is accepted. This asserts the fix does not *add* to it: a coarse-form observer
    /// is still woken by that same once-a-minute tick, not left waiting on some other event that
    /// might not come at all (which was the actual bug, not merely a slow one).
    @MainActor
    @Test func hasElapsedNotifiesACoarseObserverOnItsOwnMinuteTick() throws {
        let (clock, uptime) = makeClock()
        clock.sync(serverNow: try instant("2026-08-10T23:00:00Z"))
        let deadline = try instant("2026-08-11T00:00:00Z")

        let timer = CountdownTimer(clock: clock)
        timer.start(until: deadline, form: .coarse)
        #expect(timer.hasElapsed == false)

        let notified = ObservationFlag()
        withObservationTracking {
            _ = timer.hasElapsed
        } onChange: {
            notified.value = true
        }

        uptime.advance(3600)
        timer.refresh()

        #expect(notified.value, "the coarse tick must still wake an hasElapsed observer on its own cadence")
        #expect(timer.hasElapsed == true)
        timer.stop()
    }
}

/// A one-field `@unchecked Sendable` box, for the `onChange` closures above that must set a flag
/// from `withObservationTracking`'s `@Sendable` callback. The mutation happens synchronously, on
/// the same `@MainActor` call stack as the write that triggered it, but the closure's own type
/// cannot say so. `ArtworkView.cache` marks its one field `nonisolated(unsafe)` instead, because
/// it has an existing type to attach the escape to; this box exists purely to give a `@Sendable`
/// closure something safe to capture, so marking the type itself is the right-sized version of
/// the same escape rather than a looser one.
private final class ObservationFlag: @unchecked Sendable {
    var value = false
}
