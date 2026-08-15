import CoreText
import SwiftUI
import Testing
import UIKit
@testable import BlindDrop

/// `docs/07` §3 and `docs/12` §1, asserted rather than trusted.
///
/// Four of these tests exist because the failure they catch is silent. A font that did not
/// load falls back to SF Pro and looks *fine*; numerals that are not tabular only misbehave
/// while a timer is ticking; a scale ceiling that stopped applying is invisible until somebody
/// running `.accessibility5` opens the reveal screen. None of that shows up in a screenshot
/// taken at the default size on the machine that shipped it.
@Suite struct TypographyTests {

    /// The category matching each `DynamicTypeSize`, for the tests that walk the ramp.
    private let smallest = UIContentSizeCategory.large
    private let largest = UIContentSizeCategory.accessibilityExtraExtraExtraLarge

    // MARK: - The face actually loaded

    /// The one that catches a missing `UIAppFonts` entry, a renamed file, or a resource that
    /// stopped being copied into the bundle. `docs/07` §3 gives the display face six jobs in
    /// the whole app; if it silently became SF Pro, every one of them would still render.
    @Test func theDisplayFaceIsBricolageAndNotTheSystemFont() {
        let font = Typography.uiFont(.displayXL, for: smallest)
        #expect(font.familyName == Typography.displayFamily)
        #expect(!font.familyName.contains("SF Pro"))
        #expect(!font.familyName.contains(".AppleSystemUIFont"))
        #expect(font.familyName != UIFont.systemFont(ofSize: 56).familyName)
    }

    /// Every display style is cut from the same face; the body and mono styles are not.
    @Test func eachFaceIsUsedForItsOwnStyles() {
        for style in TypeStyle.allCases {
            let font = Typography.uiFont(style, for: smallest)
            switch style.spec.face {
            case .display:
                #expect(font.familyName == Typography.displayFamily, "\(style) lost the display face")
            case .body:
                #expect(font.familyName != Typography.displayFamily, "\(style) is not body text")
            case .mono:
                #expect(font.familyName != Typography.displayFamily, "\(style) is not mono")
                // SF Mono, whatever the platform is calling it this year: the advance width of
                // an `i` and an `m` are the same, which is the only property that matters.
                let narrow = ("i" as NSString).size(withAttributes: [.font: font]).width
                let wide = ("m" as NSString).size(withAttributes: [.font: font]).width
                #expect(abs(narrow - wide) < 0.01, "\(style) is not monospaced")
            }
        }
    }

    // MARK: - The variation axes

