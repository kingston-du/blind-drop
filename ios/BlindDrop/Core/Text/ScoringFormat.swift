import Foundation

/// Rates, as a person reads them.
///
/// **The one place a formatting bug becomes a product bug.** `docs/04` §4 sends every rate as a
/// decimal in `0…1` and lets the client format it, and `nil` means *not applicable*, never
/// *zero*:
///
/// > *"The client must render `null` ear as '—', not '0%'. Getting this wrong turns 'you sat
/// > out' into 'you scored nothing', which is the one judgement the product refuses to make."*
///
/// So the `nil` case is the whole reason this type exists. A screen that reached for
/// `String(format:)` on an optional would have to remember the rule at every call site; here it
/// is remembered once, by a function whose input is optional and whose output for `nil` is a
/// dash. `ScoringFormatTests` pins both the dash and the rounding.
///
/// It is not in `DesignSystem/` because it is not copy — a percentage is a number format, and
/// there is nothing in `86%` for a translator to translate. `Foundation`'s own percent style is
/// what renders it, so a locale that writes `% 86` gets `% 86`.
enum ScoringFormat {

    /// What a rate that does not apply looks like. An em dash — a rate that is absent is not a
    /// rate that is low, and the two must not be able to look alike (`docs/08` §7.2).
    static let unavailable = "—"

    /// A rate as a whole-number percentage, or the dash.
    ///
    /// - Parameter rate: `0…1`, or `nil` for *not applicable*.
    static func percent(_ rate: Double?) -> String {
        guard let rate else { return unavailable }
        // Formatted from the rounded whole number rather than by asking the percent style for
        // zero fraction digits: the two agree on 0.857 and disagree on the halves, and the
        // number a label prints has to be the number `a11y.readability` announces.
        return (Double(percentValue(rate)) / 100).formatted(
            .percent.precision(.fractionLength(0))
        )
    }

    /// The same number, as an integer — what `a11y.readability`'s `%lld` takes (`docs/12` §2).
    ///
    /// Clamped, because a rate arriving outside `0…1` is a bug that should not become a
    /// meter drawn off the end of its track or a label reading `140%`.
    static func percentValue(_ rate: Double) -> Int {
        Int((min(1, max(0, rate)) * 100).rounded())
    }
}
