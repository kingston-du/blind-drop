import SwiftUI

/// The countdown (`docs/07` §5).
///
/// `monoXL`, tabular, `HH:MM:SS`. **Driven by `ServerClock`, never `Date()`** (`CLAUDE.md` §2.2,
/// AC-2) — and that is a property of construction rather than of discipline here: the view has
/// no way to reach a clock except through the `CountdownTimer` it is handed, and a
/// `CountdownTimer` can only be built from a `ServerClock`.
///
/// **At zero it does not change state.** It reports that the deadline passed and the screen
/// refetches; the server says what happens next. A client that flipped its own phase at zero
/// would show a reveal that had not happened.
///
/// Above `.accessibility2` it becomes the coarse form — *"3 hours"* in `bodyLStrong`, updating
/// every minute (`docs/12` §1). That is an improvement, not a fallback: `monoXL` cannot fit
/// eight monospaced digits on an SE at that size, and at that size the reader is not reading
/// seconds.
struct CountdownView: View {
    let timer: CountdownTimer
    /// The instant being counted to. Held here as well as inside the timer so the view can
    /// re-point it when the Dynamic Type size changes the tick cadence.
    let deadline: Date
    /// Colour follows the phase (`docs/07` §5).
    let accent: PhaseAccent
    /// What the countdown is counting to, for the announcement — *"%@ until reveal"* or
    /// *"%@ until answers"* (`docs/11`).
    let announces: Copy.A11y.Deadline

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var form: CountdownForm { Typography.countdownForm(for: dynamicTypeSize) }

    var body: some View {
        Text(verbatim: Copy.countdown(timer.display))
            .typeStyle(form.typeStyle)
            .foregroundStyle(accent.text)
            .accessibilityLabel(Copy.A11y.countdown(timer.display, until: announces))
            // Recomputed on focus rather than announced on every tick (`docs/12` §2). Without
            // this, VoiceOver interrupts itself once a second and the screen becomes unusable.
            .accessibilityAddTraits(.updatesFrequently)
            .onAppear { timer.start(until: deadline, form: form) }
            .onChange(of: form) { timer.start(until: deadline, form: form) }
            .onChange(of: deadline) { timer.start(until: deadline, form: form) }
            .onDisappear { timer.stop() }
    }
}
