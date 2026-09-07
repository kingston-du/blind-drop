import Foundation
import Testing
@testable import BlindDrop

/// What `RoundScreen` draws around a phase, and what the phase draws for itself.
///
/// Sibling of `RoundInsetTests`, and it exists for the same reason that one does: these are all
/// facts about the **container**, and every golden in the suite renders a screen's
/// `snapshotContent` — its content *without* its container. So a date drawn twice, a date drawn
/// nowhere, or a cue that vanished when its phase changed hands is precisely the class of mistake
/// no picture in this repository can show. `bleedsToScreenEdge` had that cover from the day it
/// existed; `scrollsItsOwnDate` and `drawsItsOwnCue` are the same shape of flag and were added
/// without it (reviewer, 2026-09-06).
///
/// Both directions are asserted, and both are load-bearing. A phase whose flag says *the screen
/// draws this* while the screen's source never mentions the component ships a screen missing a
/// line; a phase whose flag says *the container draws this* while the screen draws it too ships
/// the same sentence twice.
/// One phase, the screens it puts up, and what those screens are expected to draw themselves.
struct PhaseChrome: Sendable, CustomStringConvertible {
    /// The fixture round that decodes to this phase — the payload the app actually parses, rather
    /// than a `RoundDTO.Phase` built by hand, which `docs/13` §2's private initialiser forbids.
    let fixture: String
    /// Whether the date is the screen's own eyebrow rather than `RoundHeader`'s pinned row.
    let scrollsItsOwnDate: Bool
    /// Whether the cue is drawn inside the screen rather than as `RoundScreen`'s `CueBanner`.
    let drawsItsOwnCue: Bool
    /// The screen files that phase puts on the display.
    let files: [String]

    var description: String { fixture }
}

/// File scope rather than a member: `@Test(arguments:)` evaluates its arguments outside whatever
/// actor the suite is isolated to — the same reason `phaseScreens` sits outside `RoundInsetTests`.
let phaseChrome = [
    // The drop screen: its own `CueCard` between the subhead and the field, and no eyebrow —
    // it does not scroll, so its date stays in the pinned row beside the "seals in" badge.
    PhaseChrome(fixture: "round_open_nosub", scrollsItsOwnDate: false, drawsItsOwnCue: true,
                files: ["Submit/SubmitScreen.swift"]),
    PhaseChrome(fixture: "round_open", scrollsItsOwnDate: false, drawsItsOwnCue: false,
                files: ["Submit/SealedScreen.swift"]),
    PhaseChrome(fixture: "round_voided", scrollsItsOwnDate: false, drawsItsOwnCue: false,
                files: ["Submit/VoidedScreen.swift"]),
    PhaseChrome(fixture: "round_revealed", scrollsItsOwnDate: true, drawsItsOwnCue: true,
                files: ["Reveal/RevealScreen.swift", "Reveal/GuessSheet.swift"]),
    PhaseChrome(fixture: "round_scored", scrollsItsOwnDate: true, drawsItsOwnCue: true,
                files: ["Results/ResultsScreen.swift"]),
]

@MainActor
@Suite struct RoundChromeTests {

    /// The flag against the fixture that decodes to it. The half that fails when somebody adds a
    /// phase, or flips one of the pair without the other.
    @Test(arguments: phaseChrome)
    func theFlagsMatchTheirPhase(_ chrome: PhaseChrome) throws {
        // Read into `Bool`s first: `#expect` prints the whole expression on failure, and a
        // `RoundDTO.Phase` prints eight decoded cards and a name pool with it.
        let phase = try RoundFixture.round(chrome.fixture).phase
        let scrolls = phase.scrollsItsOwnDate
        let ownCue = phase.drawsItsOwnCue

        #expect(scrolls == chrome.scrollsItsOwnDate,
                "\(chrome.fixture): scrollsItsOwnDate is \(scrolls), the table says \(chrome.scrollsItsOwnDate)")
        #expect(ownCue == chrome.drawsItsOwnCue,
                "\(chrome.fixture): drawsItsOwnCue is \(ownCue), the table says \(chrome.drawsItsOwnCue)")
    }

    /// A screen draws the date **iff** its phase says it does.
    @Test(arguments: phaseChrome)
    func aScreenDrawsTheDateExactlyWhenItsPhaseSaysSo(_ chrome: PhaseChrome) throws {
        let draws = try chrome.files.contains { try source($0).contains("RoundDateline(") }

        #expect(draws == chrome.scrollsItsOwnDate,
                """
                \(chrome.fixture): the screen \(draws ? "draws" : "does not draw") RoundDateline, \
                but RoundScreen \(chrome.scrollsItsOwnDate ? "withholds" : "pins") the date row. \
                One of the two is wrong, and the result is the night stated twice or not at all.
                """)
    }

    /// A screen draws the cue **iff** its phase says it does.
    ///
    /// Either component counts. Which of the two a phase uses is that phase's own argument —
    /// `CueBanner` inside the reveal's header, `CueCard` on the drop screen and the answers — and
    /// what this asserts is only that exactly one place draws it.
    @Test(arguments: phaseChrome)
    func aScreenDrawsTheCueExactlyWhenItsPhaseSaysSo(_ chrome: PhaseChrome) throws {
        let draws = try chrome.files.contains { file in
            let text = try source(file)
            return text.contains("CueBanner(") || text.contains("CueCard(")
        }

        #expect(draws == chrome.drawsItsOwnCue,
                """
                \(chrome.fixture): the screen \(draws ? "draws" : "does not draw") the cue itself, \
                but RoundScreen \(chrome.drawsItsOwnCue ? "withholds" : "draws") its banner. One \
                of the two is wrong, and the result is the cue said twice or not at all.
                """)
    }

    private func source(_ path: String) throws -> String {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Unit
            .deletingLastPathComponent()   // BlindDropTests
            .deletingLastPathComponent()   // ios
            .appending(path: "BlindDrop/Features/\(path)")
        return try String(contentsOf: file, encoding: .utf8)
    }
}
