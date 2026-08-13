import CoreText
import SwiftUI
import UIKit

/// The eleven type styles of `docs/07` §3, and the one place a point size is written down.
///
/// Three roles, three faces, and they do not do each other's jobs:
///
/// - **Display / numerals** — Bricolage Grotesque, the variable font in `Resources/Fonts`.
///   Card numbers, the countdown, results headlines. `docs/07` §3: *"used in roughly six
///   places in the entire app"*, and never below 20pt, where its personality reads as noise.
/// - **Body / UI** — SF Pro Text, the system face. Everything else. Do not fight the platform.
/// - **Data / timers** — SF Mono. Countdown digits, percentages, scores, counts.
///
/// Everything here scales with Dynamic Type through `UIFontMetrics` (`docs/12` §1). Nothing in
/// `Features/` may write `.font(.system(size:))` — `ios/scripts/lint.sh` fails the build on a
/// raw size in a feature file, because a fixed size is a screen that breaks at
/// `.accessibility5` and nobody notices until somebody who needs it opens the app.
enum TypeStyle: String, CaseIterable, Sendable {
    /// 56/56 · Bricolage 600 wdth max — the reveal card number, the countdown.
    case displayXL
    /// 40/44 · Bricolage 600 wdth max — the results headline.
    case displayL
    /// 28/32 · Bricolage 600 wdth max — a screen title, used sparingly.
    case displayM
    /// 17/24 · SF Pro Text Regular — the default.
    case bodyL
    /// 17/24 · SF Pro Text Semibold — track titles.
    case bodyLStrong
    /// 15/20 · SF Pro Text Regular — artist, supporting text.
    case bodyM
    /// 13/16 · SF Pro Text Medium, tracking +0.6, uppercase — section labels.
    case label
    /// 12/16 · SF Pro Text Regular — helper text.
    case caption
    /// 34/36 · SF Mono Medium — countdown digits.
    case monoXL
    /// 17/22 · SF Mono Medium — percentages, scores.
    case monoM
    /// 13/16 · SF Mono Regular — small counts.
    case monoS
}

extension TypeStyle {

    /// Which of the three faces a style is cut from.
    enum Face: Sendable {
        /// Bricolage Grotesque, the bundled variable font.
        case display
        /// SF Pro Text, the system face.
        case body
        /// SF Mono, the system monospaced face.
        case mono
    }

    /// One row of the `docs/07` §3 scale. Sizes are the *base* sizes, at the `.large` content
    /// size category; every one of them is scaled before it reaches a view.
    struct Spec: Sendable {
        let size: CGFloat
        let lineHeight: CGFloat
        let face: Face
        let weight: UIFont.Weight
        /// The Dynamic Type ramp this style scales along. Display and mono styles ride
        /// `.largeTitle` and `.title2` rather than `.body`, because the accessibility sizes
        /// grow body text far more aggressively than headline text — the ramp is the part of
        /// Dynamic Type that knows a 56pt numeral does not need to become 130pt.
        let textStyle: UIFont.TextStyle
        /// Letter spacing, in points at the base size.
        let tracking: CGFloat
        /// Whether the style is set in capitals. Only `label` is.
        let isUppercase: Bool
        /// The scale ceiling, as a multiple of `size`, or `nil` for no ceiling.
        ///
        /// **The display face is the one place a scaling limit is allowed** (`docs/12` §1):
        /// at `.accessibility5` an uncapped 56pt numeral is around 130pt and eats the card it
        /// is printed on. It stays the largest thing on the card at every size regardless,
        /// which is why capping it costs the reader nothing.
        let maximumScale: CGFloat?
        /// Whether numerals are tabular.
        ///
        /// `docs/07` §3 makes this mandatory on every mono style and every display numeral:
        /// *"nothing shifts horizontally as a timer ticks"*. A countdown that jitters is the
        /// most visible possible signal that an app is amateur, and it is one attribute away
        /// either side.
        let isTabular: Bool
    }

