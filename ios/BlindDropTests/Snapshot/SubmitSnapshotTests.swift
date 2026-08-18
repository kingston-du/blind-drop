import SwiftUI
import Testing
@testable import BlindDrop

/// File-scope rather than members of the suite: `@Test(arguments:)` evaluates its arguments
/// outside the actor the suite is isolated to.
private let devices = SnapshotRenderer.Device.matrix
private let sizes = SnapshotRenderer.typeSizes

/// `E10`'s snapshot matrix: the four phase screens of `docs/08` §2–§5, plus the confirm layout the
/// seal runs on.
///
/// The two axes are `docs/12` §8's — `{SE, 15 Pro Max}` × `{large, accessibility1,
/// accessibility5}`. `.accessibility5` on an SE is the worst case in the app and the size at which
/// *"nothing truncates and nothing overlaps"* either holds or visibly does not.
///
/// The last test in the file is the one `E10-04`'s checklist asks for by name: the reduced-motion
/// path's final state, rendered, against the full path's. Not "similar" — the same pixels.
@MainActor
@Suite struct SubmitSnapshots {

    // MARK: - Submit (`docs/08` §2)

    /// The default state, which is the entire tutorial: *"Drop one song. Nobody sees it until
    /// 8:00 PM."*
    @Test(arguments: devices, sizes)
    func submit(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) throws {
        try verify(named: "Submit", device, size) { context, timer in
            Self.submitScreen(context: context, timer: timer,
                              deadline: context.round.revealsAt, isBeforeOpen: false)
        }
    }

    /// Under two hours: the nudge line appears above the button and **nothing else changes**.
    ///
    /// Its own golden because "nothing else changes" is a claim a diff can check — the countdown,
    /// the headline and the button must sit exactly where they did.
    @Test(arguments: devices, [DynamicTypeSize.large, .accessibility5])
    func submitNudging(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) throws {
        try verify(named: "Submit-nudge", device, size, remaining: 90 * 60) { context, timer in
            Self.submitScreen(context: context, timer: timer,
                              deadline: context.round.revealsAt, isBeforeOpen: false)
        }
    }

    /// The dark hours: the countdown reads to the opening, the copy names it, and the button is
    /// disabled (`docs/08` §2).
    @Test(arguments: devices, [DynamicTypeSize.large, .accessibility5])
    func submitBeforeOpen(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) throws {
        try verify(named: "Submit-closed", device, size, remaining: 9 * 3600, opensIn: 4 * 3600 + 30 * 60) { context, timer in
            Self.submitScreen(context: context, timer: timer,
                              deadline: context.round.opensAt, isBeforeOpen: true)
        }
    }

    // MARK: - Sealed (`docs/08` §4)

    /// The landed card, the status line, the countdown, and **Replace song**. Nothing else.
    @Test(arguments: devices, sizes)
    func sealed(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) throws {
        try verify(named: "Sealed", device, size) { context, timer in
            SealedScreen(context: context, submission: try! Self.submission(), timer: timer,
                         replace: {})
        }
    }

    /// `CardCornerLinks`' worst case: both services present, stacked two lines in the cover's
    /// corner, at the size where `docs/12` §1's *"nothing truncates and nothing overlaps"*
    /// either holds against the seal stamp in the opposite corner or visibly does not.
    @Test(arguments: devices)
    func sealedWithBothLinks(_ device: SnapshotRenderer.Device) throws {
        try verify(named: "Sealed-bothLinks", device, .accessibility5) { context, timer in
            SealedScreen(
                context: context,
                submission: SubmissionDTO(track: .bothLinks, sealedAt: CountdownFixture.serverNow),
                timer: timer,
                replace: {}
            )
        }
    }

    /// After a replacement — *"Sealed again."* Never announced to anybody else, never counted.
    @Test(arguments: devices, [DynamicTypeSize.large])
    func sealedAfterReplacing(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) throws {
        try verify(named: "Sealed-replaced", device, size) { context, timer in
            SealedScreen(context: context, submission: try! Self.submission(), timer: timer,
                         didReplace: true, replace: {})
        }
    }

    // MARK: - Voided (`docs/08` §5)

    /// Muted amber, the song back, and **no count of how many did drop**.
    @Test(arguments: devices, sizes)
    func voided(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) throws {
        try verify(named: "Voided", device, size, fixture: "round_voided") { context, timer in
            // Never `nil` on a voided round — tomorrow's opening does not consult the clock, so
            // this is the one phase whose deadline an unanchored clock could not blank.
            VoidedScreen(context: context, submission: try! Self.submission(), timer: timer,
                         deadline: context.deadline(now: context.round.revealsAt)!)
        }
    }

