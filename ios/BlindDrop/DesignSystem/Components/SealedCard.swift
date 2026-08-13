import SwiftUI

/// The caller's own song, sealed (`docs/07` §5).
///
/// `amberWash` fill, `amber` border, the artwork covered by the seal cover, the stamp at the
/// cover's lower-right. **This is the landed state.** `docs/09` §2 owns how it arrives, and
/// `SealAnimation` animates into exactly this — which is the point of drawing the end state here:
/// the animation has something to be a transition *to*, rather than being the only place the
/// sealed card exists.
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
    /// Where in the seal this card is. `.sealed` by default, because a card on `SealedScreen` has
    /// already arrived and **must not replay the animation underneath the sheet** (`docs/08` §3.2).
    /// `ConfirmScreen` is the one caller that drives it from `.unsealed`.
    var phase: SealPhase = .sealed
    /// `docs/09` §5. Passed in rather than read from the environment so a snapshot can render both
    /// paths' end states and compare them.
    var reducedMotion: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            SealedArtwork(
                track: track,
                groupInitial: groupInitial,
                phase: phase,
                reducedMotion: reducedMotion
            )
            // `docs/08` §4: the user's own title and artist **are** shown beneath the cover,
            // small — *"it is their song and hiding it from them is theatre, not security."*
            // Small is `bodyM` for both; the title keeps `ink` so the two lines are told apart
            // by more than being adjacent.
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(verbatim: track.title)
                    .typeStyle(.displayS)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: track.artist)
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.inkDim)
            }
        }
        // White, with the amber only in the border and in what is stamped on the cover. A card
        // washed amber edge to edge would make the whole screen amber, and the accent is meant
        // to be the *signal* on the screen rather than the screen itself.
        .cardSurface(border: Palette.amberEdge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Copy.A11y.sealed(title: track.title, artist: track.artist, remaining: remaining)
        )
        .accessibilityAddTraits([.isImage, .isStaticText])
    }
}

/// The artwork with the cover over it, and the stamp on the cover.
///
/// The artwork is still *there* — the seal hides it, it does not replace it, and that is the
/// difference between a lid and a placeholder. Split out of `SealedCard` because `ConfirmScreen`
/// seals a **280pt bare artwork** rather than a card: the same six moving parts, one of the two
/// places they are drawn, and no second copy of the geometry to drift.
struct SealedArtwork: View {
    let track: TrackDTO
    let groupInitial: String
    var phase: SealPhase = .sealed
    var reducedMotion: Bool = false
    /// The drawn size when it is not filling its container. `ConfirmScreen`'s 280pt (`docs/08`
    /// §3.2); the card's own artwork fills the card's width instead.
    var size: CGFloat = Layout.Artwork.confirm
    var fillsWidth: Bool = true

    var body: some View {
        ArtworkView(track, size: size, fillsWidth: fillsWidth)
            .seal(phase, as: .artwork, reducedMotion: reducedMotion)
            .overlay {
                // The height the cover travels is the artwork's own, read at layout time. The
                // `GeometryReader` measures once and is not consulted again while the seal runs —
                // nothing here changes size, so nothing re-measures (`docs/09` §2).
                GeometryReader { proxy in
                    cover
                        .frame(height: proxy.size.height)
                        .seal(phase, as: .cover(height: proxy.size.height), reducedMotion: reducedMotion)
                }
            }
            .overlay(alignment: .bottomTrailing) { stamp }
            .clipShape(RoundedRectangle(cornerRadius: Radius.artwork, style: .continuous))
    }

    /// A solid `amberWash` panel with an `amber` 1pt top edge (`docs/09` §2, phase B).
    ///
    /// Its shadow belongs to `SealEffect`, not here: it exists **only while the cover is moving**
    /// and resolves to zero on land, which is the app's one exception to *"never a drop shadow"*
    /// (`docs/07` §2).
    private var cover: some View {
        Palette.amberWash
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Palette.amber)
                    .frame(height: Stroke.border)
            }
    }

    /// The mark, and the single ring that leaves it (`docs/09` §2, phases D and E).
    private var stamp: some View {
        SealStamp(initial: groupInitial)
            .background {
                Circle()
                    .stroke(Palette.amber, lineWidth: Stroke.mark)
                    .seal(phase, as: .ring, reducedMotion: reducedMotion)
            }
            .seal(phase, as: .stamp, reducedMotion: reducedMotion)
            .padding(Space.xl)
    }
}

/// The seal mark (`docs/09` §2, phase D): a 56pt circular `amber` outline at `Stroke.mark`
/// enclosing the group's initial in the display face, with a hairline inner ring 4pt inside it.
///
/// **It lands off-axis by 4°.** A stamp that lands square reads as a UI element; one slightly
/// crooked reads as a physical act. `docs/09`: *"Do not 'fix' this."* The rotation lives in
/// `SealTimeline` so that the animation lands on the same angle the static card draws, rather than
/// two constants that have to be kept equal by hand.
struct SealStamp: View {
    let initial: String
    /// The stamp does not scale with Dynamic Type. It is a mark, not text — the letter inside it
    /// is a graphic, and growing the whole thing to 90pt at `.accessibility5` would cover the
    /// artwork it is stamped on. Its meaning is carried by the card's accessibility label.
    var diameter: CGFloat = SealStamp.diameter

    /// The stamp on a full-width cover.
    static let diameter: CGFloat = 56
    /// The stamp on a list thumbnail, where the full-size mark would be the whole thumbnail.
    static let compactDiameter: CGFloat = 30

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.amber, lineWidth: Stroke.mark)
            Circle()
                .stroke(Palette.amber, lineWidth: Stroke.border)
                .padding(Space.xs)
            Text(verbatim: initial.prefix(1).uppercased())
                .font(Font(Typography.fixed(.display, size: diameter * 0.46, weight: .bold)))
                .foregroundStyle(Palette.amber)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}
