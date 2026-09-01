import SwiftUI
import Testing
@testable import BlindDrop

/// File-scope rather than members of the suite: `@Test(arguments:)` evaluates its arguments
/// outside the actor the suite is isolated to.
private let devices = SnapshotRenderer.Device.matrix
private let sizes = SnapshotRenderer.typeSizes

/// The cue banner (`docs/18-CUES.md` §7): one neutral line above whichever phase screen is up,
/// shared by Submit, Sealed, Reveal and Results from a single `RoundScreen` placement.
///
/// `RoundScreen` renders `CueBanner` once, above `phase(…)` — not inside `RoundHeader` (whose
/// three rows are already tight) and not duplicated per screen. These goldens compose the banner
/// over each phase's own `snapshotContent` the same way, so a cue sitting wrong above any one of
/// the four phases is a picture rather than a claim. The cue value comes off the round's own
/// JSON (`ios/Fixtures/payloads`, which `E35-04` made cued) through the real decoder, not built
/// by hand — `RoundDTO`'s memberwise initialiser is private on purpose (`docs/13` §2).
/// `.serialized` — the four parameterised tests fan out to 24 `ImageRenderer` draws, and run
/// in parallel they crash the test process (`IOSurfaceClientSetSurfaceNotify failed`, then
/// "Restarting after unexpected exit, crash, or test timeout") with only a couple of goldens
/// written. Serial like `RoundStoreTests`, so every golden lands.
@MainActor
@Suite(.serialized) struct CueSnapshots {

    // MARK: - Submit (open, nothing dropped)

    @Test(arguments: devices, sizes)
    func submit(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) throws {
        // **No `CueBanner` above this one.** Every other case in this suite composes the
        // banner over the phase screen because that is what `RoundScreen` does; the drop screen
        // is the exception `drawsItsOwnCue(_:)` names, and the golden has to be the exception too
        // or it would prove a screen nobody sees — the cue said twice, once above and once in
        // the card.
        try verify(named: "Cue-Submit", device, size, fixture: "round_open_nosub") { context, timer in
            Self.submitScreen(context: context, timer: timer)
        }
    }

    // MARK: - Sealed (open, submitted)

    @Test(arguments: devices, sizes)
    func sealed(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) throws {
        let submission = try Self.submission()
        try verify(named: "Cue-Sealed", device, size, fixture: "round_open") { context, timer in
            VStack(alignment: .leading, spacing: Space.none) {
                CueBanner(cue: context.round.cue).padding(.bottom, Layout.itemGap)
                SealedScreen(context: context, submission: submission, timer: timer, replace: {})
            }
        }
    }

    // MARK: - Reveal

    /// Three cards — the length `RevealSnapshots` uses for its full matrix — with the banner
    /// above the flight's own header. The cue is read off `round_revealed`'s base keys.
    @Test(arguments: devices, sizes)
    func reveal(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) throws {
        let store = RevealFixture.store(cardCount: 3, myCardNumber: 2, guesses: [1: "Cal"])
        let clock = ServerClock(uptime: { 1_000 })
        clock.sync(serverNow: CountdownFixture.serverNow)
        let timer = CountdownTimer(clock: clock)
        timer.start(until: store.answersAt, form: Typography.countdownForm(for: size))
        let cue = try Self.cue("round_revealed")

        let image = SnapshotRenderer.image(
            of: VStack(alignment: .leading, spacing: Space.none) {
                CueBanner(cue: cue).padding(.bottom, Layout.itemGap)
                RevealScreen(store: store, timer: timer).snapshotContent(typeSize: size)
            },
            device: device,
            typeSize: size
        )
        SnapshotRenderer.verify(
            image,
            named: "Cue-Reveal-\(device.name)-\(size.snapshotName)",
            in: "Cue"
        )
    }

    // MARK: - Results

