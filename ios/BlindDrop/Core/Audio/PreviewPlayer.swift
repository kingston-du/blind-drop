import AVFoundation
import Foundation

/// The 30-second preview (`docs/06` §4, *Previews*).
///
/// Four rules, all of them in that section, and each one is a line of code somebody would
/// otherwise get wrong:
///
/// 1. **One at a time.** Starting a second preview stops the first. There is one `AVPlayer` for
///    the whole app and it is here.
/// 2. **Never autoplays.** Nothing in this type starts playback except `toggle(_:)`, which is a
///    tap. `docs/12` §7: *"nothing autoplays audio, ever, under any setting."*
/// 3. **The audio session is configured on first play only** — not at launch. Activating a
///    `.playback` session is what stops the user's music, and doing it when the app opens would
///    stop it for somebody who never taps a preview.
/// 4. **And deactivated at the end**, so their music resumes. Without `notifyOthersOnDeactivation`
///    it does not: the other app is never told it may start again.
///
/// `.duckOthers` is deliberately **off** (`docs/12` §7): a preview must not duck VoiceOver
/// mid-sentence, and a 30-second clip the user asked for should be the only thing playing anyway.
@Observable @MainActor
final class PreviewPlayer {

    /// Which track is playing, by `track_key`, or `nil` when nothing is. The one piece of state a
    /// view needs: a row asks *"is it me"* and draws its control from the answer.
    private(set) var playing: String?

    private let player: AVPlayer
    private let session: any AudioSession
    /// Whether the category has been set. Once is enough, and once is all `docs/06` §4 allows.
    private var isConfigured = false
    /// Watches for the clip ending so the session can be released. Cancelled and replaced per
    /// play; never a notification observer that outlives the sound (`docs/13` §6).
    private var completion: Task<Void, Never>?

    /// - Parameters:
    ///   - player: injectable so a test can drive the state machine without a decoder.
    ///   - session: the audio session, behind a protocol for the same reason —
    ///     `AVAudioSession.sharedInstance()` is process-wide, and a unit test that activated it
    ///     would stop the music on the machine running it.
    init(player: AVPlayer = AVPlayer(), session: any AudioSession = SystemAudioSession()) {
        self.player = player
        self.session = session
        player.actionAtItemEnd = .pause
    }

    /// Plays this track's preview, or stops it if it is the one already playing.
    ///
    /// A track with no `preview_url` cannot get here: `docs/06` §7 gives it **no control at all**,
    /// so there is no tap to handle and no disabled state to model.
    func toggle(_ track: TrackDTO) {
        guard let url = track.previewURL else { return }
        if playing == track.trackKey {
            stop()
            return
        }
        // Whatever was playing stops first — including its session teardown, so two overlapping
        // previews cannot leave the session activated twice.
        stop()

        if !isConfigured {
            session.configure()
            isConfigured = true
        }
        session.activate()

        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.seek(to: .zero)
        player.play()
        playing = track.trackKey

        let key = track.trackKey
        completion = Task { [weak self] in
            // The clip is 30 seconds; polling at 4Hz costs nothing and needs no
            // `NotificationCenter` observer whose lifetime is a second thing to get wrong. The
            // task is cancelled by `stop()`, so it does not outlive the sound.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, self.playing == key else { return }
                if self.hasFinished { self.stop(); return }
            }
        }
    }

    /// Stops whatever is playing and hands the session back.
    ///
    /// Idempotent, and called from `onDisappear` as well as from a tap: a preview that kept
    /// playing after its sheet was dismissed would be a sound with no visible way to stop it.
    func stop() {
        completion?.cancel()
        completion = nil
        guard playing != nil else { return }
        player.pause()
        player.replaceCurrentItem(with: nil)
        playing = nil
        // The user's music resumes here, and only if the deactivation says so.
        session.deactivate()
    }

    /// Whether the current item has run out. `nil` duration (still loading) is not finished.
    private var hasFinished: Bool {
        guard let item = player.currentItem else { return true }
        let duration = item.duration.seconds
        guard duration.isFinite, duration > 0 else { return false }
        return item.currentTime().seconds >= duration - 0.05
    }
}

/// The three things this app does to the audio session, and nothing else.
///
/// A protocol so `PreviewPlayer` is testable off-device: the real implementation touches a
/// process-wide singleton owned by the OS, which a unit suite must not do.
@MainActor
protocol AudioSession: AnyObject {
    /// Sets the category. Called once, on first play (`docs/06` §4).
    func configure()
    func activate()
    /// Deactivates **and notifies others**, so the user's music starts again.
    func deactivate()
}

/// `AVAudioSession`, with the two options `docs/06` §4 and `docs/12` §7 specify.
@MainActor
final class SystemAudioSession: AudioSession {
    private let session = AVAudioSession.sharedInstance()

    init() {}

    func configure() {
        // `.playback` so a preview the user explicitly asked for plays through the silent switch,
        // and no `.duckOthers` so it never talks over VoiceOver (`docs/12` §7).
        try? session.setCategory(.playback, mode: .default, options: [])
    }

    func activate() {
        try? session.setActive(true)
    }

    func deactivate() {
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }
}
