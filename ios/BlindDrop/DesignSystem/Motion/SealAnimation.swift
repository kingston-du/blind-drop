import SwiftUI

/// **The one moment the app is remembered by** (`docs/09` §2).
///
/// Six phases over ~680ms, and the whole thing is one number: `SealPhase` says *unsealed* or
/// *sealed*, that flips a single animated `progress` from 0 to 1, and every pixel that moves is a
/// pure function of it (`SealTimeline`). That shape is what the checklist asks for and what the
/// alternatives cannot give:
///
/// - **One enum, one chain.** Not six `DispatchQueue.main.asyncAfter` calls (`docs/13` §9 lists
///   that as an automatic review rejection). Setting `progress` back to 0 reverses the whole
///   thing mid-flight, so it is interruptible by construction.
/// - **Testable without a screen.** The timeline is arithmetic: `SealTimeline.values(at:)` answers
///   what the cover, the stamp and the ring are doing at 380ms, and `SealTimelineTests` asserts
///   it against `docs/09` §2 rather than against a recording of what the code happened to do.
/// - **No layout during the animation** (`docs/09` §2, §6). Every property here is a transform, an
///   opacity, a brightness or a shadow — never a frame, never a spacing, never a `.frame(height:)`
///   that grows. The interpolation happens inside `Animatable` modifiers, so SwiftUI walks a
///   fixed layer tree per frame instead of re-evaluating the screen's body.
///
/// The two transients are the reason the timeline is a *function of time* rather than two states
/// SwiftUI interpolates between: the cover's shadow and the stamp's ring both begin at zero, rise,
/// and return to zero. A two-state crossfade cannot express "and back again" — it would animate
/// from nothing to nothing and draw neither.
enum SealPhase: Sendable, Equatable, CaseIterable {
    /// The confirm layout: artwork bare, **Seal it** at rest.
    case unsealed
    /// The landed state: the cover down, the stamp on it, the countdown up. What `SealedCard`
    /// draws with no animation at all, and what `SealedScreen` shows on arrival.
    case sealed

    /// The timeline position this phase sits at.
    var progress: Double {
        switch self {
        case .unsealed: 0
        case .sealed: 1
        }
    }
}

// MARK: - The values

/// Everything the seal moves, at one instant.
///
/// A value type with no view in it, so the timeline can be asserted and the reduced-motion path
/// can be compared to the full one **by equality** rather than by eye (`docs/09` §5: *"the same
/// final state"*).
struct SealValues: Equatable, Sendable {

    /// How much of the cover's travel is done, 0…1. Applied as a translation, never as a height.
    var coverTravel: Double
    /// The cover's own opacity. 1 throughout the full path — the cover arrives by moving. Under
    /// reduced motion it is the crossfade itself.
    var coverOpacity: Double
    /// Points **past** flush, phase C. Zero at rest and zero when it has settled; the only thing
    /// between is a lid closing.
    var coverOvershoot: CGFloat

    /// The artwork's own retreat under the cover: `y: 0 → -8`, `scale 1.0 → 0.98`, brightness
    /// `1.0 → 0.92` (`docs/09` §2, phase B).
    var artworkOffset: CGFloat
    var artworkScale: CGFloat
    /// SwiftUI's `.brightness` is additive, so `0.92` of the original is `-0.08` here.
    var artworkBrightness: Double

    /// **The only shadow in the app** (`docs/07` §2), and only while the cover is moving:
    /// `ink @ 8%`, radius `0 → 12`, y `0 → 4`, resolving to zero on land.
    var shadowRadius: CGFloat
    var shadowOffset: CGFloat

    /// The stamp: `scale 1.6 → 1.0`, `rotation -8° → -4°`, `opacity 0 → 1` (phase D).
    var stampScale: CGFloat
    var stampRotation: Double
    var stampOpacity: Double

    /// The ring: one, from the stamp's centre, `scale 1.0 → 1.9`, `opacity 0.35 → 0` (phase E).
    var ringScale: CGFloat
    var ringOpacity: Double

