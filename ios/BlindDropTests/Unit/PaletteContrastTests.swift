import Foundation
import SwiftUI
import Testing
@testable import BlindDrop

/// `docs/07` §2: *"`PaletteContrastTests` asserts every row. If you change a hex, the test
/// tells you what broke."* This file is that sentence.
///
/// The ratios are **computed** from `Palette.Hex` with the WCAG 2.1 formula, never copied out
/// of the doc's table. A test that stored the ratios would only prove the ratios had not been
/// edited; computing them means a one-character change to a hex moves the number, blows the
/// tolerance, and names the row that broke.
@Suite struct PaletteContrastTests {

    // MARK: - WCAG 2.1, from first principles

    /// sRGB → linear, per <https://www.w3.org/TR/WCAG21/#dfn-relative-luminance>.
    ///
    /// The `0.03928` breakpoint is the one WCAG 2.1 publishes. The mathematically exact knee is
    /// 0.04045; the difference is smaller than one 8-bit step, and matching the published
    /// constant is what makes these numbers comparable with every other tool that quotes a
    /// ratio — including whatever produced the table in `docs/07` §2.
    private func linearised(_ channel8: UInt32) -> Double {
        let c = Double(channel8) / 255.0
        return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// Relative luminance of a `0xRRGGBB` literal. The coefficients are the sRGB luminance
    /// weights; green dominates because human vision does.
    private func relativeLuminance(_ hex: UInt32) -> Double {
        0.2126 * linearised((hex >> 16) & 0xFF)
            + 0.7152 * linearised((hex >> 8) & 0xFF)
            + 0.0722 * linearised(hex & 0xFF)
    }

    /// Contrast ratio, per <https://www.w3.org/TR/WCAG21/#dfn-contrast-ratio>.
    ///
    /// Deliberately order-independent — it takes the lighter and darker itself rather than
    /// trusting the caller to pass foreground first. A ratio that depended on argument order
    /// would let a transposed row pass while meaning nothing.
    private func contrastRatio(_ a: UInt32, _ b: UInt32) -> Double {
        let la = relativeLuminance(a), lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// The helper has to be right before it can police anything, so it is pinned to the three
    /// values WCAG fixes by definition, plus the symmetry property the rows rely on.
    @Test func theLuminanceFormulaMatchesItsDefinition() {
        #expect(relativeLuminance(0xFFFFFF) == 1.0)
        #expect(relativeLuminance(0x000000) == 0.0)
        // Black on white is the maximum possible ratio: (1 + 0.05) / (0 + 0.05).
        #expect(abs(contrastRatio(0x000000, 0xFFFFFF) - 21.0) < 0.000_001)
        #expect(contrastRatio(Palette.Hex.ink, Palette.Hex.paper)
            == contrastRatio(Palette.Hex.paper, Palette.Hex.ink))
    }

    // MARK: - The ten rows of docs/07 §2

    /// One row of the `docs/07` §2 contrast table.
    struct Row: Sendable, CustomStringConvertible {
        /// The pair, spelled as the doc spells it, so a failure names the row you can go read.
        let pair: String
        let foreground: UInt32
        let background: UInt32
        /// The ratio `docs/07` §2 prints. Drift from the computed value means someone edited a
        /// hex without editing the doc — or the doc without the hex.
        let documented: Double
        /// The WCAG minimum this pair has to clear. `nil` for the one row whose requirement
        /// column is `—`; see `amberIsBelowEveryThresholdOnPurpose`.
        let minimum: Double?

        var description: String { pair }
    }

    /// Verbatim from the `docs/07` §2 table, in its order. Ten rows, and that is the list — the
    /// six tokens with no row (`paperSunk`, `edge`, `edgeStrong`, `amberWash`,
    /// `ultramarineDeep`, `ultramarineWash`) are washes and borders that carry no text, and
    /// inventing thresholds for them would be inventing spec.
    static let rows: [Row] = [
        Row(pair: "ink on paper",
            foreground: Palette.Hex.ink, background: Palette.Hex.paper,
            documented: 16.5, minimum: 4.5),
        Row(pair: "inkDim on paper",
            foreground: Palette.Hex.inkDim, background: Palette.Hex.paper,
            documented: 5.70, minimum: 4.5),
        // 3.0, not 4.5: large text (≥ 24pt) and UI only. Never body text.
        Row(pair: "inkFaint on paper",
            foreground: Palette.Hex.inkFaint, background: Palette.Hex.paper,
            documented: 3.49, minimum: 3.0),
        Row(pair: "amberText on paper",
            foreground: Palette.Hex.amberText, background: Palette.Hex.paper,
            documented: 5.55, minimum: 4.5),
        Row(pair: "ink on amber fill",
            foreground: Palette.Hex.ink, background: Palette.Hex.amber,
            documented: 6.73, minimum: 4.5),
        // 3.0: non-text graphics — marks, borders, icons, the seal stamp.
        Row(pair: "amberDeep on surface",
            foreground: Palette.Hex.amberDeep, background: Palette.Hex.surface,
            documented: 3.99, minimum: 3.0),
        // No minimum. Fill only, never text, never a lone mark.
        Row(pair: "amber on surface",
            foreground: Palette.Hex.amber, background: Palette.Hex.surface,
            documented: 2.68, minimum: nil),
        Row(pair: "ultramarine on paper",
            foreground: Palette.Hex.ultramarine, background: Palette.Hex.paper,
            documented: 6.61, minimum: 4.5),
        Row(pair: "white on ultramarine fill",
            foreground: Palette.Hex.surface, background: Palette.Hex.ultramarine,
            documented: 7.26, minimum: 4.5),
        Row(pair: "alert on paper",
            foreground: Palette.Hex.alert, background: Palette.Hex.paper,
            documented: 5.95, minimum: 4.5),
    ]

    @Test func theTableHasTenRows() {
        #expect(Self.rows.count == 10)
    }

    /// The accessibility half. This is the assertion that must never be relaxed: it is the
    /// reason a hex is allowed to be what it is.
    @Test(arguments: rows)
    func everyApplicableRowClearsItsWCAGMinimum(_ row: Row) {
        // The table deliberately gives `amber on surface` no requirement: amber is a fill,
        // never text or a lone mark. Its upper bound is asserted by the dedicated fill-only
        // test below. Returning here is therefore the specified assertion for that row, not
        // a missing check.
        guard let minimum = row.minimum else { return }
        let ratio = contrastRatio(row.foreground, row.background)
        #expect(
            ratio >= minimum,
            "\(row.pair) is \(ratio) : 1, below the \(minimum) : 1 requirement in docs/07 §2"
        )
    }

