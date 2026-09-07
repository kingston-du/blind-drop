import SwiftUI
import Testing
@testable import BlindDrop

/// File-scope rather than members of the suite: `@Test(arguments:)` evaluates its arguments
/// outside the actor the suite is isolated to.
private let devices = SnapshotRenderer.Device.matrix
private let sizes = SnapshotRenderer.typeSizes

/// The cue (`docs/18-CUES.md` §7): one placement per phase, and these goldens are what that
/// placement actually looks like on each.
///
/// It is **not** one placement for the app any more. `RoundScreen` draws `CueBanner` above
/// `phase(…)` for the two phases that do not scroll — Sealed and Voided — and the three that read
/// as a column draw it themselves, each in the position that phase argues for: a `CueCard` under
/// the drop screen's headline, the same card under the answers', and the banner inside the
/// flight's own header under the count. `RoundDTO.Phase.drawsItsOwnCue` is where that is decided.
/// Each case below composes the cue the way the phase it pictures actually does, so a cue sitting
/// wrong on any one of them is a picture rather than a claim. The cue value comes off the round's own
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
        // **No `CueBanner` above this one.** The drop screen draws the cue itself, as the card
        // between its subhead and its field, and a banner composed over it here would prove a
        // screen nobody sees — the cue said twice, once above and once in the card.
        try verify(named: "Cue-Submit", device, size, fixture: "round_open_nosub") { context, timer in
            Self.submitScreen(context: context, timer: timer)
        }
    }

    // MARK: - The dark hours (open, before opens_at)

    /// *"Tonight's round is done."* with the finished night's cue beneath it — the case this
    /// suite exists to keep honest, because the round on screen is the **next** one and its own
    /// cue must not appear anywhere on it (`docs/18-CUES.md` §7).
    ///
    /// `round_darkhours` carries **both** cues, with different text, so the picture can only be
    /// right one way round: *"Last night's cue: Your go-to aux song"*, and *"A song you hate"* —
    /// the coming night's, sitting on the same payload — nowhere on the screen.
    ///
    /// It also carries `previous_round_id`, so this golden includes **See last night's results**
    /// — the route into the night the headline is about (owner, 2026-09-03). Its neighbour
    /// `Submit-closed` has no such id and therefore no button, which is the pair of pictures that
    /// proves the button is gated on the server's answer rather than on the phase.
    @Test(arguments: devices, sizes)
    func closed(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) throws {
        try verify(
            named: "Cue-Closed",
            device,
            size,
            fixture: "round_darkhours",
            remaining: 9 * 3600,
            opensIn: 4 * 3600 + 30 * 60
        ) { context, timer in
            Self.closedScreen(context: context, timer: timer, previousCue: context.round.previousCue)
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

    /// Three cards — the length `RevealSnapshots` uses for its full matrix — with the cue **inside**
    /// the flight's own header, under the count. The cue is read off `round_revealed`'s base keys.
    ///
    /// It used to be composed here, above `snapshotContent`, because that is what `RoundScreen` did.
    /// The banner moved into the screen (owner, 2026-09-06) and so did this golden's composition —
    /// it now renders exactly what ships, which is the whole reason this suite draws the real
    /// screens rather than the banner on its own. The date rides with it: on this phase the pinned
    /// row that carried it is withheld, so a golden without one would be a picture of a header
    /// missing a line nobody sees missing.
    @Test(arguments: devices, sizes)
    func reveal(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) throws {
        let store = RevealFixture.store(cardCount: 3, myCardNumber: 2, guesses: [1: "Cal"])
        let clock = ServerClock(uptime: { 1_000 })
        clock.sync(serverNow: CountdownFixture.serverNow)
        let timer = CountdownTimer(clock: clock)
        timer.start(until: store.answersAt, form: Typography.countdownForm(for: size))
        let cue = try Self.cue("round_revealed")

        let image = SnapshotRenderer.image(
            of: RevealScreen(
                store: store,
                timer: timer,
                dateHeadline: "Saturday, September 5",
                cue: cue
            ).snapshotContent(typeSize: size),
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
    //
    // **No case here, deliberately** (owner, 2026-09-03). This suite pictures the cue's one
    // placement per phase, and on `scored` that placement moved inside the screen: the answers
    // draw the cue as a `CueCard` under their own headline, and `RoundDTO.Phase.drawsItsOwnCue`
    // withholds the banner exactly as it does for the drop screen. A `Cue-Results` golden with a
    // banner over the cards is a picture of a screen nobody sees, and one without a banner is
    // just `ResultsSnapshots.answersWithACue` rendered twice — so that golden is the coverage,
    // and its goldens here were deleted rather than re-recorded.

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
            previousCue: nil,
            choose: { _ in }
        ).snapshotContent
    }

    /// The dark hours: the screen after the answers, before tomorrow's opening.
    ///
    /// The card here is **last night's** cue and says so — the round this context was built
    /// from is the coming one, and its own `cue` is deliberately not passed. That is the whole
    /// claim this golden makes, and it is the one a reader can check by looking at the label.
    private static func closedScreen(
        context: RoundContext,
        timer: CountdownTimer,
        previousCue: CueDTO?
    ) -> some View {
        SubmitScreen(
            context: context,
            store: SubmitStore(api: offlineClient, circles: offlineCircles),
            player: PreviewPlayer(),
            timer: timer,
            deadline: context.round.opensAt,
            isBeforeOpen: true,
            cue: context.round.cue,
            previousCue: previousCue,
            // Taken from the fixture rather than passed in, so this golden pictures the dark
            // hours a user actually gets: `round_darkhours` has a scored night behind it, and
            // therefore the button into its answers. `Submit-closed` (SubmitSnapshotTests) is
            // the other half — a dark-hours screen with nothing behind it, and no button.
            showLastNightsResults: context.round.previousRoundID.map { _ in {} },
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
