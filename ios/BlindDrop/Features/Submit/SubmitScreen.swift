import SwiftUI

/// `docs/08` §2 — `open`, nothing dropped. Accent **amber**.
///
/// ```
/// │  Monday 10 August           │   label, inkDim
/// │  ────────────────────────   │
/// │   Drop one song.            │   displayM, ink
/// │   Nobody sees it until      │   bodyL, inkDim  ← the entire tutorial
/// │   8:00 PM.                  │
/// │         09:47:12            │   monoXL, amberText, tabular
/// │         until reveal        │   caption, inkFaint
/// │  ┌───────────────────────┐  │
/// │  │     Drop a song       │  │   PrimaryButton, amber fill, ink label
/// │  └───────────────────────┘  │
/// ```
///
/// > **This screen leaks nothing.** No submission count, no "3 of 8 in", no avatars, no activity
/// > indicator, no "waiting on Sam".
///
/// That is not a thing this file remembers to do. There is nothing here to leak *with*: the only
/// value it is given is a `RoundContext`, and an `open` round has no shape that can hold a fact
/// about anybody else (`RoundDTO.Phase.open`). A reviewer can read this screen against
/// `GET /rounds/current`'s `open` payload and see that neither could possibly express how many
/// people have dropped — and `SubmitLeakTests` asserts the accessibility side of it too, because
/// `docs/12` §2 says the blind window applies to VoiceOver as well.
struct SubmitScreen: View {
    let context: RoundContext
    let timer: CountdownTimer
    /// What the countdown counts to — the reveal, or the next opening during the dark hours.
    /// Chosen by `RoundContext.deadline(now:)` against the **server's** clock, never here.
    let deadline: Date
    /// Whether the round has opened yet (`docs/08` §2, the dark-hours state).
    let isBeforeOpen: Bool
    let drop: () -> Void

    /// Amber, decided once at the top of the screen and handed down (`CLAUDE.md` §2.5).
    private let accent = PhaseAccent.sealed

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.blockGap) {
            dateLine
            headline
            countdown
            action
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// *"Monday 10 August"* and the rule under it (`docs/08` §2).
    ///
    /// The day is the **group's**, formatted from the round's `local_date` on the group's calendar
    /// (`docs/13` §5 rule 6) — a member reading this in Lisbon sees the group's Monday, which is
    /// the day the round belongs to. Absent rather than guessed if the date will not parse.
    @ViewBuilder private var dateLine: some View {
        VStack(alignment: .leading, spacing: Layout.itemGap) {
            if let day = context.dateHeadline {
                Text(verbatim: day)
                    .typeStyle(.label)
                    .foregroundStyle(Palette.inkDim)
            }
            Rectangle()
                .fill(Palette.edgeStrong)
                .frame(height: Stroke.hairline(atScale: displayScale))
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: Layout.itemGap) {
            Text(isBeforeOpen ? "submit.closed.headline" : "submit.headline")
                .typeStyle(.displayM)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            // The subhead is the whole tutorial in one line, and in the dark hours it is the one
            // fact that matters instead: when this opens again. `%@` is the group's opening hour
            // in the group's own clock (`docs/13` §5 rule 6).
            Text(verbatim: isBeforeOpen
                 ? Copy.format("submit.closed.subhead", context.opensTime)
                 : Copy.string("submit.subhead"))
                .typeStyle(.bodyL)
                .foregroundStyle(Palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The countdown and its label, centred as `docs/08` §2 draws them.
    private var countdown: some View {
        VStack(spacing: Space.xs) {
            CountdownView(
                timer: timer,
                deadline: deadline,
                accent: accent,
                announces: .reveal
            )
            Text(isBeforeOpen ? "submit.closed.countdown.label" : "submit.countdown.label")
                .typeStyle(.caption)
                .foregroundStyle(Palette.inkFaint)
        }
        .frame(maxWidth: .infinity)
        // The countdown announces itself in full (`a11y.countdown`); the label under it is part of
        // that sentence rather than a second stop.
        .accessibilityElement(children: .combine)
    }

    private var action: some View {
        VStack(alignment: .leading, spacing: Layout.itemGap) {
            // `docs/08` §2: under two hours the nudge appears above the button, in `amberText`,
            // and **nothing else changes**. It is an in-interface nudge and it is deliberately not
            // the push — the push is `docs/05` §3's, goes only to non-submitters, and says the
            // same thing because there is only one true thing to say.
            if showsNudge {
                Text("submit.nudge")
                    .typeStyle(.bodyM)
                    .foregroundStyle(accent.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            PrimaryButton("submit.action", accent: accent, isEnabled: !isBeforeOpen, action: drop)
        }
    }

    /// Under two hours to the reveal (`docs/08` §2).
    ///
    /// Read off the **countdown that is already ticking** rather than from a second clock. Two
    /// things fall out of that: the line appears the second the visible countdown crosses two
    /// hours rather than at the next refetch, and there is no `Date()` anywhere near it
    /// (`docs/13` §5 rule 1). In the dark hours there is no nudge — the countdown is to the
    /// opening, and *"two hours left to drop"* would be false.
    private var showsNudge: Bool {
        guard !isBeforeOpen, let remaining = timer.display.secondsRemaining else { return false }
        return remaining < Self.nudgeThreshold
    }

    /// Two hours, in seconds. The same threshold `docs/05` §3 enqueues the push at.
    static let nudgeThreshold = 2 * 60 * 60
}
