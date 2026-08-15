import Foundation
import Testing
@testable import BlindDrop

/// The how-to page's one piece of logic: its clock times are the **group's** real schedule, not
/// the copy deck's placeholder hours (`docs/11` §How to play).
///
/// `HowToSheet` itself draws nothing this suite can assert without a host window — its three
/// derived times are one-line wrappers around `RevealHour`, already proven digit-for-digit by
/// `RevealHourTests`. What is actually at risk here is the **wiring**: that `RoundContext`
/// exposes the third time (`scoresTime`) the sheet needs, and that a group whose songs seal at
/// an hour other than the 20:00 default reads its own hours rather than everybody else's.
@MainActor
@Suite struct HowToTests {

    /// A group is `Decodable` with no custom `init`, so a test can build one directly rather than
    /// reach for a fixture file it does not need — `RoundDTO`'s init is the one that is private,
    /// for the reason `RoundFixture` gives, and this suite touches only the group.
    private func group(revealHour: Int) -> GroupDTO {
        GroupDTO(
            id: "g1", name: "Test", timezone: "UTC", revealHour: revealHour,
            inviteCode: "ABC123", isAdmin: false, members: []
        )
    }

    /// `docs/02` §1: songs open ten hours before the reveal, answers land two after. The default
    /// group (`RevealHour.default`, 20:00) reads *10:00 AM · 8:00 PM · 10:00 PM* — the exact hours
    /// `docs/11`'s three step times were written against.
    @Test func theDefaultGroupReadsTheCopyDecksHours() throws {
        let context = RoundContext(round: try RoundFixture.round("round_open"), group: group(revealHour: 20))
        let english = Locale(identifier: "en_US")
        #expect(spaceNormalised(RevealHour.formatted(
            RevealHour.opensHour(revealHour: context.group.revealHour), locale: english
        )) == "10:00 AM")
        #expect(spaceNormalised(RevealHour.formatted(context.group.revealHour, locale: english)) == "8:00 PM")
        #expect(spaceNormalised(RevealHour.formatted(
            RevealHour.scoresHour(revealHour: context.group.revealHour), locale: english
        )) == "10:00 PM")
    }

    /// A group with a different `reveal_hour` gets its **own** three times — the whole reason the
    /// how-to page reads `RoundContext` instead of writing "10 AM" down as a string. Picked at
    /// 18:00 so every one of the three hours differs from the default's.
    @Test func agroupWithADifferentRevealHourReadsItsOwnSchedule() throws {
        let context = RoundContext(round: try RoundFixture.round("round_open"), group: group(revealHour: 18))
        let english = Locale(identifier: "en_US")
        #expect(spaceNormalised(RevealHour.formatted(
            RevealHour.opensHour(revealHour: context.group.revealHour), locale: english
        )) == "8:00 AM")
        #expect(spaceNormalised(RevealHour.formatted(context.group.revealHour, locale: english)) == "6:00 PM")
        #expect(spaceNormalised(RevealHour.formatted(
            RevealHour.scoresHour(revealHour: context.group.revealHour), locale: english
        )) == "8:00 PM")
    }

    /// `RoundContext.scoresTime` exists for exactly one caller today — the how-to page's fourth
    /// step — and nothing else on a live phase screen names the hour scores land at on its own
    /// (`deadline(now:)` already counts down to it). The property still has to agree with the
    /// same `RevealHour` arithmetic every other time on the context uses.
    @Test func scoresTimeIsTwoHoursAfterTheReveal() throws {
        let context = RoundContext(round: try RoundFixture.round("round_open"), group: group(revealHour: 20))
        #expect(context.scoresTime == RevealHour.formatted(
            RevealHour.scoresHour(revealHour: context.group.revealHour)
        ))
        #expect(!context.scoresTime.isEmpty)
    }

    /// `RevealHour.default` is the hour `HowToSheet` falls back to when it has no `RoundContext`
    /// at all — `SignInScreen`, reached before there is a group. `docs/04` §3 pins the default at
    /// 20; this is the regression that would silently change what sign-in's `[?]` says.
    @Test func theDefaultRevealHourIsWhatSignInFallsBackTo() {
        #expect(RevealHour.default == 20)
        #expect(HowToSheet(close: {}).revealHour == RevealHour.default)
    }

    private func spaceNormalised(_ value: String) -> String {
        value.replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}