    // MARK: - Confirm (`docs/08` §3.2)

    /// The screen the seal happens on, at rest: 280pt artwork, the title in `displayM`, **Seal
    /// it** and **Pick another**.
    @Test(arguments: devices, sizes)
    func confirm(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) throws {
        let image = SnapshotRenderer.image(
            of: try Self.confirmLayout(phase: .unsealed, reducedMotion: false),
            device: device,
            typeSize: size
        )
        SnapshotRenderer.verify(image, named: "Confirm-\(device.name)-\(size.snapshotName)", in: "Submit")
    }

    // MARK: - The seal's ends (`docs/09` §2, §5)

    /// The landed state, which is what the sheet dismisses onto.
    @Test(arguments: devices, [DynamicTypeSize.large])
    func confirmSealed(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) throws {
        let image = SnapshotRenderer.image(
            of: try Self.confirmLayout(phase: .sealed, reducedMotion: false),
            device: device,
            typeSize: size
        )
        SnapshotRenderer.verify(image, named: "Confirm-sealed-\(device.name)-\(size.snapshotName)", in: "Submit")
    }

    /// **`E10-04`'s third test line**, rendered rather than reasoned about:
    ///
    /// > *"Test: reduced-motion final state is pixel-identical to the normal path's."*
    ///
    /// `SealTimelineTests` asserts the two paths' *values* are equal; this asserts the two paths'
    /// **pixels** are, at zero tolerance on both axes. A reduced-motion branch that quietly
    /// dropped the stamp, or landed it square instead of off-axis by 4°, would pass the value test
    /// only if the values agreed — and would fail here if a view read the flag anywhere else.
    @Test(arguments: devices)
    func theReducedMotionSealLandsOnTheSamePixels(_ device: SnapshotRenderer.Device) throws {
        let full = SnapshotRenderer.image(
            of: try Self.confirmLayout(phase: .sealed, reducedMotion: false),
            device: device, typeSize: .large
        )
        let reduced = SnapshotRenderer.image(
            of: try Self.confirmLayout(phase: .sealed, reducedMotion: true),
            device: device, typeSize: .large
        )

        let differing = try #require(SnapshotRenderer.differingFraction(full, reduced),
                                     "the two renders are different sizes, which is a failure on its own")
        #expect(differing == 0, "reduced motion removes movement, not the state it arrives at")
    }

    // MARK: - Rendering

    /// The confirm screen's sealed artwork at a given phase.
    ///
    /// `SealedArtwork` rather than the whole `ConfirmScreen`, deliberately: the screen owns a
    /// `PreviewPlayer` and a `SubmitStore`, and what the two seal paths have to agree about is the
    /// **card** — the cover, the stamp, the ring and the artwork under them.
    private static func confirmLayout(phase: SealPhase, reducedMotion: Bool) throws -> some View {
        SealedArtwork(
            track: .ribs,
            groupInitial: "T",
            phase: phase,
            reducedMotion: reducedMotion,
            size: Layout.Artwork.confirm,
            fillsWidth: false
        )
    }

    /// The search screen, with an idle store behind it.
    ///
    /// Idle is the state worth a golden: it is what somebody lands on, and it is the only one
    /// whose layout is the screen's own rather than a list's. `ImageRenderer` never runs
    /// `.onAppear`, so the field is drawn unfocused here — which is also what makes the border
    /// state in the picture the resting one.
    private static func submitScreen(
        context: RoundContext,
        timer: CountdownTimer,
        deadline: Date,
        isBeforeOpen: Bool
    ) -> some View {
        return SubmitScreen(
            context: context,
            store: SubmitStore(api: Self.offlineClient),
            player: PreviewPlayer(),
            timer: timer,
            deadline: deadline,
            isBeforeOpen: isBeforeOpen,
            choose: { _ in }
        ).snapshotContent
    }

    /// A client pointed at nothing.
    ///
    /// The screens in these goldens never issue a request — the query is empty and
    /// `ImageRenderer` runs no task — so all that matters is that a store can be built without a
    /// server behind it. The environment is the app's own, with its base URL replaced, which is
    /// less machinery than assembling a client by hand and cannot drift from what ships.
    private static let offlineClient = AppEnvironment(
        configuration: AppConfiguration(apiBaseURL: URL(string: "https://snapshot.invalid")!)
    ).api

    private static func submission() throws -> SubmissionDTO {
        SubmissionDTO(track: .ribs, sealedAt: CountdownFixture.serverNow)
    }

    /// A context and a **started** timer, against the frozen clock the other snapshot suites use.
    ///
    /// `ImageRenderer` never runs `.onAppear`, so a timer nobody started reads `--:--:--` and
    /// every countdown golden would be a row of hyphens.
    private func verify(
        named name: String,
        _ device: SnapshotRenderer.Device,
        _ size: DynamicTypeSize,
        fixture: String = "round_open",
        remaining: TimeInterval = 3 * 3600 + 12 * 60 + 48,
        opensIn: TimeInterval = -5 * 3600,
        sourceLocation: SourceLocation = #_sourceLocation,
        @ViewBuilder content: (RoundContext, CountdownTimer) -> some View
    ) throws {
        let context = try SnapshotFixture.context(fixture, revealsIn: remaining, opensIn: opensIn)
        let clock = ServerClock(uptime: { 1_000 })
        clock.sync(serverNow: CountdownFixture.serverNow)
        let timer = CountdownTimer(clock: clock)
        // Pointed at the round's own deadline, so a screen that re-points it — `CountdownView` does
        // on appear — lands on the same digits rather than on the gap between two constants.
        // `#require` rather than `??`: the clock here is anchored a line above, so a `nil`
        // deadline would mean `RoundContext` had stopped answering a question it can answer —
        // worth failing on rather than papering over with a fallback the goldens would then be
        // rendered against.
        timer.start(
            until: try #require(context.deadline(now: CountdownFixture.serverNow)),
            form: Typography.countdownForm(for: size)
        )

        let image = SnapshotRenderer.image(of: content(context, timer), device: device, typeSize: size)
        SnapshotRenderer.verify(
            image,
            named: "\(name)-\(device.name)-\(size.snapshotName)",
            in: "Submit",
            sourceLocation: sourceLocation
        )
    }
}