    var spec: Spec {
        switch self {
        case .displayXL:
            Spec(size: 56, lineHeight: 56, face: .display, weight: .semibold,
                 textStyle: .largeTitle, tracking: 0, isUppercase: false,
                 maximumScale: Typography.displayMaximumScale, isTabular: true)
        case .displayL:
            Spec(size: 40, lineHeight: 44, face: .display, weight: .semibold,
                 textStyle: .largeTitle, tracking: 0, isUppercase: false,
                 maximumScale: Typography.displayMaximumScale, isTabular: true)
        case .displayM:
            Spec(size: 28, lineHeight: 32, face: .display, weight: .semibold,
                 textStyle: .title1, tracking: 0, isUppercase: false,
                 maximumScale: Typography.displayMaximumScale, isTabular: true)
        case .bodyL:
            Spec(size: 17, lineHeight: 24, face: .body, weight: .regular,
                 textStyle: .body, tracking: 0, isUppercase: false,
                 maximumScale: nil, isTabular: false)
        case .bodyLStrong:
            Spec(size: 17, lineHeight: 24, face: .body, weight: .semibold,
                 textStyle: .body, tracking: 0, isUppercase: false,
                 maximumScale: nil, isTabular: false)
        case .bodyM:
            Spec(size: 15, lineHeight: 20, face: .body, weight: .regular,
                 textStyle: .subheadline, tracking: 0, isUppercase: false,
                 maximumScale: nil, isTabular: false)
        case .label:
            Spec(size: 13, lineHeight: 16, face: .body, weight: .medium,
                 textStyle: .footnote, tracking: 0.6, isUppercase: true,
                 maximumScale: nil, isTabular: false)
        case .caption:
            Spec(size: 12, lineHeight: 16, face: .body, weight: .regular,
                 textStyle: .caption1, tracking: 0, isUppercase: false,
                 maximumScale: nil, isTabular: false)
        case .monoXL:
            Spec(size: 34, lineHeight: 36, face: .mono, weight: .medium,
                 textStyle: .title1, tracking: 0, isUppercase: false,
                 maximumScale: nil, isTabular: true)
        case .monoM:
            Spec(size: 17, lineHeight: 22, face: .mono, weight: .medium,
                 textStyle: .body, tracking: 0, isUppercase: false,
                 maximumScale: nil, isTabular: true)
        case .monoS:
            Spec(size: 13, lineHeight: 16, face: .mono, weight: .regular,
                 textStyle: .footnote, tracking: 0, isUppercase: false,
                 maximumScale: nil, isTabular: true)
        }
    }
}

/// How the countdown is rendered at a given Dynamic Type size (`docs/12` §1).
enum CountdownForm: Sendable {
    /// `HH:MM:SS` in `monoXL`, ticking every second.
    case precise
    /// *"3 hours"* / *"12 minutes"* / *"under a minute"* in `bodyLStrong`, updating every
    /// minute.
    ///
    /// **This is an improvement, not a fallback.** `monoXL` at `.accessibility5` cannot fit
    /// eight monospaced digits on an SE, and at that text size the reader is not reading
    /// seconds anyway.
    case coarse

    var typeStyle: TypeStyle {
        switch self {
        case .precise: .monoXL
        case .coarse: .bodyLStrong
        }
    }
}

/// Font resolution: the bundled face, the variation axes, the Dynamic Type ramp, and the two
/// rules (`docs/12` §1) that are about numbers rather than about letters.
enum Typography {

    // MARK: - The display face

    /// The bundled variable font's family name. Registered by `UIAppFonts` in `Info.plist`;
    /// `TypographyTests` asserts it actually loaded rather than trusting the plist.
    static let displayFamily = "Bricolage Grotesque"

    /// `docs/07` §3: *"Set the `wdth` axis to the widest cut the face carries — the expanded
    /// cut is what gives the numbers character."*
    ///
    /// So the value is **read off the face** rather than written down: whatever the width axis
    /// tops out at is what the numerals are set in, which is what the rule actually says. The
    /// constant below is the shipped face's maximum, and it is used for one thing — the
    /// fallback when a face has no width axis at all, and the number `TypographyTests` checks
    /// the face against, so that a font swap which quietly narrows the family is noticed
    /// rather than absorbed.
    static let displayWidth: CGFloat = 100

    /// `wght 600` — semibold. Inside the face's 200…800 range, so it is set exactly.
    static let displayWeight: CGFloat = 600

    /// The display face's scale ceiling (`docs/12` §1).
    static let displayMaximumScale: CGFloat = 1.6

    /// Variation axis tags, as the four-character codes CoreText keys variations by.
    private enum Axis {
        static let weight = fourCharacterCode("wght")
        static let width = fourCharacterCode("wdth")
        static let opticalSize = fourCharacterCode("opsz")

        static func fourCharacterCode(_ tag: String) -> Int {
            tag.unicodeScalars.reduce(0) { ($0 << 8) + Int($1.value) }
        }
    }

    // MARK: - Resolution

