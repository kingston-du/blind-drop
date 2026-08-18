import SwiftUI

/// Every curve and duration the app animates with — `docs/09`'s budget, written down once.
///
/// > *"If a task proposes an animation not in this table, the answer is no."* (`docs/09` §1)
///
/// So this file is the table. Two moments get the whole budget and are specified frame by frame;
/// everything else is an iOS default and appears here only where a screen has to name it.
///
/// The timings are **milliseconds from the start of the moment**, exactly as `docs/09` draws them,
/// and each stage carries its own `delay` rather than being sequenced by the caller. That is what
/// makes six overlapping phases one animation: the seal's cover is still settling while the stamp
/// is already falling, which no chain of `asyncAfter` calls can express and no sequence of awaits
/// can either. `MotionTokenTests` asserts every number in here against `docs/09` §2–3.
enum Motion {

    /// The seal — 600ms, six phases (`docs/09` §2).
    ///
    /// ```
    ///    0ms                200                400                600
    ///    │──────────────────│──────────────────│──────────────────│
    ///  A ██████                                      button collapse (0–120)
    ///  B    ████████████████████                     cover slides down (80–340)
    ///  C                    ███                      cover settle overshoot (320–400)
    ///  D                       ████████████          stamp lands (360–540)
    ///  E                              ███████████    ring dissipates (480–640)
    ///  F                                    ██████   countdown fades in (560–680)
    /// ```
    enum Seal {

        /// One phase of the timeline: when it starts, how long it runs, and what curve it runs on.
        ///
        /// A value rather than six loose constants so a test can read the timeline the way
        /// `docs/09` draws it, and so the view applies `stage.animation` without knowing what is in
        /// it. `animation` already carries the delay, so a modifier is `.animation(stage.animation,
        /// value: phase)` and nothing at the call site can get the ordering wrong.
        struct Stage: Sendable {
            /// The letter `docs/09` §2 gives it, so a failing test names the phase the spec names.
            let phase: String
            /// Milliseconds from the start of the seal.
            let start: Double
            let duration: Double
            /// The curve, delay included.
            let animation: Animation

            var end: Double { start + duration }
        }

        /// **A — the button collapses (0–120ms).** `spring(response: 0.22, dampingFraction: 0.85)`.
        ///
        /// *"The screen's primary action disappearing is what makes the next 500ms feel
        /// inevitable."*
        static let buttonCollapse = Stage(
            phase: "A", start: 0, duration: 120,
            animation: .spring(response: 0.22, dampingFraction: 0.85)
        )

        /// **B — the cover slides (80–340ms).** 260ms on `cubicBezier(0.20, 0.90, 0.10, 1.00)` —
        /// fast out, long settle.
        static let coverSlide = Stage(
            phase: "B", start: 80, duration: 260,
            animation: .timingCurve(0.20, 0.90, 0.10, 1.00, duration: 0.260).delay(0.080)
        )

        /// **C — settle (320–400ms).** The cover overshoots by `overshoot` and returns.
        /// `spring(response: 0.18, dampingFraction: 0.62)`.
        ///
        /// *"Small, but it is the difference between a panel arriving and a lid closing."*
        static let settle = Stage(
            phase: "C", start: 320, duration: 80,
            animation: .spring(response: 0.18, dampingFraction: 0.62).delay(0.320)
        )

        /// **D — the stamp (360–540ms).** `spring(response: 0.28, dampingFraction: 0.72)` over
        /// 180ms.
        static let stamp = Stage(
            phase: "D", start: 360, duration: 180,
            animation: .spring(response: 0.28, dampingFraction: 0.72).delay(0.360)
        )

        /// **E — the ring (480–640ms).** One ring, `easeOut` over 200ms. Not three, not a pulse.
        static let ring = Stage(
            phase: "E", start: 480, duration: 200,
            animation: .easeOut(duration: 0.200).delay(0.480)
        )

        /// **F — the countdown (560–680ms).** *"Sealed until 8:00."* fades up over 120ms.
        static let footer = Stage(
            phase: "F", start: 560, duration: 120,
            animation: .easeOut(duration: 0.120).delay(0.560)
        )

        /// The six phases in the order `docs/09` §2 lists them.
        static let stages: [Stage] = [buttonCollapse, coverSlide, settle, stamp, ring, footer]

        /// When the last pixel stops moving: 680ms.
        static var end: Double { stages.map(\.end).max() ?? 0 }

        /// The cover's overshoot, in points (`docs/09` §2, phase C).
        static let overshoot: CGFloat = 2

        /// **The haptics, at contact rather than at phase start** (`docs/09` §2).
        ///
        /// 100ms is 20ms into the cover's travel — the moment it reads as having been let go, not
        /// the moment the animation was asked to begin. 380ms is 20ms into the stamp's fall, where
        /// it touches down; the phase itself starts at 360.
        static let coverMovesAt: Double = 100
        static let stampLandsAt: Double = 380