/// Rounds and groups for the snapshot target, decoded from `ios/Fixtures/payloads`.
///
/// The unit target has its own copy (`RoundFixture`) — the two targets share no code — and both
/// decode rather than construct, because `RoundDTO`'s memberwise initialiser is private on purpose
/// (`docs/13` §2: the decoder is the only place a phase is assigned).
///
/// **The rounds are re-timed around the frozen clock**, exactly as `ios/Fixtures/server.ts` does
/// with `ANCHOR=now`. The payloads carry literal instants in August 2026, and a golden of a
/// countdown between those and `CountdownFixture.serverNow` reads *"112:53:20"* — a real number,
/// of no interest to anybody, and one that would silently become a different real number if either
/// constant moved. Re-timing makes the digits in the picture the digits the screen is *about*.
@MainActor
enum SnapshotFixture {

    /// - Parameters:
    ///   - revealsIn: how long until the reveal, from the frozen `server_now`.
    ///   - opensIn: how long until the round opens. Negative — the usual case — means it is
    ///     already open; positive is `docs/08` §2's dark hours.
    static func context(
        _ round: String,
        revealsIn: TimeInterval = 3 * 3600 + 12 * 60 + 48,
        opensIn: TimeInterval = -5 * 3600
    ) throws -> RoundContext {
        RoundContext(
            round: try retimed(round, revealsIn: revealsIn, opensIn: opensIn),
            group: try decode(GroupDTO.self, from: "group_current")
        )
    }

    /// The payload with its three instants moved onto the frozen clock, then decoded — through the
    /// real decoder, which is the point of not building a `RoundDTO` by hand.
    private static func retimed(_ name: String, revealsIn: TimeInterval, opensIn: TimeInterval) throws -> RoundDTO {
        let data = try payload(name)
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        let now = CountdownFixture.serverNow
        json["opens_at"] = rfc3339(now.addingTimeInterval(opensIn))
        json["reveals_at"] = rfc3339(now.addingTimeInterval(revealsIn))
        json["scores_at"] = rfc3339(now.addingTimeInterval(revealsIn + 2 * 3600))
        return try JSONDecoder.api.decode(
            RoundDTO.self,
            from: try JSONSerialization.data(withJSONObject: json)
        )
    }

    /// RFC 3339 UTC with a `Z`, which is what `docs/04` puts on the wire and what
    /// `JSONDecoder.api`'s `.iso8601` strategy accepts — no fractional seconds, no offset.
    private static func rfc3339(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    private static func payload(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Snapshot
            .deletingLastPathComponent()   // BlindDropTests
            .deletingLastPathComponent()   // ios
        return try Data(contentsOf: root.appending(path: "Fixtures/payloads/\(name).json"))
    }

    private static func decode<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        try JSONDecoder.api.decode(type, from: try payload(name))
    }
}