    /// The font for a style at a given content size category.
    ///
    /// The category is a parameter rather than being read from the environment so that the
    /// same call is available to a view, to a snapshot test rendering at `.accessibility5`,
    /// and to a unit test asserting the 1.6× cap. `.unspecified` means "whatever the device is
    /// set to", which is what the app itself passes.
    static func uiFont(_ style: TypeStyle, for category: UIContentSizeCategory = .unspecified) -> UIFont {
        let spec = style.spec
        let base = baseFont(spec)
        let traits = UITraitCollection(preferredContentSizeCategory: category)
        let metrics = UIFontMetrics(forTextStyle: spec.textStyle)

        // The cap is applied through `maximumPointSize:` rather than by clamping afterwards,
        // so the font is built once at the size it will actually be drawn at — which is what
        // keeps the optical-size axis below honest.
        let ceiling = spec.maximumScale.map { spec.size * $0 } ?? 0
        let scaled = metrics.scaledFont(for: base, maximumPointSize: ceiling, compatibleWith: traits)

        guard spec.face == .display else { return scaled }
        // The display face's optical size axis is re-set at the scaled size: the same outline
        // drawn at 28pt and at 90pt wants different spacing, and the whole reason to ship a
        // variable font rather than a static cut is that it can do that.
        return displayFont(pointSize: scaled.pointSize, spec: spec)
    }

    /// Makes sure the display face is loaded, registering it from the bundle if it is not.
    ///
    /// > *"Fonts must be registered before rendering. `ImageRenderer` silently falls back to the
    /// > system face if Bricolage is not loaded."* (`docs/10` §4)
    ///
    /// `UIAppFonts` in `Info.plist` loads it at launch and normally this finds it already there
    /// and does nothing. It exists for the one case where that is not enough — a render started
    /// from a code path whose bundle is not the app's, which is exactly what a test target is —
    /// because the failure mode is not a crash or a blank card. It is a card that looks *fine*
    /// and is in the wrong typeface, shared to a group chat, permanently.
    ///
    /// - Returns: whether the face is available. `false` means the card will be drawn in the
    ///   system face, which the caller logs rather than hides.
    @discardableResult
    static func registerDisplayFace() -> Bool {
        if isDisplayFaceAvailable { return true }
        guard let url = Copy.bundle.url(forResource: "BricolageGrotesque", withExtension: "ttf")
        else { return false }
        // `.process` rather than `.persistent`: the face belongs to this process for as long as
        // it runs, and nothing about a share card should outlive it on the system.
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return isDisplayFaceAvailable
    }

    /// Whether the bundled family resolves. Asked of the font system rather than of a flag, so a
    /// registration that silently failed is visible here rather than assumed away.
    static var isDisplayFaceAvailable: Bool {
        let descriptor = UIFontDescriptor(fontAttributes: [.family: displayFamily])
        return UIFont(descriptor: descriptor, size: 12).familyName == displayFamily
    }

    /// A font at a **literal** point size, for content rendered into an image rather than onto
    /// a screen.
    ///
    /// The share card is the only caller and `docs/10` §3 is the only reason this exists: the
    /// card's numerals are specified as 96pt and 112pt in the artifact's own space, and there is
    /// no token for either. It is safe to hand a raw size here — and unsafe anywhere else —
    /// because a PNG has no Dynamic Type: the reader's text-size setting is about their screen,
    /// and the artifact has already left it. Everything else on the card is a `TypeStyle` at a
    /// pinned `.large`, so this is one line of the design and not a way around the scale.
    ///
    /// The display face keeps its axes, including the optical size set at the drawn size, which
    /// is the whole reason a variable font is bundled (`docs/07` §3).
    static func fixed(
        _ face: TypeStyle.Face,
        size: CGFloat,
        weight: UIFont.Weight = .semibold,
        isTabular: Bool = true
    ) -> UIFont {
        let spec = TypeStyle.Spec(
            size: size, lineHeight: size, face: face, weight: weight,
            textStyle: .body, tracking: 0, isUppercase: false,
            maximumScale: nil, isTabular: isTabular
        )
        return switch face {
        case .display: displayFont(pointSize: size, spec: spec)
        case .body, .mono: baseFont(spec)
        }
    }

    /// The unscaled font for a style — the `.large` category's size, before Dynamic Type.
    private static func baseFont(_ spec: TypeStyle.Spec) -> UIFont {
        switch spec.face {
        case .display:
            displayFont(pointSize: spec.size, spec: spec)
        case .body:
            tabular(UIFont.systemFont(ofSize: spec.size, weight: spec.weight), if: spec.isTabular)
        case .mono:
            // SF Mono. Monospaced by construction, so its digits are already tabular; the
            // attribute is applied anyway, because "the face happens to be monospaced" and
            // "the numerals are pinned to one advance" are two different promises and only
            // one of them is the one `docs/07` §3 makes.
            tabular(UIFont.monospacedSystemFont(ofSize: spec.size, weight: spec.weight),
                    if: spec.isTabular)
        }
    }

