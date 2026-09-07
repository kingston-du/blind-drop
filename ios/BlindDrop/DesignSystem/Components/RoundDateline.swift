import SwiftUI

/// *When* the round is — *"Saturday, September 5"*.
///
/// One line, and it has two homes rather than one. On the phases that do not scroll it rides in
/// `RoundHeader`'s pinned second row beside the phase badge, where *when the round is* and *what
/// it is doing* read as a single thought. On the two that scroll it is the eyebrow over the
/// screen's own headline, inside the scroll, because there the badge is `EmptyView` and a pinned
/// row holding one short date is chrome charging rent for a fact that never changes — see
/// `RoundDTO.Phase.scrollsItsOwnDate`.
///
/// Extracted so the two homes cannot drift: same `caption`/`inkDim` treatment — apparatus, not
/// content — and, more importantly, the same `round.dateHeadline` identifier on both. Splitting the
/// treatment per home is how the identifier ends up existing on only the phases that still pin the
/// row, which is a thing `FullLoopUITests` would not have noticed: its one assertion on
/// `round.dateHeadline` runs against `open_nosub`, a phase that never moved.
struct RoundDateline: View {
    /// The date as drawn. `RoundHeader` may hand over the abbreviated form when its row has to
    /// fit; the scrolled homes always have a row to themselves and pass the full one.
    let headline: String
    /// The date as **read aloud**, when that differs from what is drawn. Abbreviating is a way of
    /// fitting a column, and VoiceOver has no column to fit — *"Tue, Sep 1"* spoken is worse than
    /// what it replaced, for no gain at all.
    var spoken: String?

    var body: some View {
        Text(verbatim: headline)
            .typeStyle(.caption)
            .foregroundStyle(Palette.inkDim)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(Text(verbatim: spoken ?? headline))
            .accessibilityIdentifier("round.dateHeadline")
    }
}
