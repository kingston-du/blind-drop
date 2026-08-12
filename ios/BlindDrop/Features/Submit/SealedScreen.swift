import SwiftUI

/// `docs/08` §4 — `open`, submitted. Accent **amber**.
///
/// ```
/// │  ┌───────────────────────┐  │
/// │  │ ░░  cover over art ░░ │  │   SealedCard: amberWash, amberDeep border, stamp
/// │  └───────────────────────┘  │
/// │      Sealed until 8:00.     │   bodyL, amberText
/// │         03:12:48            │   monoXL, amberText, tabular
/// │         until reveal        │   caption, inkFaint
/// │       Replace song          │   SecondaryButton
/// ```
///
/// > *"Nothing else is on this screen. No 'you're the 4th to drop', no roster, no preview of the
/// > reveal."*
///
/// The card arrives **already sealed**. `docs/08` §3.2: the animation runs on the confirm sheet
/// and *"is not replayed on the screen behind"* — so `SealedCard`'s default phase is `.sealed` and
/// this screen never touches `SealAnimation`.
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
            SealedCard(
                track: submission.track,
                groupInitial: context.groupInitial,
                remaining: Copy.countdown(timer.display)
            )
            status
            countdown
            // Reopens search. A replacement re-runs the seal in the sheet, which is why this is a
            // plain callback and not something this screen animates.
            SecondaryButton("sealed.replace", action: replace)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// *"Sealed until 8:00."*, or *"Sealed again."* after a replacement (`docs/11`).
    ///
    /// The second line is the whole of what a replacement does to the interface. It drops the
    /// hour, which is not a loss: the countdown directly under it is counting to exactly that
    /// hour, and the sentence a person wants after replacing is the one that says the new song is
    /// in.
    private var status: some View {
        Text(verbatim: didReplace
             ? Copy.string("sealed.replaced")
             : Copy.format("sealed.status", context.revealTime))
            .typeStyle(.bodyL)
            .foregroundStyle(accent.text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var countdown: some View {
        VStack(spacing: Space.xs) {
            CountdownView(
                timer: timer,
                deadline: context.round.revealsAt,
                accent: accent,
                announces: .reveal
            )
            Text("sealed.countdown.label")
                .typeStyle(.caption)
                .foregroundStyle(Palette.inkFaint)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
