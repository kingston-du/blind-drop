import SwiftUI

/// `docs/08` §3.2 — pushed within the search sheet. **This is the screen the seal happens on.**
///
/// ```
/// │  ✕                          │
/// │      ┌───────────────┐      │
/// │      │   artwork     │      │   280pt, Radius.artwork
/// │      └───────────────┘      │
/// │      Motion Sickness        │   displayM, ink, centred
/// │      Phoebe Bridgers        │   bodyL, inkDim
/// │      ▶︎ ──────────── 0:30    │   preview, absent if there is none
/// │  ┌───────────────────────┐  │
/// │  │       Seal it         │  │   PrimaryButton, amber
/// │  └───────────────────────┘  │
/// │        Pick another         │   SecondaryButton
/// ```
///
/// The order of operations is the whole point of the screen, and `docs/08` §3.2 states it twice:
///
/// > Tapping **Seal it** calls `PUT /rounds/current/submission`, and **on success** runs the seal
/// > animation … The seal animation never runs speculatively. It is a confirmation of a fact, and
/// > it must never have lied.
///
/// So: call, then decode, then *pre-decode the artwork* (`docs/09` §2 — an image decode mid-seal is
/// the most likely cause of a dropped frame), then animate, then dismiss onto an already-sealed
/// card. A failure returns the button to rest with an `alert` line and nothing is sealed.
struct ConfirmScreen: View {
    let track: TrackDTO
    let store: SubmitStore
    let player: PreviewPlayer
    let animation: SealAnimation
    /// The group's initial, for the stamp. The seal is the group's mark on the caller's song.
    let groupInitial: String
    /// The reveal hour in words, for phase F's line. The same sentence `SealedScreen` shows, so
    /// the dismissal reads as a continuation rather than a cut.
    let revealTime: String
    /// Called once the seal has landed, with the submission the **server** sealed.
    let sealed: (SubmissionDTO) -> Void
    let back: () -> Void
    let close: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.blindDropForcesReducedMotion) private var forceReduceMotion
    @Environment(\.artworkLoader) private var artworkLoader
    private var reduceMotion: Bool { systemReduceMotion || forceReduceMotion }
    /// The action's width at rest, measured once so the collapse can be a **scale** rather than a
    /// frame — a width animation would re-lay-out the button on every frame of phase A, and
    /// `docs/09` §6 asserts the body count stays flat.
    @State private var actionWidth: CGFloat = 0

    private let accent = PhaseAccent.sealed

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.blockGap) {
            header
            card
            note
            Spacer(minLength: Space.none)
            // One slot, two layers: the actions fading out and the footer fading in. A `ZStack`
            // rather than a swap, so nothing in the tree changes size as the seal runs.
            ZStack {
                actions
                sealedFooter
            }
        }
        .padding(.horizontal, Layout.screenInset)
        .padding(.vertical, Layout.blockGap)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.paper)
        .onDisappear { player.stop() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Space.md) {
            Text("confirm.title")
                .typeStyle(.bodyLStrong)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: Space.sm)
            CloseButton(action: close)
        }
    }

    /// The song, on one card: the artwork it will be sealed under, and what it is.
    ///
    /// One card rather than a stack of centred blocks, because the seal happens **to** this
    /// object — the cover slides down over the artwork and the stamp lands on it — and an
    /// animation that happens to a card needs the card to be a thing on the screen first.
    private var card: some View {
        VStack(alignment: .leading, spacing: Layout.itemGap) {
            SealedArtwork(
                track: track,
                groupInitial: groupInitial,
                phase: animation.phase,
                reducedMotion: reduceMotion,
                size: Layout.Artwork.confirm,
                fillsWidth: true
            )
            metadata
        }
        .cardSurface()
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(verbatim: track.title)
                .typeStyle(.displayS)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                Text(verbatim: track.artist)
                    .typeStyle(.bodyL)
                    .foregroundStyle(Palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // `docs/06` §7: a track with no preview gets **no control at all**. Not a
                // disabled one, not a placeholder, not an explanation.
                if track.previewURL != nil {
                    PreviewControl(
                        isPlaying: player.playing == track.trackKey,
                        accent: accent,
                        action: { player.toggle(track) }
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// What sealing costs, said once, before it happens.
    ///
    /// The square is a mark rather than an icon: it is the only amber graphic on the screen that
    /// is not the stamp, and a warning triangle here would be wrong — nothing is going wrong.
    private var note: some View {
        HStack(alignment: .top, spacing: Space.md) {
            RoundedRectangle(cornerRadius: Space.xxs, style: .continuous)
                .fill(accent.mark)
                .frame(width: Space.sm, height: Space.sm)
                .padding(.top, Space.xs)
            Text(verbatim: Copy.format("confirm.note", revealTime))
                .typeStyle(.bodyM)
                .foregroundStyle(accent.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// **Seal it** / **Pick another**, and the line that appears when the server says no.
    private var actions: some View {
        VStack(spacing: Space.sm) {
            PrimaryButton("confirm.action", accent: accent, isEnabled: !store.isSealing) {
                seal()
            }
            .background {
                // Measured at rest, and never during the seal: nothing here changes size once the
                // animation starts, so this reports once and is not consulted again.
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { actionWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, width in actionWidth = width }
                }
            }
            .seal(animation.phase, as: .action(width: actionWidth), reducedMotion: reduceMotion)

            OutlineButton("confirm.another", action: back)
                .seal(animation.phase, as: .action(width: actionWidth), reducedMotion: reduceMotion)

            if let key = store.sealErrorKey {
                Text(verbatim: Copy.string(key))
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.alert)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Phase F: *"Sealed until 8:00."* arriving where the buttons were.
    ///
    /// The words are the sealed screen's, deliberately: this is the same sentence the user is about
    /// to land on, so the dismissal is a continuation rather than a cut.
    private var sealedFooter: some View {
        Text(verbatim: Copy.format("sealed.status", revealTime))
            .typeStyle(.bodyL)
            .foregroundStyle(accent.text)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .seal(animation.phase, as: .footer, reducedMotion: reduceMotion)
    }

    /// Seal, and only then animate.
    private func seal() {
        Task {
            guard let submission = await store.seal(track) else { return }

            // `docs/09` §2: *"Pre-decode the artwork before the animation begins."* The loader
            // answers instantly if the image is already in memory, which it usually is — this
            // screen has been showing it at 280pt since it appeared.
            await preDecodeArtwork()

            player.stop()
            await animation.run(reducedMotion: reduceMotion)
            // `docs/12` §2: *"The seal posts `a11y.seal.done` after the animation."*
            AccessibilityNotification.Announcement(Copy.string("a11y.seal.done")).post()
            sealed(submission)
        }
    }

    private func preDecodeArtwork() async {
        guard let url = ArtworkView.resolvedURL(
            template: track.artworkURL,
            points: Layout.Artwork.confirm,
            scale: UITraitCollection.current.displayScale
        ) else { return }
        _ = await artworkLoader.image(for: url)
    }
}
