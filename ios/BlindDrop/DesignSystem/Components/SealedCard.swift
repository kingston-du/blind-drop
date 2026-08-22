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
/// `Replace song` is still the screen's, not the card's — but the card is no longer a pure
/// picture. **Hold to peek** (`docs/08` §4, `E22-01`) lives here, because it is a hold on
/// *exactly* the region that used to show the title and artist plainly: this is one over a
/// shoulder, and the cover reads better when it is actually covering something. `isPeeking`
/// governs both the cover's own opacity and whether that region shows the song or the prompt;
/// `SealedScreen` is what turns a finger into that bit, because it also has to be able to clear
/// it from events this card cannot see — the app backgrounding, the switcher appearing, a call
/// arriving. VoiceOver needs none of this: `a11y.sealed` below announces the title and artist
/// regardless of `isPeeking`, which is the non-gesture path `docs/12` §5 requires, and a normal
/// touch simply cannot reach it while VoiceOver is running — the OS routes the touch to VoiceOver
/// first, and focusing the card is all it takes to hear the same words this hold shows.
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
    /// Whether a finger is currently down on **Hold to peek**. `false` — hidden — by default:
    /// title, artist and artwork all wait for a hold (`docs/08` §4, `E22-01`).
    var isPeeking: Bool = false
    /// Fires the instant a hold on **Hold to peek** begins or ends — including a drag off the
    /// control, which ends it the same as a lift. A plain callback, not owned state: the bit this
    /// drives has to survive being cleared by events that never touch this view.
    var onHoldChange: (Bool) -> Void = { _ in }
    /// Latches once a single continuous touch has drifted past the target and ended the hold —
    /// so wandering back within the radius before lifting does not reopen it. `docs/08` §4 lists
    /// "drag out" alongside release as one of the ways a hold **ends**, not a boundary a finger
    /// can cross back and forth across; without this, `onChanged` fires on every sample, and a
    /// finger hovering near the edge flickers the reveal open and shut. Reset only by `onEnded`,
    /// which is the one signal that a fresh touch-down is what comes next.
    @State private var hasLeftTarget = false
    /// The card's own measured size, so **the whole card is the hold target** (`E28-04`) —
    /// not just the metadata strip beneath the artwork. "Drag off the control" then means what
    /// it says: past the card's own edge, measured against where the touch actually started
    /// rather than a fixed radius that made sense for a 44pt strip and nowhere near covered an
    /// artwork the width of the screen.
    @State private var cardSize: CGSize = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            SealedArtwork(
                track: track,
                groupInitial: groupInitial,
                phase: phase,
                reducedMotion: reducedMotion,
                isPeeking: isPeeking
            )
            peekableMetadata
        }
        // White, with the amber only in the border and in what is stamped on the cover. A card
        // washed amber edge to edge would make the whole screen amber, and the accent is meant
        // to be the *signal* on the screen rather than the screen itself.
        .cardSurface(border: Palette.amberEdge)
        .contentShape(Rectangle())
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { cardSize = proxy.size }
                    .onChange(of: proxy.size) { _, size in cardSize = size }
            }
        }
        // A raw `DragGesture` rather than `onLongPressGesture`: reveals **on touch-down**, with
        // no minimum duration to wait out — `docs/08` §4 says "exactly as long as a finger is
        // down", not "as long as a finger is down past a threshold". The bound is the card's own
        // measured rectangle, not the finger's travelled distance (`E28-04`) — a hold that
        // wanders inside a card the width of the screen is not a drag off it, and one that
        // crosses the edge is, which distance-from-start could not tell apart on a target this
        // size.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard !hasLeftTarget else { return }
                    let withinCard = cardSize == .zero
                        || (0...cardSize.width).contains(value.location.x)
                        && (0...cardSize.height).contains(value.location.y)
                    if withinCard {
                        onHoldChange(true)
                    } else {
                        hasLeftTarget = true
                        onHoldChange(false)
                    }
                }
                .onEnded { _ in
                    hasLeftTarget = false
                    onHoldChange(false)
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Copy.A11y.sealed(title: track.title, artist: track.artist, remaining: remaining)
        )
        .accessibilityAddTraits([.isImage, .isStaticText])
    }

    /// `docs/08` §4: held, the title and artist show plainly, small, in `inkDim` — never a leak,
    /// since it is the caller's own song, but no longer drawn for anyone glancing at the screen.
    /// Hidden, this exact region reads **Hold to peek**.
    ///
    /// **Both crossfade in place** (`E28-04`) rather than swapping via `if`, which is what let
    /// this snap: a view SwiftUI destroys and recreates has nothing for `.animation` to
    /// interpolate between, whatever curve is attached to it. Stacking them and animating
    /// opacity is the same fix `ResolvedAnswer` already relies on for the results screen's own
    /// arrivals. The one `.animation` modifier is what SealedScreen's `reseal()` then silences
    /// on every closing path — a `disablesAnimations` transaction overrides an explicit
    /// modifier exactly as it overrides `withAnimation`, so opening still gets `Motion.Peek` and
    /// closing still gets nothing, from the same state change and the same view.
    private var peekableMetadata: some View {
        ZStack(alignment: .leading) {
            Text("sealed.peek")
                .typeStyle(.bodyM)
                .foregroundStyle(Palette.inkDim)
                .opacity(isPeeking ? 0 : 1)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(verbatim: track.title)
                    .typeStyle(.displayS)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: track.artist)
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.inkDim)
            }
            .opacity(isPeeking ? 1 : 0)
        }
        .frame(maxWidth: .infinity, minHeight: Layout.minimumTouchTarget, alignment: .leading)
        .animation(reducedMotion ? Motion.Peek.reduced : Motion.Peek.animation, value: isPeeking)
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
    /// While `true`, the cover gets out of the way of the artwork beneath it (`docs/08` §4,
    /// `E22-01`). `ConfirmScreen` never sets this — it shows the song plainly, before there is
    /// anything sealed to peek through, and dismisses the instant the seal itself lands.
    var isPeeking: Bool = false

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
                        // The one opacity the seal timeline does not own. It multiplies onto
                        // `SealEffect`'s own `coverOpacity` (1 at rest) rather than replacing it,
                        // so nothing here has to know whether a seal ever ran.
                        //
                        // **`E28-04`: the explicit `.animation` below is safe on the close path
                        // too**, despite opening now animating — `SealedCard`'s hold ends only
                        // through `SealedScreen.reseal()`, which wraps the assignment in a
                        // `Transaction` with `disablesAnimations = true`. That flag overrides an
                        // explicit modifier exactly as it overrides `withAnimation`, so a release
                        // still lands in the same single frame this comment used to guarantee by
                        // there being no animation attached at all; only the open — a plain
                        // assignment outside any transaction — actually animates.
                        .opacity(isPeeking ? 0 : 1)
                        .animation(reducedMotion ? Motion.Peek.reduced : Motion.Peek.animation, value: isPeeking)
                }
            }
            // The stamp is part of the cover, not of the artwork beneath it — a peek removes the
            // cover, so it removes the stamp with it. It fades on the same `Motion.Peek` curve
            // the cover does, and `reseal()`'s no-animation transaction snaps it back just as
            // instantly on release.
            .overlay(alignment: .bottomTrailing) {
                stamp
                    .opacity(isPeeking ? 0 : 1)
                    .animation(reducedMotion ? Motion.Peek.reduced : Motion.Peek.animation, value: isPeeking)
            }
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