        /// Reduced motion: a **240ms crossfade** between the same two states (`docs/09` §5).
        ///
        /// No translation, no scale, no rotation, no ring — and no state skipped. The sealed card
        /// still exists; it arrives without traversal.
        static let reduced = Stage(
            phase: "reduced", start: 0, duration: 240, animation: .easeInOut(duration: 0.240)
        )

        /// The one haptic of the reduced-motion path, at the crossfade's midpoint.
        ///
        /// *"Reduced motion is not reduced feedback"* (`docs/09` §5). It is the **stamp's** note
        /// rather than the cover's, because what the crossfade is a confirmation of is the arrival
        /// — the cover never travels, so there is no letting-go to feel.
        static var reducedHapticAt: Double { reduced.duration / 2 }
    }

    /// The unseal — 380ms per card, staggered (`docs/09` §3). `E11-04` animates it; the stagger
    /// lives here because this is where a duration is written down, and because `docs/09` §6 asks
    /// for a unit test on exactly this arithmetic.
    enum Unseal {

        struct Stage: Sendable {
            let phase: String
            let start: Double
            let duration: Double
            let animation: Animation

            var end: Double { start + duration }
        }

        static let cover = Stage(
            phase: "A", start: 0, duration: 220,
            animation: .easeOut(duration: 0.220)
        )
        static let stamp = Stage(
            phase: "B", start: 60, duration: 140,
            animation: .easeIn(duration: 0.140).delay(0.060)
        )
        static let colors = Stage(
            phase: "C", start: 140, duration: 260,
            animation: .easeInOut(duration: 0.260).delay(0.140)
        )
        static let artwork = Stage(
            phase: "D", start: 200, duration: 140,
            animation: .spring(response: 0.34, dampingFraction: 0.78).delay(0.200)
        )
        static let number = Stage(
            phase: "E", start: 260, duration: 140,
            animation: .easeOut(duration: 0.140).delay(0.260)
        )
        static let stages = [cover, stamp, colors, artwork, number]
        static var end: Double { stages.map(\.end).max() ?? 0 }

        static let reducedDuration = 240
        static let reducedSequenceLimit = 400

        /// ```swift
        /// let stagger = min(80, 900 / max(1, cardCount - 1))   // milliseconds
        /// ```
        ///
        /// 80ms nominal, compressed so the full sequence never exceeds ~900ms plus the 380ms tail.
        /// At twelve cards it is still 80; at thirty it compresses to 31.
        static func stagger(cardCount: Int) -> Int {
            min(80, 900 / max(1, cardCount - 1))
        }

        /// Reduced motion keeps a nominal 40ms stagger but compresses it so the final card's
        /// 240ms crossfade ends by 400ms (`docs/09` §5).
        static func reducedStagger(cardCount: Int) -> Int {
            let available = reducedSequenceLimit - reducedDuration
            return min(40, available / max(1, cardCount - 1))
        }
    }

    /// The results name-resolve (`docs/09` §4).
    ///
    /// > *"Card owners' names arrive top-to-bottom, 120ms apart, each a 220ms crossfade plus
    /// > `y: 4 → 0`. The correct/incorrect mark on your guess arrives 80ms after its name."*
    ///
    /// Three numbers and no curve table, because this moment is one crossfade repeated rather
    /// than six overlapping phases: what makes it read is the **cadence**, which is why the
    /// stagger and the mark's offset are the values a test pins.
    enum Resolve {
        /// Between one card's name and the next's.
        static let stagger = 120
        /// The name's crossfade.
        static let duration = 0.220
        /// How far the name travels up as it arrives. Eight points — a settle with presence,
        /// still small enough to leave the card's geometry untouched.
        static let rise: CGFloat = 8
        /// The mark lands **after** its own name, not after the sequence. A user reading the
        /// third card is told whose song it was and then, a beat later, whether they had it.
        static let markDelay = 80
        /// The room bar fills after the card's mark has landed.
        static let barDelay = 80

        static let name = Animation.easeOut(duration: duration)
        static let mark = Animation.easeOut(duration: duration)

        /// *"Results resolve: all names appear at once, no stagger"* (`docs/09` §5). The
        /// crossfade is kept — reduced motion removes movement, not the arrival — and the rise
        /// is dropped, because the rise **is** the movement.
        static let reduced = Animation.easeInOut(duration: duration)
    }

    /// The reveal call sheet's one interruptible spring (`docs/09` §1).
    enum CallSheet {
        static let spring = Animation.spring(response: 0.34, dampingFraction: 0.82)
    }

    /// Button press: 120ms, scale 0.985 (`docs/09` §1). Under reduced motion, opacity only
    /// (`docs/09` §5) — which is `PrimaryButton`'s to apply, not this table's to decide.
    static let buttonPress = Animation.easeOut(duration: 0.120)
    static let buttonPressScale: CGFloat = 0.985
}
