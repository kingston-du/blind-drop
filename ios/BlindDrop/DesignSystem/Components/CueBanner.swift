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

/// Tonight's cue on the **drop screen**, as its own card between the subhead and the field.
///
/// `CueBanner` is the cue everywhere else — one line, neutral, riding above whichever phase
/// screen is up. This is the one place it is the *brief* rather than a fact about the round:
/// the drop screen's entire job is to answer it, and the answer is typed into the field
/// immediately below. So it stops being a line of chrome above the screen and becomes the last
/// thing read before the field, in the card that separates it from both.
///
/// **This one is amber, and that is a real exception.** `docs/18-CUES.md` §2 rules the cue
/// neutral ink on every surface, because the banner appears on both the sealed and the revealed
/// side of a round and a semantic accent would be wrong on whichever phase it was not colouring.
/// That reasoning is about a *shared* rendering, and this card is not one — it exists only on
/// the drop screen, which is amber from the badge down, and every other phase keeps the neutral
/// banner unchanged (including Sealed, which sits one tap away). The amber is on the micro-label
/// only; the cue text itself stays `ink`, because the cue is content and the label is apparatus.
struct CueCard: View {
    let cue: CueDTO

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel("round.cue.card.label", color: Palette.amberText)
            Text(verbatim: cue.text)
                .typeStyle(.displayS)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Layout.cardInset)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Palette.edge, lineWidth: Stroke.border)
        )
        // One stop, read as one sentence — the label is what the text is, not a second item.
        .accessibilityElement(children: .combine)
    }
}
