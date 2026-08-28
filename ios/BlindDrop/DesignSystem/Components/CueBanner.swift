import SwiftUI

/// Tonight's cue, when there is one (`docs/18-CUES.md` §7).
///
/// One short line, identical for every member, that steers what people drop. It is **neutral
/// ink only** — never amber or ultramarine — because it appears on both the sealed and the
/// revealed sides of a round, so a semantic accent on it would be wrong on whichever phase it
/// is not currently colouring (`docs/18-CUES.md` §2). Absence is silent: when `cue` is `nil`
/// this renders `EmptyView()`, no placeholder, no "no cue tonight" line.
///
/// The label and the cue text read as one line — *"Tonight's cue: a song you hate."* The label
/// is `inkDim` apparatus, the cue text is the `ink` content it points at. At accessibility type
/// sizes they stack into two rows instead; see `isStacked`.
struct CueBanner: View {
    let cue: CueDTO?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Label beside cue becomes label above cue above `.accessibility1`, the same reflow
    /// `FlightCard` and `GroupScreen` make, decided from the type size and not a width check.
    ///
    /// Both `Text`s here are body styles, and `docs/07` §3 caps only the display face — so at
    /// `.accessibility5` on a narrow device the two of them share a row far too tight for
    /// either. The label does not truncate, it wraps *mid-word*: "Tonight'" on one line and
    /// "s cue:" on the next, beside a ragged second column. Giving each its own row at large
    /// type is the fix this codebase already settled on for that failure mode.
    private var isStacked: Bool { dynamicTypeSize >= .accessibility1 }

    @ViewBuilder var body: some View {
        if let cue {
            let label = Text("round.cue.label")
                .typeStyle(.bodyM)
                .foregroundStyle(Palette.inkDim)
            let text = Text(verbatim: cue.text)
                .typeStyle(.bodyM)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            Group {
                if isStacked {
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        label
                        text
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                        label
                        text
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        } else {
            EmptyView()
        }
    }
}
