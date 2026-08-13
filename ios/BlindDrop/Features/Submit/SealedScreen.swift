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

    private let accent = PhaseAccent.sealed

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.blockGap) {
            VStack(alignment: .leading, spacing: Layout.itemGap) {
                SealedCard(
                    track: submission.track,
                    groupInitial: context.groupInitial,
                    remaining: Copy.countdown(timer.display)
                )
                TrackLinkButtons(track: submission.track)
                status
            }
            countdown
            Spacer(minLength: Space.none)
            // Reopens search. A replacement re-runs the seal in the sheet, which is why this is
            // a plain callback and not something this screen animates.
            OutlineButton("sealed.replace", action: replace)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
