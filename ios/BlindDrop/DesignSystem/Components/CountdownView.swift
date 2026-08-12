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
    /// How loudly it is drawn. Defaults to `.hero`, which is `docs/07` §5's `monoXL`.
    var prominence: Prominence = .hero

    /// The two jobs a countdown does in this app.
    ///
    /// `docs/07` §5 specifies `monoXL` because on Submit and Sealed the countdown **is** the
    /// screen's second subject — the thing the eye lands on after the song. On Reveal it is not:
    /// `docs/08` §6 draws it as one half of a `bodyM` status line, *"8 songs · 01:42:19"*, in
    /// `monoM`. Both are the same countdown with the same clock and the same announcement, so
    /// this is a size, not a second component.
    ///
    /// It deliberately does not touch `CountdownForm`. Which *words* a countdown uses at a given
    /// Dynamic Type size is a legibility rule (`docs/12` §1) and stays the component's decision;
    /// how large it is drawn is the screen's. Above `.accessibility2` both prominences still go
    /// coarse — an inline countdown that kept eight monospaced digits at `.accessibility5` would
    /// break the status line exactly the way the hero one breaks the screen.
    enum Prominence: Sendable, Equatable {
        /// Submit, Sealed, Voided: `monoXL`, the screen's second subject.
        case hero
        /// Reveal's status line: `monoM`, beside the song count.
        case inline
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var form: CountdownForm { Typography.countdownForm(for: dynamicTypeSize) }

    /// The style the two decisions resolve to: the form picks the words, the prominence the size.
    private var typeStyle: TypeStyle {
        switch (form, prominence) {
        case (.precise, .hero): .monoXL
        case (.precise, .inline): .monoM
        case (.coarse, .hero): .bodyLStrong
        // The coarse form is words, not digits, so its inline size comes off the body ramp and
        // sits on the same baseline as the song count it follows.
        case (.coarse, .inline): .bodyM
        }
    }

    var body: some View {
        Text(verbatim: Copy.countdown(timer.display))
            .typeStyle(typeStyle)
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