    /// The primary action collapsing toward its centre (phase A). A horizontal **scale**, because
    /// a width would be a layout pass — see `SealTimeline.actionScale(width:progress:)`.
    var actionCollapse: Double
    var actionOpacity: Double

    /// *"Sealed until 8:00."* and the countdown arriving (phase F).
    var footerOpacity: Double
    var footerOffset: CGFloat

    /// The confirm layout, before anything has happened.
    static let unsealed = SealValues(
        coverTravel: 0, coverOpacity: 1, coverOvershoot: 0,
        artworkOffset: 0, artworkScale: 1, artworkBrightness: 0,
        shadowRadius: 0, shadowOffset: 0,
        stampScale: SealTimeline.stampEntryScale, stampRotation: SealTimeline.stampEntryRotation,
        stampOpacity: 0,
        ringScale: 1, ringOpacity: 0,
        actionCollapse: 0, actionOpacity: 1,
        footerOpacity: 0, footerOffset: SealTimeline.footerEntryOffset
    )

    /// The landed state. **Both paths end exactly here** — that is what makes the reduced-motion
    /// end state identical rather than merely similar, and it is what `SealedCard` draws by
    /// default so the animation has something to be a transition *to*.
    static let sealed = SealValues(
        coverTravel: 1, coverOpacity: 1, coverOvershoot: 0,
        artworkOffset: SealTimeline.artworkLift, artworkScale: SealTimeline.artworkSettleScale,
        artworkBrightness: SealTimeline.artworkDimming,
        shadowRadius: 0, shadowOffset: 0,
        stampScale: 1, stampRotation: SealTimeline.stampRestRotation, stampOpacity: 1,
        ringScale: SealTimeline.ringExpandedScale, ringOpacity: 0,
        actionCollapse: 1, actionOpacity: 0,
        footerOpacity: 1, footerOffset: 0
    )
}

// MARK: - The timeline

/// `docs/09` §2's diagram, as arithmetic.
///
/// Time is expressed as **timeline progress** — 0…1 across `Motion.Seal.end` — because that is what
/// SwiftUI can animate with one linear driver and interpolate on the render thread. Each phase's
/// own curve is applied *inside* this function, which is why the driver is linear and why the
/// spring in phase C can overshoot while the linear progress cannot.
enum SealTimeline {

    // MARK: The constants `docs/09` §2 names

    /// Phase B's artwork: `y: 0 → -8`, `scale 1.0 → 0.98`, brightness `1.0 → 0.92`.
    static let artworkLift: CGFloat = -8
    static let artworkSettleScale: CGFloat = 0.98
    static let artworkDimming: Double = -0.08

    /// The cover's shadow at its peak: radius 12, y 4, `ink` at 8% (`docs/07` §2).
    static let shadowPeakRadius: CGFloat = 12
    static let shadowPeakOffset: CGFloat = 4
    static let shadowOpacity: Double = 0.08

    /// Phase D's stamp: in at 1.6× and −8°, landing at 1.0 and **−4°**.
    ///
    /// > *"It lands off-axis by 4°. A stamp that lands square reads as a UI element; one that
    /// > lands slightly crooked reads as a physical act. Do not 'fix' this."*
    static let stampEntryScale: CGFloat = 1.6
    static let stampEntryRotation: Double = -8
    static let stampRestRotation: Double = -4

    /// Phase E's ring: `scale 1.0 → 1.9`, `opacity 0.35 → 0`. One ring.
    static let ringExpandedScale: CGFloat = 1.9
    static let ringEntryOpacity: Double = 0.35

    /// Phase F: the footer rises `y: 6 → 0` as it fades.
    static let footerEntryOffset: CGFloat = 6

    /// The collapsed width of the primary action (`docs/09` §2, phase A): a 52pt pill.
    static let actionCollapsedWidth: CGFloat = Layout.buttonHeight

    /// Phase A's opacity falls over **the last 40ms** of the collapse, not across all of it.
    static let actionFadeDuration: Double = 40

    // MARK: Reading the timeline

