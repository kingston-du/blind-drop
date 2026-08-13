import Foundation
import Testing
@testable import BlindDrop

@MainActor
@Suite struct UnsealAnimationTests {

    @Test func belowFoldCardsWaitForTheirOwnAppearance() async {
        let haptics = CountingHaptics()
        let animation = makeAnimation(cards: [1, 2], haptics: haptics)
        animation.updateVisibleCards([1])

        await animation.run(reducedMotion: false)

        #expect(animation.phase(for: 1) == .revealed)
        #expect(animation.phase(for: 2) == .sealed)

        animation.updateVisibleCards([2])
        #expect(animation.phase(for: 2) == .revealed)
        #expect(haptics.fired == [.coverMoves])
    }

    @Test func theSequenceFiresExactlyOneSoftHaptic() async {
        let haptics = CountingHaptics()
        let animation = makeAnimation(cards: Array(1...12), haptics: haptics)
        animation.updateVisibleCards(Set(1...12))

        await animation.run(reducedMotion: true)

        #expect(animation.revealedCards == Set(1...12))
        #expect(haptics.prepared == [.coverMoves])
        #expect(haptics.fired == [.coverMoves])
    }

    @Test func aRoundRunsOnlyOnceAcrossRelaunch() async {
        let defaults = RoundFixture.scratchDefaults()
        let firstFlags = LocalFlags(defaults: defaults)
        let firstHaptics = CountingHaptics()
        let first = UnsealAnimation(
            roundID: "round-once",
            cardNumbers: [1, 2],
            flags: firstFlags,
            haptics: firstHaptics
        )
        first.updateVisibleCards([1, 2])
        await first.run(reducedMotion: true)

        let relaunched = UnsealAnimation(
            roundID: "round-once",
            cardNumbers: [1, 2],
            flags: LocalFlags(defaults: defaults),
            haptics: CountingHaptics()
        )

        #expect(firstFlags.hasSeenUnseal(roundID: "round-once"))
        #expect(relaunched.revealedCards == [1, 2])
    }

    private func makeAnimation(
        cards: [Int],
        haptics: CountingHaptics
    ) -> UnsealAnimation {
        UnsealAnimation(
            roundID: "round-\(cards.count)-\(UUID().uuidString)",
            cardNumbers: cards,
            flags: LocalFlags(defaults: RoundFixture.scratchDefaults()),
            haptics: haptics
        )
    }
}
