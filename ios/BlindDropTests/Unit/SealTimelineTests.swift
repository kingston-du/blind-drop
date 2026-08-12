import Foundation
import Testing
@testable import BlindDrop

/// The seal, read frame by frame without rendering one (`docs/09` §2).
///
/// `SealTimeline` is a pure function of time, which is the property that makes the checklist's
/// three test lines answerable at all: *"zero SwiftUI layout passes"*, *"haptic counts"* and
/// *"reduced-motion final state is pixel-identical to the normal path's"*. The last one is
/// asserted here as **value equality**, which is stronger than a pixel diff and cannot drift with
/// a font rendering change.
@Suite struct SealTimelineTests {

    // MARK: - The two ends

    /// At rest, nothing has happened: the cover is above the artwork, the stamp is absent, the
    /// action is whole.
    @Test func theTimelineStartsAtTheConfirmLayout() {
        #expect(SealTimeline.values(progress: 0) == .unsealed)
    }

    /// And it lands exactly on the state `SealedCard` draws by itself.
    @Test func theTimelineEndsOnTheLandedCard() {
        #expect(SealTimeline.values(progress: 1) == .sealed)
    }

    /// **`docs/09` §5, the checklist's third test line.** Reduced motion is a different journey to
    /// the same place — not a different destination, and not a state skipped.
    @Test func reducedMotionEndsInTheIdenticalState() {
        #expect(SealTimeline.values(progress: 1, reducedMotion: true)
                == SealTimeline.values(progress: 1, reducedMotion: false))
    }

    /// And it starts from the same layout, so the crossfade has the same two ends the full path
    /// has. Everything except the cover, stamp, footer and action is already final — under
    /// reduced motion those four are the crossfade and the rest never moves.
    @Test func reducedMotionCrossfadesRatherThanTravelling() {
        let midway = SealTimeline.values(progress: 0.5, reducedMotion: true)
        #expect(midway.coverTravel == 1, "no translation under reduced motion")
        #expect(midway.coverOvershoot == 0, "no overshoot under reduced motion")
        #expect(midway.stampScale == 1, "no scale under reduced motion")
        #expect(midway.stampRotation == SealTimeline.stampRestRotation, "no rotation, and still off-axis")
        #expect(midway.ringOpacity == 0, "no ring under reduced motion")
        #expect(midway.shadowRadius == 0, "nothing is moving, so nothing casts a shadow")
        // It is a *crossfade*: the two layers are genuinely mid-fade at the midpoint.
        #expect(midway.coverOpacity == 0.5)
        #expect(midway.actionOpacity == 0.5)
    }

    // MARK: - The transients

    /// **The only shadow in the app** (`docs/07` §2), and only while the cover is moving.
    ///
    /// Zero at both ends is the assertion that matters: a shadow that lingered on the landed card
    /// would be the app's one exception quietly becoming a permanent drop shadow.
    @Test func theShadowExistsOnlyWhileTheCoverIsMoving() {
        #expect(SealTimeline.values(atMilliseconds: 0).shadowRadius == 0)
        #expect(SealTimeline.values(atMilliseconds: Motion.Seal.end).shadowRadius == 0)
        #expect(SealTimeline.values(atMilliseconds: Motion.Seal.end).shadowOffset == 0)

        let travelling = SealTimeline.values(atMilliseconds: 200)
        #expect(travelling.shadowRadius > 0)
        #expect(travelling.shadowRadius <= SealTimeline.shadowPeakRadius)
        #expect(travelling.shadowOffset > 0)
    }

    /// One ring, and it is gone by the end (`docs/09` §2, phase E). Not three, not a pulse loop,
    /// and not a halo sitting under the stamp from the first frame.
    @Test func theRingIsOneTransient() {
        #expect(SealTimeline.values(atMilliseconds: 0).ringOpacity == 0)
        #expect(SealTimeline.values(atMilliseconds: Motion.Seal.ring.start).ringOpacity == 0)
        #expect(SealTimeline.values(atMilliseconds: Motion.Seal.end).ringOpacity == 0)

        let mid = SealTimeline.values(atMilliseconds: 540)
        #expect(mid.ringOpacity > 0)
        #expect(mid.ringOpacity <= SealTimeline.ringEntryOpacity)
        #expect(mid.ringScale > 1)
    }

    /// The cover goes **past** flush and comes back — a lid closing rather than a panel arriving
    /// (`docs/09` §2, phase C).
    @Test func theCoverOvershootsAndSettles() {
        let arriving = SealTimeline.values(atMilliseconds: Motion.Seal.settle.start)
        #expect(arriving.coverOvershoot > 1, "it should be nearly 2pt past flush as C takes over")

        let settled = SealTimeline.values(atMilliseconds: Motion.Seal.end)
        #expect(abs(settled.coverOvershoot) < 0.01, "and flush by the end")
    }

    // MARK: - The phases in order

    /// The stamp lands **off-axis by 4°**. `docs/09`: *"Do not 'fix' this."*
    @Test func theStampLandsOffAxisByFourDegrees() {
        #expect(SealTimeline.values(progress: 1).stampRotation == -4)
        #expect(SealValues.sealed.stampRotation == -4)
    }

    /// The stamp is visible for its landing rather than arriving already there, and it is
    /// **absent** before its phase starts.
    @Test func theStampArrivesDuringItsOwnPhase() {
        #expect(SealTimeline.values(atMilliseconds: Motion.Seal.stamp.start).stampOpacity == 0)
        // At 380ms the stamp is on screen and still falling — which is what the rigid note is
        // announcing. `docs/09` §2 puts contact 20ms into a 180ms spring, so *"landed"* is not the
        // claim being made here; "visible, arriving, and felt" is.
        let atContact = SealTimeline.values(atMilliseconds: Motion.Seal.stampLandsAt)
        #expect(atContact.stampOpacity > 0, "it is on screen when the haptic fires")
        #expect(atContact.stampScale > 1, "and still above its landed size")
        #expect(SealTimeline.values(atMilliseconds: Motion.Seal.stamp.end).stampScale < 1.05,
                "and has all but landed at 1.0 when its phase ends")
    }

    /// Phase A's opacity falls over **the last 40ms** of the collapse, not across all of it.
    @Test func theActionFadesOnlyAtTheEndOfItsCollapse() {
        #expect(SealTimeline.values(atMilliseconds: 0).actionOpacity == 1)
        #expect(SealTimeline.values(atMilliseconds: 70).actionOpacity == 1)
        #expect(SealTimeline.values(atMilliseconds: 100).actionOpacity < 1)
        #expect(SealTimeline.values(atMilliseconds: 120).actionOpacity == 0)
    }

    /// The cover is not still arriving when the stamp hits it. Overlap is the point of the
    /// timeline, but *this* pair has an order: something has to be there to stamp.
    @Test func theCoverHasLandedBeforeTheStampDoes() {
        let atContact = SealTimeline.values(atMilliseconds: Motion.Seal.stampLandsAt)
        #expect(atContact.coverTravel == 1)
    }

    /// The artwork retreats under the cover as it arrives: `y: 0 → -8`, `scale → 0.98`, dimmed.
    @Test func theArtworkRetreatsUnderTheCover() {
        let landed = SealTimeline.values(progress: 1)
        #expect(landed.artworkOffset == -8)
        #expect(landed.artworkScale == 0.98)
        #expect(landed.artworkBrightness == -0.08)
    }

    // MARK: - The collapse is a scale, not a width

    /// A 52pt pill out of a full-width button, expressed as the scale that gets there — because a
    /// width animation re-lays-out its subtree on every frame (`docs/09` §2, §6).
    @Test func theActionCollapsesToA52PointPill() {
        #expect(SealTimeline.actionScale(width: 335, collapse: 0) == 1)
        let collapsed = SealTimeline.actionScale(width: 335, collapse: 1)
        #expect(abs(collapsed * 335 - Layout.buttonHeight) < 0.001, "52pt of a 335pt button")
    }

    /// A button narrower than the pill does not *grow* into it.
    @Test func theCollapseNeverExpandsANarrowButton() {
        #expect(SealTimeline.actionScale(width: 40, collapse: 1) == 1)
    }

    /// Before layout has measured anything, the fallback still collapses rather than freezing the
    /// button at full width mid-seal.
    @Test func theCollapseHasAPreLayoutFallback() {
        #expect(SealTimeline.actionScale(width: 0, collapse: 1) < 0.2)
    }

    // MARK: - The curves

    /// A spring's unit step: starts at zero, passes one (it is under-damped, so it overshoots),
    /// and settles back on one.
    @Test func theSpringOvershootsAndSettles() {
        #expect(Curve.springValue(elapsed: 0, response: 0.28, damping: 0.72) == 0)
        let overshooting = (1...40).map { Curve.springValue(elapsed: Double($0) / 100, response: 0.28, damping: 0.72) }
        #expect(overshooting.contains { $0 > 1 }, "an under-damped spring passes its target")
        #expect(abs(Curve.springValue(elapsed: 2, response: 0.28, damping: 0.72) - 1) < 0.001)
    }

    /// The bezier is monotonic and hits both ends, which is what a timing curve has to be for the
    /// cover's travel to never go backwards.
    @Test func theBezierIsMonotonicBetweenZeroAndOne() {
        let samples = stride(from: 0.0, through: 1.0, by: 0.05)
            .map { Curve.bezierValue(at: $0, 0.20, 0.90, 0.10, 1.00) }
        #expect(samples.first == 0)
        #expect(abs((samples.last ?? 0) - 1) < 0.001)
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 + 0.0001 })
    }
}