    /// The values at a timeline position, 0…1.
    ///
    /// - Parameter reducedMotion: `docs/09` §5 — a 240ms crossfade between the same two states.
    ///   No translation, no scale, no rotation, no ring; the stamp appears at its final position
    ///   and rotation. Colour is not reduced, because colour is information.
    static func values(progress: Double, reducedMotion: Bool = false) -> SealValues {
        let progress = min(max(progress, 0), 1)
        // **The two ends are exact.** Not "wherever the springs happen to be at 680ms": a spring's
        // tail is still a few thousandths from its target when its phase nominally ends, and a
        // stamp sitting at 1.003× and −4.02° is a *visibly* different set of pixels once it is
        // rasterised — antialiasing around a 56pt circle magnifies it. Both paths therefore land
        // on the same defined state, which is what `docs/09` §5's *"same final state"* means and
        // what `SubmitSnapshots.theReducedMotionSealLandsOnTheSamePixels` checks at zero
        // tolerance. SwiftUI's own animations end on their target the same way.
        if progress >= 1 { return .sealed }
        if progress <= 0 { return .unsealed }
        guard !reducedMotion else { return crossfade(progress) }
        return values(atMilliseconds: progress * Motion.Seal.end)
    }

    /// The values at a wall-clock instant inside the seal, in milliseconds from its start.
    ///
    /// This is the function `docs/09` §2 is a picture of, and the one the tests read. Every phase
    /// is evaluated independently and they overlap exactly as drawn — the cover is still settling
    /// at 380ms while the stamp is already landing.
    static func values(atMilliseconds time: Double) -> SealValues {
        let a = Curve.spring(response: 0.22, damping: 0.85)
            .value(elapsed: time - Motion.Seal.buttonCollapse.start)
        let b = Curve.bezier(0.20, 0.90, 0.10, 1.00, duration: Motion.Seal.coverSlide.duration)
            .value(elapsed: time - Motion.Seal.coverSlide.start)
        let c = Curve.spring(response: 0.18, damping: 0.62)
            .value(elapsed: time - Motion.Seal.settle.start)
        let d = Curve.spring(response: 0.28, damping: 0.72)
            .value(elapsed: time - Motion.Seal.stamp.start)
        let e = Curve.easeOut(duration: Motion.Seal.ring.duration)
            .value(elapsed: time - Motion.Seal.ring.start)
        let f = Curve.easeOut(duration: Motion.Seal.footer.duration)
            .value(elapsed: time - Motion.Seal.footer.start)

        return SealValues(
            coverTravel: b,
            coverOpacity: 1,
            // Phase C. The cover travels 2pt past flush on B's tail and the spring lifts it back,
            // dipping a hair beyond zero on the way — which is the difference between a panel
            // arriving and a lid closing. Continuous at the hand-over: B is at 0.93 by 320ms.
            coverOvershoot: Motion.Seal.overshoot * (time < Motion.Seal.settle.start ? b : 1 - c),
            artworkOffset: artworkLift * b,
            artworkScale: 1 + (artworkSettleScale - 1) * b,
            artworkBrightness: artworkDimming * b,
            // The shadow exists **only while moving**: a tent over the cover's travel, exactly
            // zero at both ends. `docs/07` §2 allows this one and nothing else.
            shadowRadius: shadowPeakRadius * moving(b),
            shadowOffset: shadowPeakOffset * moving(b),
            stampScale: stampEntryScale + (1 - stampEntryScale) * d,
            stampRotation: stampEntryRotation + (stampRestRotation - stampEntryRotation) * d,
            // The stamp fades in over the first third of its fall, so it is visible for the
            // landing rather than arriving already there.
            stampOpacity: min(1, d * 3),
            ringScale: 1 + (ringExpandedScale - 1) * e,
            // One ring, dissipating. Before phase E it does not exist at all — an `opacity` of
            // 0.35 sitting under the stamp from 0ms would be a halo, not an impact.
            ringOpacity: e <= 0 || e >= 1 ? 0 : ringEntryOpacity * (1 - e),
            actionCollapse: a,
            actionOpacity: actionOpacity(atMilliseconds: time),
            footerOpacity: f,
            footerOffset: footerEntryOffset * (1 - f)
        )
    }

