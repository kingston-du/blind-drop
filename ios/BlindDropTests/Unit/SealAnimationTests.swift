import Foundation
import Testing
@testable import BlindDrop

/// `docs/09` §6's haptic row: *"seal fires 2, unseal fires 1, reduced-motion seal fires 1."*
///
/// The unseal's is `E11-04`'s to assert when it lands. The two seal rows are here, and they are
/// answerable because `HapticEngine` is a protocol and `SealAnimation` takes one — `docs/09` §6
/// asks for counts, and a count only means something if the thing counted is *"the stamp landed"*
/// rather than *"some rigid impact happened somewhere"* (`Haptics.swift`).
@MainActor
@Suite struct SealAnimationTests {

    /// Two notes, in order, and they are the two `docs/09` §2 names: the cover being let go and
    /// the stamp making contact.
    @Test func theSealFiresTwoHaptics() async {
        let haptics = CountingHaptics()
        let animation = SealAnimation(haptics: haptics)

        await animation.run(reducedMotion: false)

        #expect(haptics.fired == [.coverMoves, .stampLands])
        #expect(animation.phase == .sealed)
        #expect(!animation.isRunning)
    }

    /// **Reduced motion is not reduced feedback** (`docs/09` §5). One note, and the landed state
    /// is the same one.
    @Test func theReducedMotionSealStillFiresOnce() async {
        let haptics = CountingHaptics()
        let animation = SealAnimation(haptics: haptics)

        await animation.run(reducedMotion: true)

        #expect(haptics.fired.count == 1)
        #expect(animation.phase == .sealed)
    }

    /// The generators are warmed before the first note. A cold generator delivers the tap a frame
    /// or two late, and on a 100ms cue that is the difference between feeling the cover let go and
    /// feeling something happen afterwards.
    ///
    /// **Exactly the seal's own two, not `Haptic.allCases`.** The assertion used to be the
    /// all-cases one, and it was right until `E17-07` added a third note that the seal can never
    /// fire: `.nameLands` belongs to the reveal, and a submit screen that warms a generator for a
    /// tap it will never play is a lie in the code as well as wasted Taptic time. What the
    /// all-cases form was really protecting — *no note can fire cold* — is asserted whole by
    /// `everyNoteIsWarmedBySomebody` below, which is a stronger claim than this test ever made.
    @Test func bothGeneratorsAreWarmedFirst() async {
        let haptics = CountingHaptics()
        await SealAnimation(haptics: haptics).run(reducedMotion: false)
        #expect(Set(haptics.prepared) == [.coverMoves, .stampLands])
    }

    /// **No note can fire cold.** The property the all-cases assertion above used to carry,
    /// stated where it is actually true: across the three places that fire haptics, the union of
    /// what they warm is the whole vocabulary. A fourth `Haptic` case added without a warm-up
    /// fails here, which is the failure `E17-07` shipped and this slice is closing.
    @Test func everyNoteIsWarmedBySomebody() async {
        let seal = CountingHaptics()
        await SealAnimation(haptics: seal).run(reducedMotion: false)

        let unseal = CountingHaptics()
        await UnsealAnimation(
            roundID: "r1",
            cardNumbers: [1],
            flags: LocalFlags(defaults: UserDefaults(suiteName: #function)!),
            haptics: unseal
        ).run(reducedMotion: true)

        let reveal = CountingHaptics()
        RevealStore(
            cards: [],
            pool: [],
            myCardNumber: nil,
            canGuess: true,
            me: nil,
            haptics: reveal
        ).prepareHaptics()

        let warmed = Set(seal.prepared) .union(unseal.prepared) .union(reveal.prepared)
        #expect(warmed == Set(Haptic.allCases))
    }

    /// A second tap while the first seal is running does nothing — no second timeline, no third
    /// and fourth haptic. The animation is a confirmation of one fact and there is only one.
    @Test func asecondRunIsIgnoredWhileTheFirstIsInFlight() async {
        let haptics = CountingHaptics()
        let animation = SealAnimation(haptics: haptics)

        async let first: Void = animation.run(reducedMotion: false)
        // Long enough to be inside the first run, short enough to be well before it ends.
        try? await Task.sleep(for: .milliseconds(50))
        await animation.run(reducedMotion: false)
        await first

        #expect(haptics.fired == [.coverMoves, .stampLands])
    }

    /// A replacement starts from the confirm layout again (`docs/08` §4). Resetting is not an
    /// animation — the sheet is closed and the card behind it is about to be replaced.
    @Test func resettingReturnsToTheUnsealedPhase() async {
        let animation = SealAnimation(haptics: CountingHaptics())
        await animation.run(reducedMotion: true)
        #expect(animation.phase == .sealed)

        animation.reset()
        #expect(animation.phase == .unsealed)
    }
}

/// A haptic engine that counts instead of buzzing.
@MainActor
final class CountingHaptics: HapticEngine {
    private(set) var fired: [Haptic] = []
    private(set) var prepared: [Haptic] = []

    func fire(_ haptic: Haptic) { fired.append(haptic) }
    func prepare(_ haptic: Haptic) { prepared.append(haptic) }
}
