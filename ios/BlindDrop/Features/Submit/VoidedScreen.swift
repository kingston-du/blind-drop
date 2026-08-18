import SwiftUI

/// `docs/08` §5 — `voided`. Accent **amber, muted**: `amberText` on `paper`, no fills.
///
/// > *"Not enough drops tonight. Nothing revealed."* Beneath it, the user's own card, unsealed and
/// > plain, with *"Your song came back."*
///
/// **No count of how many did drop**, and there is nowhere to get one: the `voided` payload has
/// the same shape as `open` and carries the caller's own submission and nothing else
/// (`docs/04` §4). In a group of eight, *"only 2 dropped"* is a statement about six specific
/// people — which is why the number does not exist on the wire, not merely why it is not printed.
///
/// The card is drawn **plain**: `surface` and an `edge` border, the standard card treatment of
/// `docs/07` §2. Not a `SealedCard` with the cover lifted — the seal is over, the song was never
/// seen by anybody, and dressing it in amber wash would say the opposite.
struct VoidedScreen: View {
    let context: RoundContext
    /// The caller's own song, if they dropped one. A member who did not drop sees the headline and
    /// the countdown, and no card — there is no song of theirs to come back.
    let submission: SubmissionDTO?
    let timer: CountdownTimer
    /// Tomorrow's opening, in the group's timezone (`RoundContext.deadline(now:)`).
    let deadline: Date

    private let accent = PhaseAccent.sealed

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.blockGap) {
            Text("voided.headline")
                .typeStyle(.displayL)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let submission {
                returnedSong(submission)
            }

            countdown
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Space.xxl)
    }

    /// The song, unsealed and plain, and the line that explains why it is back.
    private func returnedSong(_ submission: SubmissionDTO) -> some View {
        VStack(alignment: .leading, spacing: Layout.itemGap) {
            HStack(alignment: .top, spacing: Space.md) {
                ArtworkView(submission.track, size: Layout.Artwork.flightCard)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(verbatim: submission.track.title)
                        .typeStyle(.bodyLStrong)
                        .foregroundStyle(Palette.ink)
                    Text(verbatim: submission.track.artist)
                        .typeStyle(.bodyM)
                        .foregroundStyle(Palette.inkDim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .cardSurface()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Copy.A11y.track(title: submission.track.title,
                                                artist: submission.track.artist))

            Text("voided.returned")
                .typeStyle(.bodyM)
                .foregroundStyle(accent.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The countdown to **tomorrow's** open, and the hour it will be (`docs/08` §5).
    private var countdown: some View {
        VStack(spacing: Space.sm) {
            SectionLabel(verbatim: Copy.format("voided.next", context.opensTime))
            CountdownView(
                timer: timer,
                deadline: deadline,
                accent: accent,
                announces: .reveal
            )
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
