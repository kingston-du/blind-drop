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
                // `strokeBorder`, so the ring is drawn *inside* the 28pt frame rather than
                // spilling to 29 — which matters here more than elsewhere, because the rows below
                // do arithmetic against this control's drawn size.
                .background(
                    Circle().strokeBorder(accent.mark, lineWidth: Stroke.border)
                )
                // Drawn at 28pt, tapped at 44 (`docs/07` §5, `docs/12` §5).
                .minimumTouchTarget()
                // A card row's geometry belongs to its 88pt artwork, not to this control's
                // generous hit area. Without cancelling the 8pt expansion on each side, a
                // preview-bearing card reports a 44pt-tall artist line; baseline alignment can
                // then make that one row visibly taller than its neighbours. The hit shape stays
                // 44pt and lives safely inside the card's inset, while layout sees the 28pt
                // control that is actually drawn.
                .padding(-(Layout.minimumTouchTarget - Layout.previewControl) / 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Copy.A11y.preview(isPlaying: isPlaying))
        .accessibilityAddTraits([.isButton, .startsMediaSession])
    }
}
