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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.artworkLoader) private var artworkLoader
    /// The action's width at rest, measured once so the collapse can be a **scale** rather than a
    /// frame — a width animation would re-lay-out the button on every frame of phase A, and
    /// `docs/09` §6 asserts the body count stays flat.
    @State private var actionWidth: CGFloat = 0

    private let accent = PhaseAccent.sealed

    var body: some View {
        VStack(spacing: Layout.blockGap) {
            HStack {
                CloseButton(action: close)
                Spacer(minLength: Space.none)
            }

            SealedArtwork(
                track: track,
                groupInitial: groupInitial,
                phase: animation.phase,
                reducedMotion: reduceMotion,
                size: Layout.Artwork.confirm,
                fillsWidth: false
            )

            metadata

            // One slot, two layers: the actions fading out and the footer fading in. A `ZStack`
            // rather than a swap, so nothing in the tree changes size as the seal runs.
            ZStack {
                actions
                footer
            }
        }
        .padding(.horizontal, Layout.screenInset)
        .padding(.vertical, Layout.blockGap)
        .frame(maxWidth: .infinity)
        .background(Palette.paper)
        .onDisappear { player.stop() }
    }

    private var metadata: some View {
        VStack(spacing: Space.sm) {
            Text(verbatim: track.title)
                .typeStyle(.displayM)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: track.artist)
                .typeStyle(.bodyL)
                .foregroundStyle(Palette.inkDim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // `docs/06` §7: a track with no preview gets **no control at all**. Not a disabled
            // one, not a placeholder, not an explanation.
            if track.previewURL != nil {
                PreviewControl(
                    isPlaying: player.playing == track.trackKey,
                    accent: accent,
                    action: { player.toggle(track) }
                )
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// **Seal it** / **Pick another**, and the line that appears when the server says no.
    private var actions: some View {
        VStack(spacing: Layout.itemGap) {
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

            SecondaryButton("confirm.another", action: back)
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
    private var footer: some View {
        Text(verbatim: Copy.format("sealed.status", revealTime))
            .typeStyle(.bodyL)
            .foregroundStyle(accent.text)
            .multilineTextAlignment(.center)
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
