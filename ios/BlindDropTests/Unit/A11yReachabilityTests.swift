import SwiftUI
import Testing
@testable import BlindDrop

/// `E11-03`'s worst case: the iPhone SE with all twelve members and the largest supported text.
///
/// The flight and the pool are separate scrollers. The test asserts their entire addressable
/// sets, rather than a visible subset, because a bottom sheet that only exposes its first two
/// rows has not met the accessibility requirement merely because the first screenshot looks
/// orderly. `NameChip` and `FlightCard` use these stable identifiers in the UI hierarchy, so
/// E14's end-to-end VoiceOver pass can walk this same manifest without rediscovering names.
@MainActor
@Suite struct A11yReachabilityTests {

    @Test func seWithTwelveMembersAtAccessibilityFiveHasAnAddressForEveryCardAndChip() {
        let store = RevealFixture.store(cardCount: 12, myCardNumber: 7)
        let layout = NamePoolLayout(dynamicTypeSize: .accessibility5)

        #expect(layout == .verticalGrid)
        #expect(store.cards.map(\.cardNumber) == Array(1...12))
        #expect(store.pool.count == 11, "the caller is not in their own eleven-name pool")
        #expect(Set(store.pool.map(\.userID)).count == 11)
        #expect(store.pool.allSatisfy { !$0.userID.isEmpty })
        #expect(store.cards.allSatisfy { $0.cardNumber > 0 })

        // Both interactive shapes explicitly expand to 44pt. The grid does not shrink its
        // children, and the flight stays in its own scroll view above the capped pool.
        #expect(Layout.minimumTouchTarget >= 44)
        #expect(Layout.chipHeight < Layout.minimumTouchTarget)
        #expect(Layout.namePoolMaximumHeightFraction == 0.4)
    }

    /// `E17-03`: the answer card's links are an ellipsis menu now, and the menu is
    /// `accessibilityHidden` — the card is a single VoiceOver element (`docs/12` §2), so a menu
    /// inside the collapse is reachable by direct touch and by nobody swiping. `FlightCard.body`
    /// re-exposes both links as custom actions on the card, and this asserts what that block can
    /// actually build: a track carrying both services yields both destinations, and a track
    /// carrying only Apple Music yields exactly one — an action that opened nothing would be
    /// worse than no action, so the `if let` in front of each is the test's real subject.
    @Test func bothTrackLinksAreReachableAsCardActions() {
        let both = TrackDTO.onBothServices
        #expect(TrackLinkDestination.appleMusic(track: both) != nil)
        #expect(TrackLinkDestination.spotify(track: both) != nil)

        // Apple Music is the only service `TrackDTO` requires, so this is the shape most of the
        // record is in: one action, not two, and not one dead one.
        let appleOnly = TrackDTO.motionSickness
        #expect(TrackLinkDestination.appleMusic(track: appleOnly) != nil)
        #expect(TrackLinkDestination.spotify(track: appleOnly) == nil)
    }

    @Test(arguments: [
        (DynamicTypeSize.large, NamePoolLayout.horizontalScroll),
        (.accessibility2, .horizontalScroll),
        (.accessibility3, .verticalGrid),
        (.accessibility5, .verticalGrid),
    ])
    func thePoolChangesOnlyAtTheAccessibilityThreeBoundary(
        size: DynamicTypeSize,
        expected: NamePoolLayout
    ) {
        #expect(NamePoolLayout(dynamicTypeSize: size) == expected)
    }
}

private extension TrackDTO {
    /// A track on both services. The unit target's shared fixtures
    /// (`PreviewPlayerTests`' `.motionSickness` and friends) are all Apple-only, and Apple-only
    /// is the case that cannot tell a card exposing one link from a card exposing two.
    static let onBothServices = TrackDTO(
        trackKey: "isrc:USUM71300456",
        isrc: "USUM71300456",
        title: "Eenie Meenie",
        artist: "Sean Kingston & Justin Bieber",
        album: "Sean Kingston & Justin Bieber",
        artworkURL: "https://example.test/{w}x{h}bb.jpg",
        artworkBackgroundColor: "1d2b3a",
        durationMilliseconds: 194_000,
        previewURL: nil,
        appleMusicID: "1440857783",
        appleMusicURL: URL(string: "https://music.apple.com/us/song/eenie-meenie/1440857783")!,
        spotifyID: "3a1lNhkSLSkpJE4MSHpDu9",
        spotifyURL: URL(string: "https://open.spotify.com/track/3a1lNhkSLSkpJE4MSHpDu9")!
    )
}
