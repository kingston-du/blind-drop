import SwiftUI

/// Tonight's cue, when there is one (`docs/18-CUES.md` §7).
///
/// One short line, identical for every member, that steers what people drop. It is **neutral
/// ink only** — never amber or ultramarine — because it appears on both the sealed and the
/// revealed sides of a round, so a semantic accent on it would be wrong on whichever phase it
/// is not currently colouring (`docs/18-CUES.md` §2). Absence is silent: when `cue` is `nil`
/// this renders `EmptyView()`, no placeholder, no "no cue tonight" line.
///
/// **A recessed strip, not a card and not a bare line.** It used to be one `bodyM` sentence on
/// the paper — *"Tonight's cue: a song you hate"* — which on Reveal sat at the same size and
/// nearly the same colour as the subhead two lines below it, and on Sealed dangled under the
/// chrome with nothing binding it to anything. A `CueCard` is the wrong fix: on those two phases
/// the white rounded rect *is* the content (the polaroid, the ranked rows), so a fourth one at
/// the top reads as the first item in the list rather than the brief over it.
///
/// So it takes the card's **structure** — micro-label over the cue, the same reading rhythm —
/// with a different **material**: `paperSunk` fill, no border, `Radius.artwork` rather than
/// `Radius.card`, and a tighter inset than `Layout.cardInset`. Nothing else in the app is
/// recessed-and-unbordered, which gives three legible tiers: sunk strip is the round's standing
/// condition, paper is the screen's own copy, a white card is an item. The recession is also what
/// lets it keep sitting *above* the headline — apparatus can, a runt sentence cannot.
///
/// Stacking the label unconditionally retires the old `isStacked` reflow: the two `Text`s never
/// share a row now, so the accessibility-size failure it existed to dodge cannot occur.
struct CueBanner: View {
    let cue: CueDTO?

    @ViewBuilder var body: some View {
        if let cue {
            VStack(alignment: .leading, spacing: Space.xxs) {
                SectionLabel("round.cue.card.label")
                Text(verbatim: cue.text)
                    .typeStyle(.bodyLStrong)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Space.sm)
            .padding(.horizontal, Space.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.artwork, style: .continuous)
                    .fill(Palette.hairline)
            )
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
///
/// **The dark hours are the exception to the exception**, and they take the defaults with them.
/// There the card is not a brief — the field is not up, and the cue it shows is the *finished*
/// round's (`SubmitScreen.closed`, `docs/18-CUES.md` §7). The amber carve-out was argued from
/// this card being the thing the screen is asking you to answer; nothing is being asked at
/// 3 a.m., so the label goes back to `inkDim` and names the night it belongs to instead.
struct CueCard: View {
    let cue: CueDTO
    /// What the card calls the cue. *"Tonight's cue"* by default, because that is what it is
    /// on the phase this card was built for.
    var label: LocalizedStringKey = "round.cue.card.label"
    /// The micro-label's colour — amber on the live drop screen, neutral wherever the card is
    /// pointing at a round that is over. See the note above.
    var labelColor: Color = Palette.amberText

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel(label, color: labelColor)
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
