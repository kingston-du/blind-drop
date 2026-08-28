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
/// is `inkDim` apparatus, the cue text is the `ink` content it points at.
struct CueBanner: View {
    let cue: CueDTO?

    @ViewBuilder var body: some View {
        if let cue {
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Text("round.cue.label")
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.inkDim)
                Text(verbatim: cue.text)
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        } else {
            EmptyView()
        }
    }
}
