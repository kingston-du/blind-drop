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
/// `standard` stacks its label unconditionally, which retires the old `isStacked` reflow: its two
/// `Text`s never share a row, so the accessibility-size failure that reflow existed to dodge
/// cannot occur. `prominent` does share a row, and answers the same hazard differently — see its
/// note.
struct CueBanner: View {
    /// Which of the strip's two readings a call site wants (`E41-04`, owner 2026-09-11).
    enum Density {
        /// Label over text. The cue **introduced** — the first surface in a night that names it.
        case standard
        /// A short label on the cue's own line, at the same size. The cue **recognised** rather
        /// than introduced. See `prominent(_:)`'s note.
        case prominent
    }

    let cue: CueDTO?
    var density: Density = .standard

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder var body: some View {
        if let cue {
            switch density {
            case .standard: standard(cue)
            case .prominent: prominent(cue)
            }
        } else {
            EmptyView()
        }
    }

    private func standard(_ cue: CueDTO) -> some View {
        strip {
            VStack(alignment: .leading, spacing: Space.xxs) {
                SectionLabel("round.cue.card.label")
                Text(verbatim: cue.text)
                    .typeStyle(.bodyLStrong)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The strip with its micro-label moved onto the line rather than above it.
    ///
    /// **It ran without a label at all for a day, and that was wrong** — not because the reader
    /// needs the cue introduced a third time (they do not; they have met it on the drop screen
    /// under an amber *"Tonight's cue"* and again in the flight's own header), but because of
    /// what an unlabelled strip *is*. A recessed rounded rectangle holding one left-aligned line
    /// with the row's spare width trailing it is the shape iOS uses for a search field. Sitting
    /// beside a close button, where a sheet puts its title, it asked two questions before it
    /// answered either: is that an input, and is that the song's name? The label is what settles
    /// them, and one word settles them as well as three.
    ///
    /// So the label is **inline and short**: `round.cue.label.short` — *"Cue"*, set as the same
    /// `.label` micro-type `standard` stacks, on the cue's own line. Inline because the row is
    /// already `Layout.minimumTouchTarget` tall for the close button beside it, so a label on
    /// that line costs the artwork nothing, where a stacked one costs it a whole row — which is
    /// the 64pt `standard` was rejected for here in the first place. Short because *"Tonight's
    /// cue"* at third sight is the chrome the no-label experiment was right to object to; the
    /// job left is naming the box, not introducing its contents.
    ///
    /// `.firstTextBaseline`, so an 11pt mono label and a 17pt body line sit on one baseline
    /// rather than on one centre, and `fixedSize` on the label so a three-character word can
    /// never be the thing that wraps — the cue absorbs the width, which is what it is for.
    ///
    /// **The line itself does not change — `bodyLStrong`, the same as `standard` above.** Two
    /// other sizes were tried
    /// and both were wrong in the same direction, which is why the type is worth pinning down
    /// here: `bodyS` made it a caption for a control that was not there, and `displayS` — the
    /// drop screen's size for the cue — made a 24pt Bricolage line the loudest thing on a screen
    /// whose subject is a 300pt album cover, competing with the ultramarine numeral for the eye.
    /// The cue is a condition the cards are read against; it is not the card.
    ///
    /// So this is not a third rendering of the cue. It is `standard` with its micro-label moved
    /// onto the line and shortened, at `standard`'s type, in `standard`'s material.
    /// `docs/18-CUES.md` §7 holds the placement.
    ///
    /// VoiceOver still hears the long form. The element speaks `round.cue.label`'s *"Tonight's
    /// cue:"* ahead of the text rather than the visible *"Cue"*, because a person who cannot see
    /// where the strip sits on the screen has none of the context the sighted reader is being
    /// trusted with — and the abbreviation is only defensible against that context.
    private func prominent(_ cue: CueDTO) -> some View {
        let label = SectionLabel(LocalizedStringKey(Self.prominentLabelKey))
        let text = Text(verbatim: cue.text)
            .typeStyle(.bodyLStrong)
            .foregroundStyle(Palette.ink)
            .fixedSize(horizontal: false, vertical: true)

        return strip(minHeight: Layout.minimumTouchTarget) {
            if Self.prominentStacksLabel(at: dynamicTypeSize) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    label
                    text
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    label.fixedSize()
                    text
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("round.cue.label") + Text(verbatim: " ") + Text(verbatim: cue.text))
    }

    /// **Above `.accessibility1` the label stops sharing the line.**
    ///
    /// Inline is right at reading sizes and wrong at accessibility ones, and the SE golden at
    /// `.accessibility5` is the proof: a label that cannot wrap — and it must not, a
    /// three-character word broken across lines is worse than anything it could save — takes
    /// ninety points off a three-hundred-point column, and the cue it was meant to clarify wraps
    /// into a ragged stack of one and two words hanging off its right. The label costs less than
    /// it destroys only while there is width to share.
    ///
    /// So above that boundary it goes back over the cue, the way `standard` always sets it. That
    /// is the same threshold `QuickPassScreen.isStacked` uses to move the whole strip under the
    /// close button, and deliberately so: at exactly the size the strip stops sharing its row
    /// with a button, the label stops sharing its line with the cue.
    static func prominentStacksLabel(at size: DynamicTypeSize) -> Bool {
        size.isAccessibilitySize
    }

    /// What `prominent`'s label costs the cue beside it — width when inline, height when stacked,
    /// never both.
    ///
    /// **The component owns this, not the screen that reserves space for it.** `QuickPassScreen`
    /// sizes its artwork from what the cue has left to wrap into, so it needs these numbers — and
    /// if it derived them itself, changing the label here would silently mis-size an album cover
    /// over there. Returning both costs from one call is what keeps the screen from having to
    /// know *which* of the two applies at a given size, which is the fact most likely to drift.
    /// `CueBannerTests` pins the pair to what is actually drawn.
    ///
    /// `.label` is `isUppercase` and tracked `+1.3` at its base size, and `TypeStyleModifier`
    /// scales that tracking with the font — so the string is measured uppercased, with the kern
    /// attribute the modifier will actually apply, at the category the strip renders at. Dropping
    /// the kern under-reads a three-character word by about four points, which is the margin that
    /// decides whether the last word of a 45-character cue wraps.
    static func prominentLabelCost(
        for size: DynamicTypeSize
    ) -> (width: CGFloat, height: CGFloat) {
        let category = UIContentSizeCategory(size)
        guard !prominentStacksLabel(at: size) else {
            return (0, Typography.lineHeight(.label, for: category) + Space.xxs)
        }
        return (prominentLabelWidth(for: category) + Space.sm, 0)
    }

    /// The drawn width of the inline label alone, tracking included. `prominentLabelCost` is what
    /// a layout should ask for; this is exposed for the test that checks the measurement itself.
    static func prominentLabelWidth(for category: UIContentSizeCategory = .unspecified) -> CGFloat {
        let style = TypeStyle.label
        let font = Typography.uiFont(style, for: category)
        let kern = style.spec.tracking * (font.pointSize / style.spec.size)
        let text = Copy.string(prominentLabelKey).uppercased()
        return ceil((text as NSString).size(withAttributes: [.font: font, .kern: kern]).width)
    }

    /// The one spelling of the key, so the rendered label and the measured one cannot diverge.
    private static let prominentLabelKey = "round.cue.label.short"

    /// The material both densities share, in one place so they cannot drift apart.
    ///
    /// - Parameter minHeight: a floor on the strip's height, applied **inside** the background so
    ///   the fill grows with it rather than the strip floating in a taller frame.
    ///
    ///   `prominent` passes `Layout.minimumTouchTarget`, and the reason is alignment rather than
    ///   touch: it shares a row with `CloseButton`, whose 44pt target centres a 17pt glyph 22pt
    ///   down, while an unconstrained one-line strip is 36pt tall and centres its text at 18pt.
    ///   Top-aligned, those two agree on their top edge and disagree by 3.7pt on everything a
    ///   reader actually looks at. Matching the target's height makes the button and the strip one
    ///   44pt block with one centre — and a cue long enough to wrap still grows downward from the
    ///   top they share, which is why this is a floor and not a fixed height.
    private func strip<Content: View>(
        minHeight: CGFloat? = nil,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Space.sm)
            .padding(.horizontal, Space.md)
            .frame(minHeight: minHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.artwork, style: .continuous)
                    .fill(Palette.paperSunk)
            )
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
