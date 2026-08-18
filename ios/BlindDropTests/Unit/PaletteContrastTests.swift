import Foundation
import SwiftUI
import Testing
import UIKit
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

    // MARK: - The eleven rows of docs/07 §2

    /// One row of the `docs/07` §2 contrast table.
    struct Row: Sendable, CustomStringConvertible {
        /// The pair, spelled as the doc spells it, so a failure names the row you can go read.
        let pair: String
        let foreground: UInt32
        let background: UInt32
        /// The ratio `docs/07` §2 prints. Drift from the computed value means someone edited a
        /// hex without editing the doc — or the doc without the hex.
        let documented: Double
        /// The WCAG minimum this pair has to clear, or `nil` for a row `docs/07` §2 prints with
        /// `—` in its requirement column. Every row currently has one; the optional is what lets
        /// a future surface-only pair into the drift check without inventing a threshold for it.
        let minimum: Double?

        var description: String { pair }
    }

    /// Verbatim from the `docs/07` §2 table, in its order. Eleven rows, and that is the list —
    /// the remaining tokens (`paperSunk`, `edge`, `edgeStrong`, `hairline`, `track`, the two washes,
    /// the two wash edges, the row tint and the pressed fills) are surfaces and borders that
    /// carry no text, and inventing thresholds for them would be inventing spec.
    static let rows: [Row] = [
        Row(pair: "ink on paper",
            foreground: Palette.Hex.ink, background: Palette.Hex.paper,
            documented: 16.02, minimum: 4.5),
        Row(pair: "inkDim on paper",
            foreground: Palette.Hex.inkDim, background: Palette.Hex.paper,
            documented: 7.77, minimum: 4.5),
        // 3.0, not 4.5: large text (≥ 24pt) and UI only. Never body text, never a micro-label.
        Row(pair: "inkFaint on paper",
            foreground: Palette.Hex.inkFaint, background: Palette.Hex.paper,
            documented: 3.71, minimum: 3.0),
        Row(pair: "amberText on paper",
            foreground: Palette.Hex.amberText, background: Palette.Hex.paper,
            documented: 5.65, minimum: 4.5),
        // The amber fill's label. 3.0, not 4.5: it is the 17pt semibold button label and nothing
        // smaller, which is WCAG's large-text case. `theAmberFillOnlyEverCarriesLargeText` is
        // what keeps that from quietly becoming a licence to set body copy on amber.
        Row(pair: "white on amber fill",
            foreground: Palette.Hex.surface, background: Palette.Hex.amber,
            documented: 4.24, minimum: 3.0),
        // 3.0: non-text graphics — marks, borders, icons, the seal stamp, a card number.
        Row(pair: "amber on surface",
            foreground: Palette.Hex.amber, background: Palette.Hex.surface,
            documented: 4.24, minimum: 3.0),
        // The other half of `PhaseAccent.mark`, on the same white card. Same bar as its amber
        // sibling for the same reason: it draws `FlightCard`'s number and How to play's step
        // numeral, both `numberM`. The ratio is the transpose of `white on ultramarine fill`,
        // and the row is here anyway — a table where one accent's mark tier is written down and
        // the other's is only implied is a table somebody reads as a rule about amber.
        Row(pair: "ultramarine on surface",
            foreground: Palette.Hex.ultramarine, background: Palette.Hex.surface,
            documented: 8.98, minimum: 3.0),
        Row(pair: "amberText on amberWash",
            foreground: Palette.Hex.amberText, background: Palette.Hex.amberWash,
            documented: 5.37, minimum: 4.5),
        Row(pair: "ultramarine on paper",
            foreground: Palette.Hex.ultramarine, background: Palette.Hex.paper,
            documented: 7.94, minimum: 4.5),
        Row(pair: "white on ultramarine fill",
            foreground: Palette.Hex.surface, background: Palette.Hex.ultramarine,
            documented: 8.98, minimum: 4.5),
        Row(pair: "alert on paper",
            foreground: Palette.Hex.alert, background: Palette.Hex.paper,
            documented: 5.78, minimum: 4.5),
    ]

    @Test func theTableHasElevenRows() {
        #expect(Self.rows.count == 11)
    }

    /// The accessibility half. This is the assertion that must never be relaxed: it is the
    /// reason a hex is allowed to be what it is.
    @Test(arguments: rows)
    func everyApplicableRowClearsItsWCAGMinimum(_ row: Row) {
        // A row `docs/07` §2 prints with `—` in its requirement column has nothing to clear:
        // it is a surface pair, and inventing a threshold for it would be inventing spec. Such
        // a row is still held to the documented ratio by the drift test below.
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

    /// The amber fill carries a white label at 4.24:1, which is **large text only**.
    ///
    /// The row above gives it a 3.0 minimum, and a minimum on its own is the kind of rule that
    /// erodes: somebody sets a 13pt caption in white on amber, the row still passes, and the
    /// caption is illegible. So the pair is pinned from both sides — it must clear 3.0, and it
    /// must *not* clear 4.5, because the day it does is the day this test should be deleted
    /// along with the restriction it encodes rather than quietly outliving it.
    @Test func theAmberFillOnlyEverCarriesLargeText() {
        let onFill = contrastRatio(Palette.Hex.surface, Palette.Hex.amber)
        #expect(onFill >= 3.0, "white on amber is \(onFill) : 1 — below the large-text bar")
        #expect(
            onFill < 4.5,
            """
            white on amber now clears the body bar at \(onFill) : 1. That is not a free \
            improvement — `PhaseAccent.onFill` is documented as large-text-only and several \
            views rely on that being enforced. Update docs/07 §2 and this test together.
            """
        )
    }

    /// `amber` fills, `amberDeep` draws, `amberText` writes — which is a statement about
    /// darkness, in that order. Three tiers that drifted into the same luminance would collapse
    /// into one token and the split would quietly stop meaning anything.
    @Test func theThreeAmberTiersStayInTheirOrder() {
        let fill = relativeLuminance(Palette.Hex.amber)
        let pressed = relativeLuminance(Palette.Hex.amberDeep)
        let write = relativeLuminance(Palette.Hex.amberText)
        #expect(write < pressed, "amberText must be darker than amberDeep — it carries body text")
        #expect(pressed < fill, "amberDeep must be darker than amber — a press darkens")
        // The wash and its edge are tinted surfaces, not tiers: both are lighter than all three,
        // and the edge is the darker of the two or it would not be an edge.
        #expect(relativeLuminance(Palette.Hex.amberEdge) > fill)
        #expect(relativeLuminance(Palette.Hex.amberWash) > relativeLuminance(Palette.Hex.amberEdge))
    }

    // MARK: - The legend numerals, at the size they are drawn

    /// How to play's step numerals (`HowToSheet.step`), which `CLAUDE.md` §2.5's second
    /// exception lets carry both accents on one page because they are the legend.
    ///
    /// The exception is about meaning; it lowers no floor. And the floor for `amber` is the
    /// interesting one — 4.24:1 on `surface` clears WCAG's 3.0 large-text-and-graphics bar and
    /// misses the 4.5 body bar — so the colour is only defensible for as long as the numeral
    /// stays large. That makes this **two** assertions, not one: the ratio, and the point size
    /// that decides which ratio applies. A test that checked the colour alone would go on
    /// passing the day somebody re-set the numerals in `bodyM`, and the page would be quietly
    /// illegible to the readers it matters most to.
    @Test func theLegendNumeralsClearTheBarAtTheSizeTheyAreDrawn() {
        // The tier the page actually asks for, rather than a hex picked here to match it —
        // `HowToSheet` writes `accent.mark`, so `mark` is what has to clear the bar.
        #expect(PhaseAccent.sealed.mark == Color(hex: Palette.Hex.amber))
        #expect(PhaseAccent.revealed.mark == Color(hex: Palette.Hex.ultramarine))

        // Step 1 is `.sealed`, steps 2–4 are `.revealed`, and all four are drawn on the white
        // of `cardSurface()` — not on `paper`, which is the background the §2 table's other
        // accent rows are measured against.
        for (step, hex) in [("step 1 — amber", Palette.Hex.amber),
                            ("steps 2–4 — ultramarine", Palette.Hex.ultramarine)] {
            let ratio = contrastRatio(hex, Palette.Hex.surface)
            #expect(
                ratio >= 3.0,
                "\(step) is \(ratio) : 1 on surface — below the 3.0 large-text bar in docs/07 §2"
            )
        }

        // The size half. WCAG 2.1 calls bold text large from 14pt; `numberM` is 26pt at `.large`
        // and rides the `.title1` ramp, so the smallest it is ever drawn at is whatever the
        // smallest content-size category resolves to. That number is what has to clear 14.
        let resolved = DynamicTypeSize.allCases.map {
            Typography.uiFont(.numberM, for: UIContentSizeCategory($0)).pointSize
        }
        let smallest = resolved.min() ?? 0
        #expect(
            smallest >= 14,
            """
            How to play's numeral resolves to \(smallest)pt at the smallest Dynamic Type size, \
            under WCAG's 14pt bold large-text threshold. `amber` on `surface` is 4.24 : 1 — it \
            clears the 3.0 large-text bar and misses the 4.5 body bar, so a smaller numeral \
            makes the colour wrong rather than merely small. Put the size back, or move the \
            numeral to `PhaseAccent.text` (`amberText`, 6.39 : 1 on surface) and say so in \
            docs/07 §2.
            """
        )
    }

    // MARK: - Transcription

    /// The six tokens with no contrast row still have to be the hexes `docs/07` §2 prints, and
    /// nothing else in this file would notice if they were not. This is a transcription check,
    /// not a contrast check: the literals below are read off the doc, so a typo made while
    /// copying the palette across shows up here.
    @Test func everyTokenIsTheHexTheDocPrints() {
        #expect(Palette.Hex.paper == 0xEFF1F5)
        #expect(Palette.Hex.paperSunk == 0xE7EAEF)
        #expect(Palette.Hex.surface == 0xFFFFFF)
        #expect(Palette.Hex.edge == 0xDCE0E7)
        #expect(Palette.Hex.edgeStrong == 0xD3D8E0)
        #expect(Palette.Hex.hairline == 0xEAEDF1)
        #expect(Palette.Hex.track == 0xEEF0F4)
        #expect(Palette.Hex.ink == 0x14161A)
        #expect(Palette.Hex.inkDim == 0x454B55)
        #expect(Palette.Hex.inkFaint == 0x767C88)
        #expect(Palette.Hex.inkQuiet == 0xB9BEC7)
        #expect(Palette.Hex.amber == 0xB26A06)
        #expect(Palette.Hex.amberDeep == 0x96590A)
        #expect(Palette.Hex.amberText == 0x8A5205)
        #expect(Palette.Hex.amberWash == 0xF6EAD6)
        #expect(Palette.Hex.amberEdge == 0xE6CFA6)
        #expect(Palette.Hex.ultramarine == 0x2233C4)
        #expect(Palette.Hex.ultramarineDeep == 0x1B29A0)
        #expect(Palette.Hex.ultramarineWash == 0xE3E6FA)
        #expect(Palette.Hex.ultramarineEdge == 0xC3C9F2)
        #expect(Palette.Hex.alert == 0xB3261E)
    }

    /// The neutrals have to stay in their order, or the three of them stop being a scale and
    /// start being three greys. Each is lighter than the one before it, and every one of them is
    /// darker than the surface they are drawn on.
    @Test func theNeutralTextTiersStayInTheirOrder() {
        let tiers = [Palette.Hex.ink, Palette.Hex.inkDim, Palette.Hex.inkFaint,
                     Palette.Hex.inkQuiet]
        for (darker, lighter) in zip(tiers, tiers.dropFirst()) {
            #expect(relativeLuminance(darker) < relativeLuminance(lighter))
        }
        #expect(relativeLuminance(Palette.Hex.inkQuiet) < relativeLuminance(Palette.Hex.paper))
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
        #expect(Palette.hairline == Color(hex: Palette.Hex.hairline))
        #expect(Palette.track == Color(hex: Palette.Hex.track))
        #expect(Palette.ink == Color(hex: Palette.Hex.ink))
        #expect(Palette.inkDim == Color(hex: Palette.Hex.inkDim))
        #expect(Palette.inkFaint == Color(hex: Palette.Hex.inkFaint))
        #expect(Palette.inkQuiet == Color(hex: Palette.Hex.inkQuiet))
        #expect(Palette.amber == Color(hex: Palette.Hex.amber))
        #expect(Palette.amberDeep == Color(hex: Palette.Hex.amberDeep))
        #expect(Palette.amberText == Color(hex: Palette.Hex.amberText))
        #expect(Palette.amberWash == Color(hex: Palette.Hex.amberWash))
        #expect(Palette.amberEdge == Color(hex: Palette.Hex.amberEdge))
        #expect(Palette.ultramarine == Color(hex: Palette.Hex.ultramarine))
        #expect(Palette.ultramarineDeep == Color(hex: Palette.Hex.ultramarineDeep))
        #expect(Palette.ultramarineWash == Color(hex: Palette.Hex.ultramarineWash))
        #expect(Palette.ultramarineEdge == Color(hex: Palette.Hex.ultramarineEdge))
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
