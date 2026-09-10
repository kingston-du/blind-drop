import SwiftUI

/// The open round, after the caller has dropped: their song under a cover, and a clock.
///
/// **Four things, and the same four whichever night it is**: the cue, the card, the clock, the way
/// out. The card is the flexible one — the cover is square-to-fit and takes whatever height the
/// column has left — so anything that comes and goes above or below it comes out of the artwork,
/// and the same phone draws a different-sized cover from one moment to the next. That is why
/// nothing here is conditional. *"Sealed again."* used to appear under the card after a
/// replacement and took 24pt of cover width with it, which read as the card resizing under a
/// change that is meant to be invisible (owner, 2026-09-06). The replacement already announces
/// itself the only way it should: the seal runs again over the new song on the way back here.
///
/// The whole screen is one fact and one number. There is nothing here about anybody else —
/// no count, no *waiting on*, no sense of whether the caller was early or last. The line under
/// the countdown is the only nod to the others in the group, and it is deliberately unfalsifiable:
/// it says nothing that could be true of one night and false of another.
struct SealedScreen: View {
    let context: RoundContext
    let submission: SubmissionDTO
    let timer: CountdownTimer
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
        replace: @escaping () -> Void,
        player: PreviewPlayer? = nil,
        isPeekingForSnapshot: Bool = false
    ) {
        self.context = context
        self.submission = submission
        self.timer = timer
        self.replace = replace
        self.player = player
        _isPeeking = State(initialValue: isPeekingForSnapshot)
    }

    var body: some View {
        // **`Space.sm`, not `Space.xl`, and the card gets the difference.** The cover is the one
        // flexible thing on this screen — square-to-fit — so every point spent anywhere above or
        // below it comes straight out of the artwork. Two `Space.xl` gaps around the spacer put
        // 40pt of nothing between the countdown and **Replace song** while the cover sat 45pt
        // short of the card it lives in. The countdown keeps its old 20pt above it via its own
        // `.padding(.top)`; what closed up is the run to the button, which had the most air and
        // the least to say (owner, 2026-09-05).
        VStack(alignment: .leading, spacing: Space.sm) {
            SealedCard(
                track: submission.track,
                groupInitial: context.groupInitial,
                remaining: Copy.countdown(timer.display),
                // The cover's upper-right is empty — the stamp lands lower-right (`docs/09`
                // §2) — so the one compact service menu belongs there. It is the card's own
                // now rather than an overlay this screen hangs off it: only the card knows
                // where its artwork actually ends. See `SealedCard.linksMenu`.
                menuColor: accent.text,
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
            // Two equal spacers centre the countdown in the gap between the card and **Replace
            // song**, instead of hugging the card and leaving all the free space for the run down
            // to the button. The `.padding(.top)` below is unchanged — the countdown keeps its own
            // breathing room, and only its position in the gap moves (owner, 2026-09-10).
            Spacer(minLength: Space.none)
            countdown
                .padding(.top, Space.md)
            Spacer(minLength: Space.none)
            // Reopens search. A replacement re-runs the seal in the sheet, which is why this is
            // a plain callback and not something this screen animates.
            OutlineButton("sealed.replace", action: replace)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // **Nothing on this screen has a keyboard, so nothing on it moves for one.**
        //
        // A keyboard raised anywhere in the window insets this hierarchy too, and the one place
        // that happens is the replacement sheet's search field — presented *over* this screen,
        // which keeps laying out underneath it. The cover is square-to-fit and takes whatever
        // height the column has left (see the note on `body`), so a bottom inset arriving from
        // a field this screen does not own resized the artwork behind the sheet; dismissing the
        // sheet then played that resize back as an animation, on a card whose whole contract is
        // that it does not move. There is no text input here and never will be, so the keyboard
        // region is simply not this screen's to react to.
        .ignoresSafeArea(.keyboard, edges: .bottom)
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

    /// The number the screen is really about, centred, with the word for what it counts to above
    /// it.
    ///
    /// **`sealed.company` used to sit beneath it** — *"Come back for the reveal to see today's
    /// drops."* — and it is gone (owner, 2026-09-05). It said what the badge, the label and the
    /// number above it already say three times over, and it was the last 34pt standing between
    /// the cover and the width of its own card. The screen is now four things: the cue, the card,
    /// the clock, the way out.
    private var countdown: some View {
        VStack(spacing: Space.sm) {
            SectionLabel("sealed.opens.label")
            CountdownView(
                timer: timer,
                deadline: context.round.revealsAt,
                accent: accent,
                announces: .reveal
            )
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
