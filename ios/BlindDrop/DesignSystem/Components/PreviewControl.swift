import SwiftUI

/// The 30-second preview control, shared by `TrackRow` and `FlightCard`.
///
/// Not one of the ten components of `docs/07` §5 — it is a *part* of two of them, and it lives
/// in its own file because the alternative is the same 30 lines in both, drifting apart at the
/// first change to the accessibility contract. `docs/12` §2 gives it a row of its own in the
/// VoiceOver table, which is the clearest sign it is one thing rather than two.
///
/// **A track with no preview gets no control** — not a disabled one (`docs/06` §7). That is the
/// caller's decision, which is why there is no `isEnabled` here to get it wrong with.
struct PreviewControl: View {
    let isPlaying: Bool
    let accent: PhaseAccent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                .font(.system(size: Layout.previewControl * 0.5))
                .foregroundStyle(accent.mark)
                .frame(width: Layout.previewControl, height: Layout.previewControl)
                .background(
                    Circle().stroke(accent.mark, lineWidth: Stroke.border)
                )
                // Drawn at 28pt, tapped at 44 (`docs/07` §5, `docs/12` §5).
                .minimumTouchTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Copy.A11y.preview(isPlaying: isPlaying))
        .accessibilityAddTraits([.isButton, .startsMediaSession])
    }
}
