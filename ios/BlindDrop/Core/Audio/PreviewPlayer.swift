import AVFoundation
import Foundation
import UIKit

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
///
/// A fifth rule, which is rules 1 and 4 restated for the two ways a preview ends without anybody
/// tapping anything: **the sound going away for a reason outside this app is still the sound
/// ending.** The app declares no background audio mode, so the system pauses the player the
/// moment it backgrounds, and a phone call takes the session outright. Neither tells this type,
/// which is what left `playing` pointing at a track that had gone silent: the row kept its pause
/// control, the session was never handed back so the user's own music never resumed, and the
/// first tap on that control read as *"stop the thing already playing"* and did nothing audible
/// — a preview that took two taps to restart. `observeInterruptions()` is the fix, and it lives
/// here rather than in a `scenePhase` handler on each screen because there are five screens that
/// play previews and an interruption is not a scene phase on any of them.
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
    /// The app going to the background, and a call taking the session — the two things that
    /// silence a preview without a tap. See `observeInterruptions()`.
    private var interruptions: Task<Void, Never>?
    private var interrupted: Task<Void, Never>?

    /// - Parameters:
    ///   - player: injectable so a test can drive the state machine without a decoder.
    ///   - session: the audio session, behind a protocol for the same reason —
    ///     `AVAudioSession.sharedInstance()` is process-wide, and a unit test that activated it
    ///     would stop the music on the machine running it.
    ///   - observesInterruptions: off in the unit suite, where there is no app to background and
    ///     a live `NotificationCenter` subscription is a second thing running under the test.
    init(
        player: AVPlayer = AVPlayer(),
        session: any AudioSession = SystemAudioSession(),
        observesInterruptions: Bool = true
    ) {
        self.player = player
        self.session = session
        player.actionAtItemEnd = .pause
        if observesInterruptions { observeInterruptions() }
    }

    /// Ends the preview when the system does, rather than when a finger does.
    ///
    /// Two notifications, one handler, because the user-visible answer is the same for both: the
    /// clip is over. `stop()` is idempotent and no-ops when nothing is playing, so a background
    /// with no preview running costs a comparison.
    ///
    /// `[weak self]` and no explicit teardown, which is the same bargain `CountdownTimer`'s
    /// ticker makes and for the same reason: the loop wakes only when one of these actually
    /// fires, and the first wake after this player is gone returns. There is no `deinit` here to
    /// get wrong.
    private func observeInterruptions() {
        // Backgrounding, not resigning active: the app switcher and a Control Centre pull both
        // resign active without stopping the audio, and killing a preview for a swipe the user
        // cancelled would be the more annoying bug.
        interruptions = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: UIApplication.didEnterBackgroundNotification
            ) {
                guard let self else { return }
                self.stop()
            }
        }
        interrupted = Task { @MainActor [weak self] in
            for await note in NotificationCenter.default.notifications(
                named: AVAudioSession.interruptionNotification
            ) {
                // Only `.began` — the app never resumes a preview by itself (`docs/12` §7:
                // nothing autoplays audio, ever), so `.ended` has nothing to do and its
                // `shouldResume` option is deliberately ignored.
                let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                guard raw == AVAudioSession.InterruptionType.began.rawValue else { continue }
                guard let self else { return }
                self.stop()
            }
        }
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