    /// The drift half, and the loud one. `docs/07` §2 quotes each ratio to two decimals, so the
    /// tolerance only has to absorb that rounding — ±0.1 covers the worst row (`ink` on
    /// `paper`, printed as 16.5, computed 16.4425) with room to spare. The exact transcription
    /// test below catches even a one-channel, one-step change; this check separately keeps the
    /// documented contrast table honest.
    @Test(arguments: rows)
    func everyRowStillComputesToTheRatioTheDocPrints(_ row: Row) {
        let ratio = contrastRatio(row.foreground, row.background)
        #expect(
            abs(ratio - row.documented) <= 0.1,
            """
            \(row.pair) computes to \(ratio) : 1 but docs/07 §2 prints \(row.documented) : 1. \
            A hex changed. Either put it back or update docs/07 §2 in the same commit — the \
            palette and the table are one artefact.
            """
        )
    }

    // MARK: - The three amber tiers, asserted rather than described

    /// `amber` is 2.68:1 on `surface`: below every threshold, on purpose. Asserting the *upper*
    /// bound is the only way this stays a rule. If someone lightens `amber` until it passes
    /// 3.0 they have not fixed an accessibility problem, they have changed what the token
    /// means — it is a fill, and its job is to sit behind `ink`, not to be legible itself.
    @Test func amberIsBelowEveryThresholdOnPurpose() {
        let onSurface = contrastRatio(Palette.Hex.amber, Palette.Hex.surface)
        #expect(onSurface < 3.0, "amber is \(onSurface) : 1 on surface — it is no longer fill-only")
        // And the fill only works because what sits on it is `ink`.
        #expect(contrastRatio(Palette.Hex.ink, Palette.Hex.amber) >= 4.5)
    }

    /// `amber` fills, `amberDeep` draws, `amberText` writes — which is a statement about
    /// darkness, in that order. Three tiers that drifted into the same luminance would collapse
    /// into one token and the split would quietly stop meaning anything.
    @Test func theThreeAmberTiersStayInTheirOrder() {
        let fill = relativeLuminance(Palette.Hex.amber)
        let draw = relativeLuminance(Palette.Hex.amberDeep)
        let write = relativeLuminance(Palette.Hex.amberText)
        #expect(write < draw, "amberText must be darker than amberDeep — it carries body text")
        #expect(draw < fill, "amberDeep must be darker than amber — it draws on light surfaces")
        // The wash is a tinted surface, not a tier: it is lighter than all three.
        #expect(relativeLuminance(Palette.Hex.amberWash) > fill)
    }

    // MARK: - Transcription

    /// The six tokens with no contrast row still have to be the hexes `docs/07` §2 prints, and
    /// nothing else in this file would notice if they were not. This is a transcription check,
    /// not a contrast check: the literals below are read off the doc, so a typo made while
    /// copying the palette across shows up here.
    @Test func everyTokenIsTheHexTheDocPrints() {
        #expect(Palette.Hex.paper == 0xF3F4F7)
        #expect(Palette.Hex.paperSunk == 0xE8EAEF)
        #expect(Palette.Hex.surface == 0xFFFFFF)
        #expect(Palette.Hex.edge == 0xDEE1E9)
        #expect(Palette.Hex.edgeStrong == 0xC4C9D6)
        #expect(Palette.Hex.ink == 0x14161C)
        #expect(Palette.Hex.inkDim == 0x5A6072)
        #expect(Palette.Hex.inkFaint == 0x7C8294)
        #expect(Palette.Hex.amber == 0xE08A1E)
        #expect(Palette.Hex.amberDeep == 0xB96D0C)
        #expect(Palette.Hex.amberText == 0x8F5411)
        #expect(Palette.Hex.amberWash == 0xFDF3E3)
        #expect(Palette.Hex.ultramarine == 0x2C3FE0)
        #expect(Palette.Hex.ultramarineDeep == 0x1E2CA8)
        #expect(Palette.Hex.ultramarineWash == 0xEEF0FE)
        #expect(Palette.Hex.alert == 0xB3261E)
    }

    /// Every `Color` on `Palette` is built from the matching `Hex`, so the two can never
    /// disagree — which is what lets the tests above reason about `Hex` and conclude something
    /// about what actually renders.
    @Test func everyColourIsBuiltFromItsHex() {
        #expect(Palette.paper == Color(hex: Palette.Hex.paper))
        #expect(Palette.paperSunk == Color(hex: Palette.Hex.paperSunk))
        #expect(Palette.surface == Color(hex: Palette.Hex.surface))
        #expect(Palette.edge == Color(hex: Palette.Hex.edge))
        #expect(Palette.edgeStrong == Color(hex: Palette.Hex.edgeStrong))
        #expect(Palette.ink == Color(hex: Palette.Hex.ink))
        #expect(Palette.inkDim == Color(hex: Palette.Hex.inkDim))
        #expect(Palette.inkFaint == Color(hex: Palette.Hex.inkFaint))
        #expect(Palette.amber == Color(hex: Palette.Hex.amber))
        #expect(Palette.amberDeep == Color(hex: Palette.Hex.amberDeep))
        #expect(Palette.amberText == Color(hex: Palette.Hex.amberText))
        #expect(Palette.amberWash == Color(hex: Palette.Hex.amberWash))
        #expect(Palette.ultramarine == Color(hex: Palette.Hex.ultramarine))
        #expect(Palette.ultramarineDeep == Color(hex: Palette.Hex.ultramarineDeep))
        #expect(Palette.ultramarineWash == Color(hex: Palette.Hex.ultramarineWash))
        #expect(Palette.alert == Color(hex: Palette.Hex.alert))
    }

    // MARK: - Light mode only

    /// `CLAUDE.md` §2.4, made checkable: *"No dark mode in v1. Do not add `@Environment(\.colorScheme)`
    /// branches."*
    ///
    /// A palette with one value per token is only half of light-mode-only; the other half is that
    /// nothing downstream reintroduces a second value. `ios/scripts/lint.sh` rule 4 already greps
    /// for `colorScheme`, but a lint script is a thing someone has to remember to run, and the
    /// E08-02 checklist box says *anywhere*. So the test suite reads the source tree itself.
    @Suite struct LightModeOnlyTests {

        /// `ios/BlindDrop/`, found by walking up from this file. The simulator runs tests against
        /// the host filesystem, so the checkout is readable from here; if that ever stops being
        /// true the `#require` below fails loudly rather than passing on an empty file list.
        private static var appSourceRoot: URL {
            URL(fileURLWithPath: #filePath)          // …/ios/BlindDropTests/Unit/PaletteContrastTests.swift
                .deletingLastPathComponent()         // …/ios/BlindDropTests/Unit
                .deletingLastPathComponent()         // …/ios/BlindDropTests
                .deletingLastPathComponent()         // …/ios
                .appendingPathComponent("BlindDrop")
        }

        /// Comment text is stripped before matching, so this rule can be written about — and cited
        /// in a doc comment — without tripping over itself.
        private func codeIgnoringComments(_ source: String) -> String {
            source.split(separator: "\n", omittingEmptySubsequences: false)
                .map { line -> Substring in
                    if let slashes = line.range(of: "//") { return line[line.startIndex..<slashes.lowerBound] }
                    return line
                }
                .joined(separator: "\n")
        }

        private func swiftSources() throws -> [(path: String, code: String)] {
            let root = Self.appSourceRoot
            let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" } ?? []
            // A scan over nothing passes over nothing. Fail instead.
            try #require(!files.isEmpty, "no Swift sources found under \(root.path) — the scan would be vacuous")
            return try files.map { url in
                (path: url.lastPathComponent, code: codeIgnoringComments(try String(contentsOf: url, encoding: .utf8)))
            }
        }

        /// The forbidden constructor. Two values behind one token is dark mode wearing a hat.
        @Test func noColourIsDeclaredWithALightDarkPair() throws {
            for file in try swiftSources() {
                #expect(
                    !file.code.contains("Color(light:"),
                    "\(file.path) declares a light/dark colour pair — CLAUDE.md §2.4: light mode only, one value per token"
                )
            }
        }

        /// The other route to the same place: branching on the environment at render time.
        @Test func nothingBranchesOnTheColourScheme() throws {
            for file in try swiftSources() {
                #expect(
                    !file.code.contains("colorScheme"),
                    "\(file.path) reads the colour scheme — CLAUDE.md §2.4: the app is .preferredColorScheme(.light) and never asks"
                )
            }
        }

        /// Asset-catalog colours are the third route, and the quietest: an `.colorset` can carry an
        /// Any/Dark appearance pair with nothing in the Swift source to show for it. The palette is
        /// code for exactly this reason.
        @Test func thereIsNoColourAssetCatalogToCarryADarkAppearance() {
            let assets = FileManager.default.enumerator(at: Self.appSourceRoot, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "colorset" } ?? []
            #expect(assets.isEmpty, "colour assets found: \(assets.map(\.lastPathComponent)) — colours live in Palette.swift, in code")
        }
    }
}
