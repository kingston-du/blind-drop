import SwiftUI
import Testing
@testable import BlindDrop

/// The sealed phase rendered into **the height a phone actually has**, rather than the height it
/// asks for.
///
/// Every other golden in this repository renders at `proposedSize.height == nil`
/// (`SnapshotRenderer.image`), which is deliberate — it is what makes *"nothing truncates"*
/// visible instead of hidden behind a fixed frame. But it also means no golden here has ever
/// seen this screen's real constraint. The cover is square-to-fit, so it is the one *flexible*
/// thing in the column; under an unbounded proposal it always gets the square it wants, and under
/// a real one it silently absorbs every point spent above it. On 2026-09-05 that had it drawing
/// at 137pt inside a 313pt card on an iPhone 17 — a fault invisible to all 93 goldens and obvious
/// in the first screenshot of the running app.
///
/// So this suite pins one number: **the cover reaches the width of the card it is on**, on a
/// column with a cue over it and no room to spare. `sealedLongTitle` pins the second: that the
/// number does not depend on which song was dropped — `peekableMetadata` lays out both of its
/// halves at all times so they can crossfade, so an unlimited title made the card's height a
/// function of its content until `SealedCard.lineLimit` fixed it.
@MainActor
@Suite(.serialized) struct SealedHeightSnapshots {

    /// iPhone 17's 874pt, less the 171pt of round chrome above the cue and the 33pt of home
    /// indicator below the button. Measured off the running app, not derived — the chrome is
    /// `RoundScreen`'s and is not rendered here.
    private static let available: CGFloat = 670
    private static let device = SnapshotRenderer.Device(name: "17", width: 402, scale: 3)

    @Test func sealed() throws {
        try verify(track: .ribs, peeking: false, named: "SealedHeight")
    }

    /// The same column mid-peek. The cover must not resize when a finger goes down — a card that
    /// changes size on hold is a card that jumps under the thumb holding it.
    @Test func sealedPeeking() throws {
        try verify(track: .ribs, peeking: true, named: "SealedHeight-peeking")
    }

    /// A 59-character title. Must be pixel-identical to `SealedHeight` — the fixture
    /// `ComponentSnapshots` already keeps for exactly this shape of failure.
    @Test func sealedLongTitle() throws {
        try verify(track: .longTitle, peeking: false, named: "SealedHeight-longTitle")
    }

    private func verify(
        track: TrackDTO,
        peeking: Bool,
        named name: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let context = try SnapshotFixture.context("round_open", revealsIn: 7 * 3600 + 53 * 60, opensIn: -5 * 3600)
        let clock = ServerClock(uptime: { 1_000 })
        clock.sync(serverNow: CountdownFixture.serverNow)
        let timer = CountdownTimer(clock: clock)
        timer.start(
            until: try #require(context.deadline(now: CountdownFixture.serverNow)),
            form: Typography.countdownForm(for: .large)
        )
        let submission = SubmissionDTO(track: track, sealedAt: CountdownFixture.serverNow)

        let view = VStack(alignment: .leading, spacing: Space.none) {
            CueBanner(cue: CueDTO(key: "scratch", text: "A song that makes you think of them"))
                .padding(.bottom, Layout.itemGap)
            SealedScreen(
                context: context,
                submission: submission,
                timer: timer,
                replace: {},
                isPeekingForSnapshot: peeking
            )
        }
        .frame(width: 402 - 2 * Layout.screenInset, height: Self.available, alignment: .top)

        let image = SnapshotRenderer.image(of: view, device: Self.device, typeSize: .large)
        SnapshotRenderer.verify(image, named: name, in: "Submit", sourceLocation: sourceLocation)
    }
}
