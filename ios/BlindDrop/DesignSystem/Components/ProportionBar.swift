import SwiftUI

/// How much of a whole one part is, drawn as a filled track with the raw count beside it.
///
/// It is used for one thing: how many of the people who could have placed a song did.
/// **Colour is never the only signal** (`docs/12` §3) — the count is printed at the end of the
/// bar in the monospaced face, so the bar is a picture of a number that is also written down.
struct ProportionBar: View {
    /// How many got it.
    let part: Int
    /// How many could have.
    let whole: Int
    let accent: PhaseAccent
    /// The sentence the row announces. Built by the caller from `Copy`, because *"nobody got
    /// it"* and *"4 of 7 got it"* are different sentences and the choice between them is copy.
    let announcement: String

    private var fraction: Double {
        guard whole > 0 else { return 0 }
        return min(1, max(0, Double(part) / Double(whole)))
    }

    private let trackHeight: CGFloat = 9

    var body: some View {
        HStack(spacing: Space.md) {
            track
            Text(verbatim: Copy.format("results.card.tally", part, whole))
                .typeStyle(.monoS)
                .foregroundStyle(part > 0 ? accent.text : Palette.inkDim)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: announcement))
        .accessibilityAddTraits(.isStaticText)
    }

    private var track: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track)
                Capsule()
                    .fill(accent.fill)
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: trackHeight)
        .frame(maxWidth: .infinity)
    }
}
