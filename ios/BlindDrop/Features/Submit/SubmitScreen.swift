import SwiftUI

/// The open round, before the caller has dropped anything: **the search screen itself**.
///
/// There is no lobby in front of it. A screen whose only content is a headline and a button
/// that opens the real screen is a tap charged for nothing, and the round is on a clock — the
/// field is up and focused the moment this appears, so the first thing somebody can do is the
/// thing they came to do.
///
/// The clock lives in the header badge (`RoundHeader`) rather than in the column, because it is
/// the only thing here that changes while nobody is touching the screen, and a ticking hero
/// countdown over a search field is a countdown competing with the typing.
///
/// Nothing on this screen counts anybody. No submitted total, no *waiting on*, no avatars — the
/// only shared fact is the clock, which everybody already has (`CLAUDE.md` §2.1).
struct SubmitScreen: View {
    let context: RoundContext
    let store: SubmitStore
    let player: PreviewPlayer
    let timer: CountdownTimer
    /// What the countdown counts to — the reveal, or the next opening during the dark hours.
    /// Chosen by `RoundContext.deadline(now:)` against the **server's** clock, never here.
    let deadline: Date
    /// Whether the round has opened yet (`docs/08` §2, the dark-hours state).
    let isBeforeOpen: Bool
    /// A chosen song goes to the confirm step, which the round presents.
    let choose: (TrackDTO) -> Void

    /// Amber, decided once at the top of the screen and handed down (`CLAUDE.md` §2.5).
    private let accent = PhaseAccent.sealed

    @FocusState private var isFieldFocused: Bool

    var body: some View {
        column
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear { if !isBeforeOpen { isFieldFocused = true } }
            .onDisappear { player.stop() }
    }

    /// The screen's column, which the snapshots render directly.
    var snapshotContent: some View { column }

    @ViewBuilder private var column: some View {
        if isBeforeOpen {
            closed
        } else {
            SongSearch(
                store: store,
                player: player,
                accent: accent,
                isFieldFocused: $isFieldFocused,
                choose: choose,
                header: { prompt },
                footer: { footer }
            )
        }
    }

    // MARK: - Open

    /// *"Today's song."* and the one line of rules under it.
    private var prompt: some View {
        VStack(alignment: .leading, spacing: Layout.itemGap) {
            Text("submit.headline")
                .typeStyle(.displayL)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("submit.subhead")
                .typeStyle(.bodyL)
                .foregroundStyle(Palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What sits under the field while nothing has been searched for: the nudge if the reveal is
    /// close, and the fact that makes the whole game work.
    private var footer: some View {
        VStack(alignment: .leading, spacing: Layout.itemGap) {
            // `docs/08` §2: under two hours the nudge appears, in `amberText`, and **nothing
            // else changes**. It is an in-interface nudge and deliberately not the push — the
            // push is `docs/05` §3's, goes only to non-droppers, and says the same thing because
            // there is only one true thing to say.
            if showsNudge {
                Text("submit.nudge")
                    .typeStyle(.bodyM)
                    .foregroundStyle(accent.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            Text("submit.blind")
                .typeStyle(.bodyS)
                .foregroundStyle(Palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - The dark hours

    /// Between the answers and tomorrow's opening there is nothing to search for, so the screen
    /// says what it is waiting for and counts to it.
    private var closed: some View {
        VStack(alignment: .leading, spacing: Layout.blockGap) {
            Spacer(minLength: Space.none)
            VStack(alignment: .leading, spacing: Layout.itemGap) {
                Text("submit.closed.headline")
                    .typeStyle(.displayL)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: Copy.format("submit.closed.subhead", context.opensTime))
                    .typeStyle(.bodyL)
                    .foregroundStyle(Palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            countdown
            Spacer(minLength: Space.none)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var countdown: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionLabel("submit.closed.countdown.label")
            CountdownView(
                timer: timer,
                deadline: deadline,
                accent: accent,
                announces: .reveal
            )
        }
        // The countdown announces itself in full (`a11y.countdown`); the label above it is part
        // of that sentence rather than a second stop.
        .accessibilityElement(children: .combine)
    }

    /// Under two hours to the reveal (`docs/08` §2).
    ///
    /// Read off the **countdown that is already ticking** rather than from a second clock. Two
    /// things fall out of that: the line appears the second the visible countdown crosses two
    /// hours rather than at the next refetch, and there is no `Date()` anywhere near it
    /// (`docs/13` §5 rule 1).
    private var showsNudge: Bool {
        guard !isBeforeOpen, let remaining = timer.display.secondsRemaining else { return false }
        return remaining < Self.nudgeThreshold
    }

    /// Two hours, in seconds. The same threshold `docs/05` §3 enqueues the push at.
    static let nudgeThreshold = 2 * 60 * 60
}
