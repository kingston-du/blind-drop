import SwiftUI

/// The caller's own song, sealed (`docs/07` §5).
///
/// `amberWash` fill, `amberDeep` border, the artwork covered by the seal cover, the stamp at the
/// cover's lower-right. **This is the landed state.** `docs/09` §2 owns how it arrives, and
/// `E10-04` animates into exactly this — which is the point of drawing the end state here: the
/// animation has something to be a transition *to*, rather than being the only place the sealed
/// card exists.
///
/// It announces itself as one thing (`docs/12` §2: `.image` + `.staticText`, `a11y.sealed`).
/// Nothing on it is interactive; **Replace song** is the screen's, not the card's.
struct SealedCard: View {
    let track: TrackDTO
    /// The group's initial, printed in the stamp.
    let groupInitial: String
    /// The countdown to the reveal, already in words — the card announces *"Reveal in %@"* and
    /// the words for a duration belong to `Copy`, not to a second formatter down here.
    let remaining: String
    /// How much of the artwork the cover has taken. 1 is sealed; `E10-04` drives it from 0.
    var coverage: Double = 1

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            sealedArtwork
            // `docs/08` §4: the user's own title and artist **are** shown beneath the cover,
            // small — *"it is their song and hiding it from them is theatre, not security."*
            // Small is `bodyM` for both; the title keeps `ink` so the two lines are told apart
            // by more than being adjacent.
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(verbatim: track.title)
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.ink)
                Text(verbatim: track.artist)
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.inkDim)
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Palette.amberWash)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Palette.amberDeep, lineWidth: Stroke.border)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Copy.A11y.sealed(title: track.title, artist: track.artist, remaining: remaining)
        )
        .accessibilityAddTraits([.isImage, .isStaticText])
    }

    /// The artwork with the cover over it. The artwork is still *there* — the seal hides it, it
    /// does not replace it, and that is the difference between a lid and a placeholder.
    private var sealedArtwork: some View {
        ArtworkView(track, size: Layout.Artwork.confirm, fillsWidth: true)
            .overlay(alignment: .top) {
                GeometryReader { proxy in
                    cover
                        .frame(height: proxy.size.height * coverage)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                SealStamp(initial: groupInitial)
                    .padding(Space.xl)
                    .opacity(coverage >= 1 ? 1 : 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.artwork, style: .continuous))
    }

    /// A solid `amberWash` panel with an `amberDeep` 1pt top edge (`docs/09` §2, phase B). No
    /// shadow: the shadow exists **only while the cover is moving**, and here it has landed.
    private var cover: some View {
        Palette.amberWash
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Palette.amberDeep)
                    .frame(height: Stroke.border)
            }
    }
}

/// The seal mark (`docs/09` §2, phase D): a 56pt circular `amberDeep` outline at `Stroke.mark`
/// enclosing the group's initial in the display face, with a hairline inner ring 4pt inside it.
///
/// **It lands off-axis by 4°.** A stamp that lands square reads as a UI element; one slightly
/// crooked reads as a physical act. `docs/09`: *"Do not 'fix' this."*
struct SealStamp: View {
    let initial: String
    /// The stamp does not scale with Dynamic Type. It is a mark, not text — the letter inside it
    /// is a graphic, and growing the whole thing to 90pt at `.accessibility5` would cover the
    /// artwork it is stamped on. Its meaning is carried by the card's accessibility label.
    private let diameter: CGFloat = 56

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.amberDeep, lineWidth: Stroke.mark)
            Circle()
                .stroke(Palette.amberDeep, lineWidth: 1)
                .padding(Space.xs)
            Text(verbatim: initial.prefix(1).uppercased())
                .font(Font(Typography.uiFont(.displayM, for: .large)))
                .foregroundStyle(Palette.amberDeep)
        }
        .frame(width: diameter, height: diameter)
        .rotationEffect(.degrees(-4))
        .accessibilityHidden(true)
    }
}