    /// Bricolage Grotesque at a point size, with its three axes set.
    ///
    /// Falls back to the system face if the bundled font is missing — a missing resource must
    /// not be a crash on launch, and `TypographyTests` is what makes sure the fallback stays
    /// theoretical rather than becoming what ships.
    private static func displayFont(pointSize: CGFloat, spec: TypeStyle.Spec) -> UIFont {
        let descriptor = UIFontDescriptor(fontAttributes: [.family: displayFamily])
        guard UIFont(descriptor: descriptor, size: pointSize).familyName == displayFamily else {
            return tabular(UIFont.systemFont(ofSize: pointSize, weight: spec.weight),
                           if: spec.isTabular)
        }

        let probe = UIFont(descriptor: descriptor, size: pointSize)
        let variations: [Int: CGFloat] = [
            Axis.weight: clamped(displayWeight, to: Axis.weight, of: probe),
            // The widest cut the face has, whatever that is — `docs/07` §3's rule, read off
            // the font rather than transcribed from it.
            Axis.width: widest(Axis.width, of: probe) ?? displayWidth,
            Axis.opticalSize: clamped(pointSize, to: Axis.opticalSize, of: probe),
        ]
        let variationKey = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
        let varied = descriptor.addingAttributes([variationKey: variations])
        return tabular(UIFont(descriptor: varied, size: pointSize), if: spec.isTabular)
    }

    /// A variation value, clamped into the axis's own range. An axis the face does not have
    /// returns the value unchanged — setting an absent axis is a no-op either way.
    private static func clamped(_ value: CGFloat, to axis: Int, of font: UIFont) -> CGFloat {
        guard let range = range(of: axis, in: font) else { return value }
        return min(max(value, range.minimum), range.maximum)
    }

    /// The top of an axis, or `nil` if the face does not have it.
    private static func widest(_ axis: Int, of font: UIFont) -> CGFloat? {
        range(of: axis, in: font)?.maximum
    }

    private static func range(of axis: Int, in font: UIFont) -> (minimum: CGFloat, maximum: CGFloat)? {
        guard let axes = CTFontCopyVariationAxes(font as CTFont) as? [[CFString: Any]],
              let match = axes.first(where: {
                  ($0[kCTFontVariationAxisIdentifierKey] as? Int) == axis
              }),
              let minimum = match[kCTFontVariationAxisMinimumValueKey] as? CGFloat,
              let maximum = match[kCTFontVariationAxisMaximumValueKey] as? CGFloat
        else { return nil }
        return (minimum, maximum)
    }

    /// Pins the numerals to one advance width, so nothing moves sideways as a number changes.
    private static func tabular(_ font: UIFont, if isTabular: Bool) -> UIFont {
        guard isTabular else { return font }
        let descriptor = font.fontDescriptor.addingAttributes([
            .featureSettings: [[
                UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
            ]],
        ])
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }

    // MARK: - The countdown's two forms

    /// Which countdown form a Dynamic Type size gets (`docs/12` §1): coarse **above**
    /// `.accessibility2`, precise at or below it.
    static func countdownForm(for size: DynamicTypeSize) -> CountdownForm {
        size > .accessibility2 ? .coarse : .precise
    }

    // MARK: - Line height

    /// The leading a style asks for, scaled the same way its size was, so the ratio between
    /// them survives Dynamic Type.
    static func lineHeight(_ style: TypeStyle, for category: UIContentSizeCategory = .unspecified) -> CGFloat {
        let spec = style.spec
        let font = uiFont(style, for: category)
        return spec.lineHeight * (font.pointSize / spec.size)
    }
}

// MARK: - SwiftUI

/// Applies a `TypeStyle` — face, size, leading, tracking, and capitals — as one modifier.
///
/// It reads `dynamicTypeSize` from the environment rather than letting SwiftUI scale a
/// `Font` for us, because the display face's axes and its 1.6× ceiling are decisions
/// `Typography` has to make at a known size. That is also what makes a snapshot test at
/// `.accessibility5` render exactly what a device at `.accessibility5` renders.
private struct TypeStyleModifier: ViewModifier {
    let style: TypeStyle
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let category = UIContentSizeCategory(dynamicTypeSize)
        let font = Typography.uiFont(style, for: category)
        let spec = style.spec
        return content
            .font(Font(font))
            .tracking(spec.tracking * (font.pointSize / spec.size))
            .lineSpacing(max(0, Typography.lineHeight(style, for: category) - font.lineHeight))
            .textCase(spec.isUppercase ? .uppercase : nil)
    }
}

extension View {
    /// The only way a view in `Features/` sets type. `docs/07` §3 owns the scale; a feature
    /// file that writes a point size is a review failure (`CLAUDE.md` §4).
    func typeStyle(_ style: TypeStyle) -> some View {
        modifier(TypeStyleModifier(style: style))
    }
}

extension UIContentSizeCategory {
    /// SwiftUI's `DynamicTypeSize` → UIKit's category, which is what `UIFontMetrics` speaks.
    init(_ size: DynamicTypeSize) {
        self = switch size {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }
}
