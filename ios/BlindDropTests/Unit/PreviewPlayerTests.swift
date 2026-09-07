import AVFoundation
import Foundation
import Testing
@testable import BlindDrop

/// `docs/06` §4's four preview rules, and `docs/12` §7's one.
///
/// The audio session is behind a protocol so this suite can assert *when* it is configured and
/// deactivated without touching the process-wide singleton — a test that activated a `.playback`
/// session would stop the music on the machine running it.
@MainActor
@Suite struct PreviewPlayerTests {

    private func makePlayer() -> (PreviewPlayer, FakeAudioSession) {
        let session = FakeAudioSession()
        // No notification observers under test: there is no app here to background, and a
        // live subscription would be a second thing running alongside the assertions.
        return (PreviewPlayer(player: AVPlayer(), session: session, observesInterruptions: false), session)
    }

    /// **Nothing autoplays, ever, under any setting** (`docs/12` §7). A freshly built player is
    /// silent, and only a tap starts one.
    @Test func nothingPlaysUntilSomebodyTapsPlay() {
        let (player, session) = makePlayer()
        #expect(player.playing == nil)
        #expect(!session.didConfigure, "and the session is untouched until first play")
    }

    /// **One at a time.** Starting a second preview stops the first.
    @Test func startingASecondPreviewStopsTheFirst() throws {
        let (player, _) = makePlayer()

        player.toggle(.ribs)
        #expect(player.playing == TrackDTO.ribs.trackKey)

        player.toggle(.motionSickness)
        #expect(player.playing == TrackDTO.motionSickness.trackKey, "the second one is playing")
    }

    /// Tapping the playing row's control stops it.
    @Test func tappingTheSameTrackStopsIt() {
        let (player, _) = makePlayer()

        player.toggle(.ribs)
        player.toggle(.ribs)

        #expect(player.playing == nil)
    }

    /// **The session is configured on first play only** (`docs/06` §4). Configuring at launch
    /// would stop the music of somebody who never taps a preview.
    @Test func thesessionIsConfiguredOnceAndOnFirstPlay() {
        let (player, session) = makePlayer()

        player.toggle(.ribs)
        #expect(session.didConfigure)
        #expect(session.configureCount == 1)

        player.toggle(.motionSickness)
        player.toggle(.ribs)
        #expect(session.configureCount == 1, "the category is set once, not per play")
    }

    /// **And deactivated at the end, so the user's music resumes.**
    @Test func stoppingHandsTheSessionBack() {
        let (player, session) = makePlayer()

        player.toggle(.ribs)
        #expect(session.isActive)

        player.stop()
        #expect(!session.isActive, "the user's music can start again")
    }

    /// Stopping twice is not two deactivations. `stop()` is called from a tap *and* from the
    /// sheet's `onDisappear`, and an unbalanced session is how the user's music stays paused.
    @Test func stoppingIsIdempotent() {
        let (player, session) = makePlayer()
        player.toggle(.ribs)

        player.stop()
        player.stop()

        #expect(session.deactivateCount == 1)
    }

    /// **A track with no preview has no control**, so there is no tap to handle — and if one
    /// arrives anyway, nothing plays (`docs/06` §7).
    @Test func atrackWithNoPreviewCannotBePlayed() {
        let (player, session) = makePlayer()

        player.toggle(.longTitle)

        #expect(player.playing == nil)
        #expect(!session.didConfigure)
    }
}

/// An audio session that records instead of interrupting anybody's music.
@MainActor
final class FakeAudioSession: AudioSession {
    private(set) var configureCount = 0
    private(set) var deactivateCount = 0
    private(set) var isActive = false

    var didConfigure: Bool { configureCount > 0 }

    func configure() { configureCount += 1 }
    func activate() { isActive = true }
    func deactivate() {
        deactivateCount += 1
        isActive = false
    }
}

/// The two tracks the component snapshots already use, plus the one with no preview.
///
/// `BlindDropTests/Unit` and `BlindDropTests/Snapshot` are separate targets and share no code, so
/// the unit target carries its own copies (`RevealSnapshotTests` says the same of its fixtures).
extension TrackDTO {
    static let ribs = make(key: "isrc:NZUM71300123", title: "Ribs", artist: "Lorde", appleID: "1440857781")
    static let motionSickness = make(
        key: "isrc:USUM71703861", title: "Motion Sickness", artist: "Phoebe Bridgers", appleID: "1440857782"
    )
    /// No `preview_url`, which is a real state and not a broken one (`docs/06` §7).
    static let longTitle = make(
        key: "am:1234567890", title: "Everything Is Embarrassing (Extended Mix)",
        artist: "Sky Ferreira", appleID: "1234567890", preview: nil
    )

    private static func make(
        key: String,
        title: String,
        artist: String,
        appleID: String,
        preview: URL? = URL(string: "https://example.test/preview.m4a")
    ) -> TrackDTO {
        TrackDTO(
            trackKey: key,
            isrc: key.hasPrefix("isrc:") ? String(key.dropFirst(5)) : nil,
            title: title,
            artist: artist,
            album: "—",
            artworkURL: "https://example.test/{w}x{h}bb.jpg",
            artworkBackgroundColor: "1d2b3a",
            durationMilliseconds: 240_000,
            previewURL: preview,
            appleMusicID: appleID,
            appleMusicURL: URL(string: "https://music.apple.com/us/song/x/\(appleID)")!,
            spotifyID: nil,
            spotifyURL: nil
        )
    }
}