    /// `docs/07` §3: the numerals are set in the widest cut the face carries, and the width is
    /// read off the font rather than transcribed. What is asserted is both halves — the axis
    /// is set to its own maximum, and that maximum is still the number the doc records, so a
    /// font swap that quietly narrows the family fails here instead of shipping.
    @Test func theDisplayFaceIsSetOnItsAxes() throws {
        let font = Typography.uiFont(.displayXL, for: smallest)
        let axes = try #require(CTFontCopyVariationAxes(font as CTFont) as? [[CFString: Any]])
        // `CTFontCopyVariation` is keyed by the axis's four-character code as a number, and it
        // **omits an axis that is sitting at its default value** — so an absent key means "at
        // the default", not "never set", and the lookup below says so rather than failing.
        let variation = try #require(CTFontCopyVariation(font as CTFont) as? [AnyHashable: Any])

        func identifier(_ tag: String) -> Int {
            tag.unicodeScalars.reduce(0) { ($0 << 8) + Int($1.value) }
        }
        func axis(_ tag: String) throws -> (minimum: CGFloat, maximum: CGFloat, standard: CGFloat) {
            let match = try #require(axes.first {
                ($0[kCTFontVariationAxisIdentifierKey] as? Int) == identifier(tag)
            })
            return (
                try #require(match[kCTFontVariationAxisMinimumValueKey] as? CGFloat),
                try #require(match[kCTFontVariationAxisMaximumValueKey] as? CGFloat),
                try #require(match[kCTFontVariationAxisDefaultValueKey] as? CGFloat)
            )
        }
        func setting(_ tag: String) throws -> CGFloat {
            try variation[NSNumber(value: identifier(tag))] as? CGFloat ?? axis(tag).standard
        }

        let width = try axis("wdth")
        let weight = try axis("wght")
        let optical = try axis("opsz")

        #expect(try setting("wdth") == width.maximum, "the widest cut the face has")
        #expect(Typography.displayWidth == width.maximum,
                "the face's width axis moved — docs/07 §3 records this number")

        #expect(try setting("wght") == Typography.axisWeight(TypeStyle.displayXL.spec.weight))
        #expect(Typography.displayWeight >= weight.minimum)
        #expect(Typography.displayWeight <= weight.maximum)

        // The optical-size axis tracks the size the glyphs are actually drawn at.
        #expect(try setting("opsz")
            == min(max(font.pointSize, optical.minimum), optical.maximum))
    }

    // MARK: - Dynamic Type

    /// `docs/12` §1: every style scales. Not "most", and not "the ones somebody remembered".
    @Test func everyStyleGrowsWithDynamicType() {
        for style in TypeStyle.allCases {
            let small = Typography.uiFont(style, for: .extraSmall).pointSize
            let base = Typography.uiFont(style, for: smallest).pointSize
            let big = Typography.uiFont(style, for: largest).pointSize
            #expect(small < base, "\(style) does not shrink below the default")
            #expect(big > base, "\(style) does not scale with Dynamic Type")
        }
    }

    /// The base sizes are the doc's, at the default category, to one decimal place. This is
    /// the test that notices somebody nudging 17pt to 16pt because a screen was tight.
    @Test func theScaleMatchesTheDocumentedSizes() {
        let documented: [TypeStyle: CGFloat] = [
            .displayXL: 56, .displayL: 44, .displayM: 32, .displayS: 24,
            .numberL: 44, .numberM: 26,
            .bodyL: 17, .bodyLStrong: 17, .bodyM: 15, .bodyS: 13,
            .label: 11, .labelSmall: 10, .caption: 13,
            .monoXL: 34, .monoM: 15, .monoS: 12,
        ]
        #expect(documented.count == TypeStyle.allCases.count, "docs/07 §3 has twelve styles")
        for (style, size) in documented {
            #expect(style.spec.size == size, "\(style)")
            #expect(abs(Typography.uiFont(style, for: smallest).pointSize - size) < 0.5, "\(style)")
        }
    }

    /// `docs/12` §1's one allowed scaling limit: the display face stops at 1.6×. At
    /// `.accessibility5` an uncapped 56pt numeral is around 130pt and eats the card.
    @Test func theDisplayFaceStopsAt1Point6() {
        for style in TypeStyle.allCases where style.spec.face == .display {
            let base = style.spec.size
            let biggest = Typography.uiFont(style, for: largest).pointSize
            #expect(biggest <= base * Typography.displayMaximumScale + 0.5, "\(style) is uncapped")
            #expect(biggest > base, "\(style) is capped so hard it stopped scaling")
        }
        // 56pt × 1.6 = 89.6pt, and it is still the largest thing on the card: the results
        // card's number beside it at the same size is smaller.
        let number = Typography.uiFont(.displayXL, for: largest).pointSize
        #expect(number > Typography.uiFont(.numberL, for: largest).pointSize)
    }

    /// Nothing else is capped. A ceiling on body text is a truncated screen for the people who
    /// need the text large, which is the failure `docs/12` §1 spends its first rule on.
    @Test func nothingButTheDisplayFaceIsCapped() {
        for style in TypeStyle.allCases where style.spec.face != .display {
            #expect(style.spec.maximumScale == nil, "\(style) must not have a scaling ceiling")
        }
    }

    // MARK: - Numbers that do not move

    /// `docs/07` §3: tabular figures on every mono style and every display numeral. Asserted by
    /// measuring, not by reading the descriptor back: what matters is that a `1` and a `8`
    /// occupy the same width, which is the thing a ticking countdown depends on.
    @Test func numeralsAreTabularWhereANumberChanges() {
        for style in TypeStyle.allCases where style.spec.isTabular {
            let font = Typography.uiFont(style, for: smallest)
            let widths = (0...9).map { digit in
                (String(digit) as NSString).size(withAttributes: [.font: font]).width
            }
            let spread = (widths.max() ?? 0) - (widths.min() ?? 0)
            #expect(spread < 0.01, "\(style) has proportional figures — a timer in it jitters")
        }
    }

    /// Both the mono styles and the display styles are tabular; body text is not, because
    /// tabular figures in a sentence look like a spreadsheet.
    @Test func tabularIsAskedForExactlyWhereTheDocSaysItIs() {
        for style in TypeStyle.allCases {
            let expected = style.spec.face == .mono || style.spec.face == .display
            #expect(style.spec.isTabular == expected, "\(style)")
        }
    }

    // MARK: - The countdown's two forms

    /// `docs/12` §1: above `.accessibility2` the countdown stops being `HH:MM:SS` and becomes
    /// *"3 hours"*. The boundary is asserted on both sides — a rule that fired one size early
    /// would take the digits away from someone who could still read them.
    @Test func theCountdownGoesCoarseAboveAccessibility2() {
        for size in DynamicTypeSize.allCases where size <= .accessibility2 {
            #expect(Typography.countdownForm(for: size) == .precise, "\(size)")
        }
        for size in DynamicTypeSize.allCases where size > .accessibility2 {
            #expect(Typography.countdownForm(for: size) == .coarse, "\(size)")
        }
        #expect(CountdownForm.precise.typeStyle == .displayXL)
        #expect(CountdownForm.coarse.typeStyle == .bodyLStrong)
    }

    // MARK: - Leading

    /// Line height scales with the size it belongs to, so a paragraph at `.accessibility5` has
    /// the same rhythm it has at `.large` rather than growing text inside fixed leading.
    @Test func leadingScalesWithTheTypeItLeads() {
        for style in TypeStyle.allCases {
            let spec = style.spec
            let base = Typography.lineHeight(style, for: smallest)
            let big = Typography.lineHeight(style, for: largest)
            #expect(abs(base - spec.lineHeight) < 0.5, "\(style)")
            #expect(big > base, "\(style)")
            let baseRatio = base / Typography.uiFont(style, for: smallest).pointSize
            let bigRatio = big / Typography.uiFont(style, for: largest).pointSize
            #expect(abs(baseRatio - bigRatio) < 0.001, "\(style) changed its leading ratio")
        }
    }
}