    /// Three cards — the same numbers `ResultsSnapshots` uses, so every mark state is present —
    /// with the banner above. `maximumPixelCount` mirrors `ResultsSnapshots.threeCards`: the
    /// 15 Pro Max × accessibility5 render is over ImageIO's simulator PNG ceiling.
    @Test(arguments: devices, sizes)
    func results(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) throws {
        let cue = try Self.cue("round_scored")
        let image = SnapshotRenderer.image(
            of: VStack(alignment: .leading, spacing: Space.none) {
                CueBanner(cue: cue).padding(.bottom, Layout.itemGap)
                ResultsSnapshotFixture.screen(cards: ResultsSnapshotFixture.cards([3, 4, 5]))
            },
            device: device,
            typeSize: size,
            maximumPixelCount: 8_000_000
        )
        SnapshotRenderer.verify(
            image,
            named: "Cue-Results-\(device.name)-\(size.snapshotName)",
            in: "Cue"
        )
    }

    // MARK: - Rendering

    /// The search screen, with an idle store behind it — the same shape `SubmitSnapshots` uses.
    private static func submitScreen(context: RoundContext, timer: CountdownTimer) -> some View {
        SubmitScreen(
            context: context,
            store: SubmitStore(api: offlineClient, circles: offlineCircles),
            player: PreviewPlayer(),
            timer: timer,
            deadline: context.round.revealsAt,
            isBeforeOpen: false,
            // The whole point of this suite: the drop screen draws the cue itself, as a card in
            // its own column, so the golden has to be given the cue rather than relying on the
            // banner `RoundScreen` no longer puts above this phase.
            cue: context.round.cue,
            choose: { _ in }
        ).snapshotContent
    }

    /// A client pointed at nothing. The screens in these goldens never issue a request, so all
    /// that matters is that a store can be built without a server behind it.
    private static let offlineEnvironment = AppEnvironment(
        configuration: AppConfiguration(apiBaseURL: URL(string: "https://snapshot.invalid")!)
    )
    private static var offlineClient: APIClient { offlineEnvironment.api }
    private static var offlineCircles: CircleStore { offlineEnvironment.circles }

    private static func submission() throws -> SubmissionDTO {
        SubmissionDTO(track: .ribs, sealedAt: CountdownFixture.serverNow)
    }

    /// The cue off a payload's round, decoded through the real decoder. The round is the fixture
    /// server's source of truth and now carries `cue` on its base keys (`E35-04`).
    private static func cue(_ name: String) throws -> CueDTO? {
        try JSONDecoder.api.decode(RoundDTO.self, from: payload(name)).cue
    }

    private static func payload(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Snapshot
            .deletingLastPathComponent()   // BlindDropTests
            .deletingLastPathComponent()   // ios
        return try Data(contentsOf: root.appending(path: "Fixtures/payloads/\(name).json"))
    }

    /// A context and a **started** timer, against the frozen clock — the same shape
    /// `SubmitSnapshots.verify` uses, because `ImageRenderer` runs no `.onAppear` and a timer
    /// nobody started reads `--:--:--`.
    private func verify(
        named name: String,
        _ device: SnapshotRenderer.Device,
        _ size: DynamicTypeSize,
        fixture: String,
        remaining: TimeInterval = 3 * 3600 + 12 * 60 + 48,
        opensIn: TimeInterval = -5 * 3600,
        sourceLocation: SourceLocation = #_sourceLocation,
        @ViewBuilder content: (RoundContext, CountdownTimer) -> some View
    ) throws {
        let context = try SnapshotFixture.context(fixture, revealsIn: remaining, opensIn: opensIn)
        let clock = ServerClock(uptime: { 1_000 })
        clock.sync(serverNow: CountdownFixture.serverNow)
        let timer = CountdownTimer(clock: clock)
        timer.start(
            until: try #require(context.deadline(now: CountdownFixture.serverNow)),
            form: Typography.countdownForm(for: size)
        )

        let image = SnapshotRenderer.image(of: content(context, timer), device: device, typeSize: size)
        SnapshotRenderer.verify(
            image,
            named: "\(name)-\(device.name)-\(size.snapshotName)",
            in: "Cue",
            sourceLocation: sourceLocation
        )
    }
}