    /// The reduced-motion path: one crossfade, same destination (`docs/09` §5).
    ///
    /// The artwork's own transform is taken to its final value rather than animated, because it
    /// ends underneath an opaque cover: interpolating it would be motion nobody can see, and
    /// skipping the *state* is what §5 forbids, not skipping the traversal.
    private static func crossfade(_ progress: Double) -> SealValues {
        var values = SealValues.sealed
        values.coverOpacity = progress
        values.stampOpacity = progress
        values.footerOpacity = progress
        values.footerOffset = 0
        values.actionOpacity = 1 - progress
        // No translation, no scale, no rotation, no ring, and no shadow — the cover never moves,
        // so there is nothing for a shadow to be cast by.
        values.actionCollapse = 0
        values.ringOpacity = 0
        values.ringScale = 1
        return values
    }

    /// A tent over a 0…1 travel: zero at both ends, one in the middle. `sin(πx)` rather than a
    /// triangle so the shadow grows and resolves without a corner in its derivative.
    private static func moving(_ travel: Double) -> Double {
        guard travel > 0, travel < 1 else { return 0 }
        return sin(.pi * travel)
    }

    /// Phase A's opacity: full until the last 40ms of the collapse, then out (`docs/09` §2).
    private static func actionOpacity(atMilliseconds time: Double) -> Double {
        let stage = Motion.Seal.buttonCollapse
        let fadeStart = stage.end - actionFadeDuration
        guard time > fadeStart else { return 1 }
        return max(0, 1 - (time - fadeStart) / actionFadeDuration)
    }

    /// The horizontal scale that collapses a button of this width into a 52pt pill.
    ///
    /// A scale and not a width: `.frame(width:)` re-lays-out its subtree on every frame, and
    /// `docs/09` §6 asserts the view-body count stays flat through the seal. A button narrower
    /// than the pill does not grow — `min` rather than a bare ratio.
    static func actionScale(width: CGFloat, collapse: Double) -> CGFloat {
        guard width > 0 else { return 1 - 0.84 * collapse }  // pre-layout fallback, ~52/330
        let target = min(1, actionCollapsedWidth / width)
        return 1 + (target - 1) * collapse
    }
}

// MARK: - Curves

/// The three curve shapes `docs/09` §2 names, as functions of elapsed milliseconds.
///
/// They exist because the seal is driven by **one** linear value and each phase applies its own
/// easing inside `SealTimeline`. Writing the spring out is not a re-implementation of SwiftUI's
/// for its own sake: it is what lets a test ask *"where is the stamp at 380ms"* and get an answer
/// that does not depend on a frame having been rendered.
enum Curve {
    case bezier(Double, Double, Double, Double, duration: Double)
    case easeOut(duration: Double)
    /// SwiftUI's `spring(response:dampingFraction:)`, as its unit-step response.
    case spring(response: Double, damping: Double)

    /// The curve's value for a number of milliseconds since **its own** start. Negative elapsed is
    /// 0 (the phase has not begun); past its duration is 1, except for a spring, which is allowed
    /// to still be settling.
    func value(elapsed: Double) -> Double {
        guard elapsed > 0 else { return 0 }
        switch self {
        case let .bezier(x1, y1, x2, y2, duration):
            guard elapsed < duration else { return 1 }
            return Curve.bezierValue(at: elapsed / duration, x1, y1, x2, y2)
        case let .easeOut(duration):
            guard elapsed < duration else { return 1 }
            let t = elapsed / duration
            // The standard ease-out cubic. `easeOut` in SwiftUI is a bezier(0, 0, 0.58, 1); this
            // is within a percent of it and has no solver in the hot path.
            return 1 - pow(1 - t, 3)
        case let .spring(response, damping):
            return Curve.springValue(elapsed: elapsed / 1000, response: response, damping: damping)
        }
    }

