import Foundation
import Testing
@testable import BlindDrop

/// The screen inset is applied **exactly once** on any path from `RoundScreen` to a pixel.
///
/// This exists because the rule broke and nothing noticed. `RevealScreen` applies
/// `Layout.screenInset` inside its own scroll view — it has to, because the guess sheet is
/// pinned across the full width beneath it — and `RoundScreen` also applied it to the column
/// every phase sits in, so the reveal shipped indented forty points instead of twenty.
///
/// **No golden in the repository could have caught it.** Every snapshot renders a screen's
/// `snapshotContent` — its content without its container — precisely so the renderer can supply
/// the inset itself, which means the container's inset is the one thing the pictures never
/// see. So the invariant is asserted here instead, against the screens' own source: a file that
/// writes `Layout.screenInset` is a screen that insets itself, and a screen that insets itself
/// must be one `RoundScreen` leaves alone.
/// One phase, the screens it puts up, and whether they own the inset.
struct PhaseScreens: Sendable, CustomStringConvertible {
    let phase: String
    let bleeds: Bool
    let files: [String]

    var description: String { phase }
}

/// Which screens each phase puts on the display. `GuessSheet` is listed with the reveal because
/// it is part of that screen's body, and it is the file with the strongest claim to the full
/// width. File scope rather than a member: `@Test(arguments:)` evaluates its arguments outside
/// whatever actor the suite is isolated to.
let phaseScreens = [
    PhaseScreens(phase: "open (nothing dropped)", bleeds: false, files: ["Submit/SubmitScreen.swift"]),
    PhaseScreens(phase: "open (sealed)", bleeds: false, files: ["Submit/SealedScreen.swift"]),
    PhaseScreens(phase: "voided", bleeds: false, files: ["Submit/VoidedScreen.swift"]),
    PhaseScreens(phase: "revealed", bleeds: true,
                 files: ["Reveal/RevealScreen.swift", "Reveal/GuessSheet.swift"]),
    PhaseScreens(phase: "scored", bleeds: true, files: ["Results/ResultsScreen.swift"]),
]

@MainActor
@Suite struct RoundInsetTests {

    /// A screen insets itself **iff** its phase bleeds to the screen's edge.
    ///
    /// Both directions matter. A screen that insets itself while `RoundScreen` also insets it is
    /// the forty-point bug; a screen that does neither sits flush against the edge, which on a
    /// card with a border is just as visible and just as quiet.
    @Test(arguments: phaseScreens)
    func aScreenInsetsItselfExactlyWhenItsPhaseBleeds(_ screen: PhaseScreens) throws {
        let insetsItself = try screen.files.contains { try source($0).contains("Layout.screenInset") }

        #expect(insetsItself == screen.bleeds,
                """
                \(screen.phase): the screen \(insetsItself ? "applies" : "does not apply") \
                Layout.screenInset itself, but RoundScreen \
                \(screen.bleeds ? "leaves it alone" : "insets it"). One of the two is wrong, and \
                the result is either a double indent or a screen flush against the edge.
                """)
    }

    /// The flag the screen switch actually reads, against the same table. This is the half that
    /// would fail if somebody added a phase and forgot it, rather than if they changed a padding.
    @Test func thePhaseFlagMatchesTheScreensItSelects() throws {
        // Read into a `Bool` first: `#expect` prints the whole expression on failure, and a
        // `RoundDTO.Phase` prints eight decoded cards and a name pool with it.
        for name in ["round_revealed", "round_scored"] {
            let bleeds = try RoundFixture.round(name).phase.bleedsToScreenEdge
            #expect(bleeds, "\(name) puts up a screen that insets itself")
        }
        for name in ["round_open", "round_open_nosub", "round_voided"] {
            let bleeds = try RoundFixture.round(name).phase.bleedsToScreenEdge
            #expect(!bleeds, "\(name) puts up a screen RoundScreen has to inset")
        }
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
