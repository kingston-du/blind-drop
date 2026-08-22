import SwiftUI

/// The open round, after the caller has dropped: their song under a cover, and a clock.
///
/// The whole screen is one fact and one number. There is nothing here about anybody else —
/// no count, no *waiting on*, no sense of whether the caller was early or last. The line under
/// the countdown is the only nod to the others in the group, and it is deliberately unfalsifiable:
/// it says nothing that could be true of one night and false of another.
struct SealedScreen: View {
    let context: RoundContext
    let submission: SubmissionDTO
    let timer: CountdownTimer
    /// Whether this song replaced an earlier one in this round. Replacing is *"never penalised,
    /// never announced, and the replaced-song count is never displayed"* (`docs/08` §4) — what it
    /// changes is one line of the caller's own copy, and nothing anybody else can ever see.
    var didReplace = false
    let replace: () -> Void
    /// The 30-second preview (`Core/Audio/PreviewPlayer.swift`). `nil` in every golden, which is
    /// what keeps a snapshot silent and keeps `RevealScreen`/`SearchSheet`'s "one at a time" rule
    /// intact when this screen shares the instance those already play through (`E28-04`).
    var player: PreviewPlayer? = nil

    @Environment(\.scenePhase) private var scenePhase
    /// **Hold to peek** (`docs/08` §4, `E22-01`): `true` for exactly as long as a finger is down.
    /// This screen owns the bit rather than `SealedCard`, because it also has to be able to clear
    /// it from events the card cannot see on its own — leaving the screen, the app backgrounding,
    /// the switcher appearing. The initialiser's `isPeekingForSnapshot` is the one way a test
    /// seeds this to `true` without a live gesture to drive it.
    @State private var isPeeking: Bool
    /// The deferred preview stop from a release (`reseal()`). Kept so a fast re-hold can cancel
    /// it before it fires — without this, the release's one-turn-later pause would cut short the
    /// very next hold's playback.
    @State private var pendingStop: Task<Void, Never>?

    private let accent = PhaseAccent.sealed

    init(
        context: RoundContext,
        submission: SubmissionDTO,
        timer: CountdownTimer,
        didReplace: Bool = false,
        replace: @escaping () -> Void,
        player: PreviewPlayer? = nil,
        isPeekingForSnapshot: Bool = false
    ) {
        self.context = context
        self.submission = submission
        self.timer = timer
        self.didReplace = didReplace
        self.replace = replace
        self.player = player
        _isPeeking = State(initialValue: isPeekingForSnapshot)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            VStack(alignment: .leading, spacing: Layout.itemGap) {
                SealedCard(
                    track: submission.track,
                    groupInitial: context.groupInitial,
                    remaining: Copy.countdown(timer.display),
                    isPeeking: isPeeking,
                    // A press begins in the ordinary way; a release goes through `reseal()`, the
                    // same no-animation path every other way a hold ends uses, so a release is
                    // never the one that behaves differently.
                    onHoldChange: { holding in
                        if holding {
                            // A release just before this re-hold queued a one-turn-later pause.
                            // Cancel it: the audio is still playing (it was never actually
                            // stopped), and the hold this finger is now starting owns it.
                            pendingStop?.cancel()
                            pendingStop = nil
                            isPeeking = true
                            // `E28-04`: the caller's own preview, for exactly as long as the
                            // hold lasts. `toggle` already no-ops a track with no `preview_url`
                            // (`docs/06` §7) — a peek on those stays silent, same as before.
                            if player?.playing != submission.track.trackKey {
                                player?.toggle(submission.track)
                            }
                        } else {
                            reseal()
                        }
                    }
                )
                // The cover's upper-right is empty — the stamp lands lower-right (`docs/09` §2)
                // — so the one compact service menu belongs there. It stays outside
                // `SealedCard`, whose contents are deliberately one VoiceOver element.
                .overlay(alignment: .topTrailing) {
                    if TrackLinkDestination.appleMusic(track: submission.track) != nil
                        || TrackLinkDestination.spotify(track: submission.track) != nil {
                        // `SealedCard` insets its artwork by `Layout.cardInset` (`E28-04`: moved
                        // up and right off that plain inset, which crowded the seal stamp's own
                        // 8pt corner margin more than it needed to).
                        TrackUtilityMenu(track: submission.track, color: accent.text)
                            .padding(.top, Layout.cardInset)
                            .padding(.trailing, Layout.cardInset)
                    }
                }
                status
            }
            countdown
            Spacer(minLength: Space.none)
            // Reopens search. A replacement re-runs the seal in the sheet, which is why this is
            // a plain callback and not something this screen animates.
            OutlineButton("sealed.replace", action: replace)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // A peek that survives the app going to the background is a screenshot in the app
        // switcher with the song in it (`E22-01`). `scenePhase` is the one signal every one of
        // those failure modes shares — the switcher appearing, backgrounding, a call arriving —
        // because each of them leaves it something other than `.active`. Leaving this screen at
        // all (a phase change under it, the header menu pushing a route) is the other way, which
        // `scenePhase` cannot see and `.onDisappear` can. Both go through `reseal()`, which forces
        // no-animation explicitly rather than relying on nothing nearby happening to animate:
        // this is the one bit in the app that must never be caught inside someone else's
        // `withAnimation`.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { reseal() }
        }
        .onDisappear { reseal() }
    }

    /// Puts the cover back down and hides the metadata again, **immediately** — `docs/08` §4: *"an
    /// animated close is a few frames of the answer, which is the thing being prevented."*
    /// `Transaction.disablesAnimations` rather than a plain assignment, so this is true regardless
    /// of whatever transaction happens to be open when one of `reseal()`'s callers fires.
    private func reseal() {
        guard isPeeking else { return }
        // The cover comes back down **before** the audio stops. `stop()` hands the audio session
        // back to other apps with `notifyOthersOnDeactivation`, which blocks the main actor; if
        // it ran first, the single-frame reseal `docs/08` §4 requires would wait on that. Defer
        // the pause one turn so the seal is never the thing that lags — the audio may take a
        // moment to stop, the cover must not.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { isPeeking = false }
        // Capture the player and the track as locals, not `self`: the `Task` is `@Sendable` and
        // `self` is a `View` — the pause only needs the one player instance and the one track.
        let player = self.player
        let track = submission.track
        pendingStop = Task { @MainActor in
            // A re-hold cancels this task, but cancellation is cooperative — the body still
            // runs — so the guard is what actually keeps a cancelled pause from firing.
            guard !Task.isCancelled else { return }
            if player?.playing == track.trackKey {
                player?.toggle(track)
            }
        }
    }

    /// *"Sealed until 8:00."*, or *"Sealed again."* after a replacement (`docs/11`).
    ///
    /// The second line is the whole of what a replacement does to the interface. It drops the
    /// hour, which is not a loss: the countdown directly under it is counting to exactly that
    /// hour, and the sentence a person wants after replacing is the one that says the new song
    /// is in.
    private var status: some View {
        Text(verbatim: didReplace
             ? Copy.string("sealed.replaced")
             : Copy.format("sealed.status", context.revealTime))
            .typeStyle(.bodyM)
            .foregroundStyle(accent.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The number the screen is really about, centred, with the word for what it counts to above
    /// it and the one line about everybody else beneath.
    private var countdown: some View {
        VStack(spacing: Space.sm) {
            SectionLabel("sealed.opens.label")
            CountdownView(
                timer: timer,
                deadline: context.round.revealsAt,
                accent: accent,
                announces: .reveal
            )
            Text("sealed.company")
                .typeStyle(.bodyS)
                .foregroundStyle(Palette.inkDim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.xs)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