    /// A damped spring's unit-step response, which is what SwiftUI's spring animates along.
    ///
    /// `response` is the period of the undamped system, so `ω = 2π / response`; `damping` is ζ.
    /// Under-damped (every spring in `docs/09`) overshoots and rings; at ζ ≥ 1 it does not, and
    /// the critically-damped form is used instead so a future token cannot divide by zero.
    static func springValue(elapsed: Double, response: Double, damping: Double) -> Double {
        guard elapsed > 0 else { return 0 }
        let omega = 2 * Double.pi / response
        if damping < 1 {
            let damped = omega * (1 - damping * damping).squareRoot()
            let decay = exp(-damping * omega * elapsed)
            return 1 - decay * (cos(damped * elapsed)
                + (damping * omega / damped) * sin(damped * elapsed))
        }
        return 1 - exp(-omega * elapsed) * (1 + omega * elapsed)
    }

    /// A cubic bezier's y for a given x, by bisection.
    ///
    /// Bisection rather than Newton because it cannot diverge on the flat-then-steep curves this
    /// app uses, and twenty iterations is exact to five decimal places — which is more precision
    /// than a display has pixels for, and this runs off the render path anyway (a test, or one
    /// frame's worth of arithmetic).
    static func bezierValue(at x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        // The ends are exact rather than within a millionth of exact: bisection converges *toward*
        // 0 and 1, and a curve whose first frame is 1.3e-06 instead of 0 puts a sub-pixel offset on
        // a cover that has not started moving.
        guard x > 0 else { return 0 }
        guard x < 1 else { return 1 }

        func axis(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
            let inverse = 1 - t
            return 3 * inverse * inverse * t * p1 + 3 * inverse * t * t * p2 + t * t * t
        }
        var low = 0.0, high = 1.0
        for _ in 0..<20 {
            let mid = (low + high) / 2
            if axis(mid, x1, x2) < x { low = mid } else { high = mid }
        }
        return axis((low + high) / 2, y1, y2)
    }
}

// MARK: - Driving it

/// Runs the seal: flips the phase, fires the two haptics **at contact**, and reports when the
/// last pixel has stopped.
///
/// It owns no view and no timer of its own. The animation is SwiftUI's — one linear driver on
/// `progress` — and this type exists for the two things SwiftUI cannot express: feedback at an
/// instant inside the timeline, and an `await` that ends when the seal does.
///
/// > *"The seal animation never runs speculatively. It is a confirmation of a fact, and it must
/// > never have lied."* (`docs/08` §3.2)
///
/// So nothing here calls the API. `ConfirmScreen` seals first and runs this only on success.
@Observable @MainActor
final class SealAnimation {

    /// The one enum. Every moving property is a function of this (`docs/09` §2).
    private(set) var phase: SealPhase = .unsealed

    /// Whether the seal is mid-flight. The screen uses it to refuse a second tap; it is not what
    /// drives any pixel.
    private(set) var isRunning = false

    private let haptics: any HapticEngine

    init(haptics: any HapticEngine) {
        self.haptics = haptics
    }

    /// Runs the whole thing, returning when it has landed.
    ///
    /// - Parameter reducedMotion: `docs/09` §5. The crossfade still fires **one** haptic, at its
    ///   midpoint — reduced motion is not reduced feedback.
    func run(reducedMotion: Bool) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        // Warmed before the first note rather than at its instant: a cold generator delivers the
        // tap a frame or two late, which on a 100ms cue is the difference between feeling the
        // cover let go and feeling something happen afterwards.
        haptics.prepare(.coverMoves)
        haptics.prepare(.stampLands)

        let duration = reducedMotion ? Motion.Seal.reduced.duration : Motion.Seal.end
        // The single chain. One linear driver; every phase's own curve lives in `SealTimeline`,
        // which is what makes six overlapping phases one animation rather than six.
        withAnimation(.linear(duration: duration / 1000)) {
            phase = .sealed
        }

        if reducedMotion {
            await sleep(until: Motion.Seal.reducedHapticAt)
            haptics.fire(.stampLands)
            await sleep(until: Motion.Seal.reduced.duration)
            return
        }

        await sleep(until: Motion.Seal.coverMovesAt)
        haptics.fire(.coverMoves)
        await sleep(until: Motion.Seal.stampLandsAt - Motion.Seal.coverMovesAt)
        haptics.fire(.stampLands)
        await sleep(until: Motion.Seal.end - Motion.Seal.stampLandsAt)
    }

    /// Puts the card back, unanimated. Used when a **replacement** starts: the sheet reopens on
    /// the confirm layout, and a card that stayed sealed underneath would be a second sealed song.
    func reset() {
        phase = .unsealed
    }

    private func sleep(until milliseconds: Double) async {
        try? await Task.sleep(for: .milliseconds(Int(milliseconds.rounded())))
    }
}

// MARK: - Applying it

/// Which part of the seal a view is.
///
/// One modifier per part, each fed the same `progress`, because a single modifier cannot apply six
/// different transforms to six different subtrees — and because this is what keeps the
/// interpolation inside `Animatable` where SwiftUI runs it on the render thread, instead of in a
/// body that would be re-evaluated sixty times a second.
enum SealRole: Equatable, Sendable {
    /// The cover panel. Its travel is in points, so it needs the artwork's height — measured at
    /// rest by the `GeometryReader` that draws it, never during the animation.
    case cover(height: CGFloat)
    /// The artwork retreating under it.
    case artwork
    /// The stamp landing on the cover.
    case stamp
    /// The ring leaving the stamp.
    case ring
    /// The primary action collapsing. Width measured at rest for the same reason as the cover's
    /// height.
    case action(width: CGFloat)
    /// The countdown and *"Sealed until 8:00."* arriving.
    case footer
}

/// The seal applied to one part, interpolated on the render thread.
///
/// `Animatable` is the whole point: SwiftUI drives `animatableData` frame by frame and calls this
/// modifier's `body` — not the screen's. `docs/09` §6's *"view-body counts flat during the
/// animation"* is a property of that arrangement rather than a thing to remember.
struct SealEffect: ViewModifier, Animatable {
    var progress: Double
    let role: SealRole
    let reducedMotion: Bool

    /// `nonisolated` because SwiftUI drives it off the main actor, sixty times a second, while the
    /// `ViewModifier` half of this type is main-actor isolated. That split is the arrangement, not
    /// a wrinkle in it: the interpolation happens on the render thread and only its *result*
    /// reaches a body.
    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private var values: SealValues {
        SealTimeline.values(progress: progress, reducedMotion: reducedMotion)
    }

    func body(content: Content) -> some View {
        let values = values
        switch role {
        case let .cover(height):
            content
                // A translation, not a height: the cover is always its full size and slides in
                // from above, so nothing in the tree re-lays-out as it arrives.
                .offset(y: -height * (1 - values.coverTravel) + values.coverOvershoot)
                .opacity(values.coverOpacity)
                .shadow(
                    color: Palette.ink.opacity(SealTimeline.shadowOpacity),
                    radius: values.shadowRadius,
                    y: values.shadowOffset
                )
        case .artwork:
            content
                .scaleEffect(values.artworkScale)
                .offset(y: values.artworkOffset)
                .brightness(values.artworkBrightness)
        case .stamp:
            content
                .scaleEffect(values.stampScale)
                .rotationEffect(.degrees(values.stampRotation))
                .opacity(values.stampOpacity)
        case .ring:
            content
                .scaleEffect(values.ringScale)
                .opacity(values.ringOpacity)
        case let .action(width):
            content
                .scaleEffect(x: SealTimeline.actionScale(width: width, collapse: values.actionCollapse))
                .opacity(values.actionOpacity)
        case .footer:
            content
                .opacity(values.footerOpacity)
                .offset(y: values.footerOffset)
        }
    }
}

extension View {
    /// Applies the seal to this part of the screen.
    ///
    /// The animation is not declared here: the caller flips one `SealPhase` inside
    /// `withAnimation` (`SealAnimation.run(reducedMotion:)`) and every part follows. That is the
    /// single chain, and it is why there is no per-part `.animation(_:value:)` to get out of sync.
    func seal(_ phase: SealPhase, as role: SealRole, reducedMotion: Bool = false) -> some View {
        modifier(SealEffect(progress: phase.progress, role: role, reducedMotion: reducedMotion))
    }
}
