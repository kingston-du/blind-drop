import SwiftUI
import Testing
@testable import BlindDrop

/// File-scope rather than members of the suite: `@Test(arguments:)` evaluates its arguments
/// outside the actor the suite is isolated to.
private let devices = SnapshotRenderer.Device.matrix
private let sizes = SnapshotRenderer.typeSizes

/// `E41-01`'s goldens. The two things that can go wrong here are both layout, and both invisible
/// in a unit test.
///
/// **The artwork clamp.** Its side is whatever the column has not already claimed, so the pool's
/// size decides it: five names leave room for the top of
/// `Layout.Artwork.quickPassRange`, eleven leave the bottom. A golden at each end is the only
/// thing that shows the two layouts are both whole rather than one being the other with a gap in
/// it.
///
/// **`accessibility5` on an SE.** The pool falls from three columns to one, the artwork lands on
/// its floor, and the page has to scroll rather than overlap (`docs/12` §1). That combination is
/// the worst case in the app and it is asserted here across the full matrix.
///
/// The screen's `content` is rendered rather than the screen, and the reason is not convenience:
/// `ImageRenderer` asked for a `ScrollView` answers with whatever rectangle it was offered and
/// clips the rest, so a golden of one is a picture of a fixed frame with the layout cropped off
/// the bottom — the opposite of what a truncation test is for. Same split, same reason, as
/// `RevealSnapshots`.
@MainActor
@Suite struct QuickPassSnapshots {

    /// The ordinary night: a six-person circle, five names, nothing placed yet. The full matrix,
    /// because the reflow — three columns to one, the numeral against its 1.6× ceiling, the
    /// artwork on its floor — is the whole risk on this screen.
    @Test(arguments: devices, sizes)
    func sixPersonCircle(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "QuickPass-6", device, size) {
            screen(
                RevealFixture.store(cardCount: 6, myCardNumber: 3, poolSize: 5),
                size: size,
                device: device
            )
        }
    }

    /// Eleven names. `.large` only: the interesting thing here is the artwork giving its height
    /// to a four-row pool, and above `.accessibility1` the pool is a single column on every
    /// device anyway — the same picture the case above already takes.
    @Test(arguments: devices)
    func twelvePersonCircle(_ device: SnapshotRenderer.Device) {
        verify(named: "QuickPass-12", device, .large) {
            screen(
                RevealFixture.store(cardCount: 12, myCardNumber: 7),
                size: .large,
                device: device
            )
        }
    }

    /// Resumed half-finished, on the first gap — the state a re-entered run actually opens in.
    /// Two names are already spent, so this is also where the struck-through chip is drawn at
    /// `.large` rather than only described in `NameChip`'s doc comment.
    @Test(arguments: devices)
    func resumedWithNamesAlreadySpent(_ device: SnapshotRenderer.Device) {
        verify(named: "QuickPass-resumed", device, .large) {
            screen(
                RevealFixture.store(
                    cardCount: 6,
                    myCardNumber: 3,
                    poolSize: 5,
                    guesses: [1: "Cal", 2: "Ana"]
                ),
                size: .large,
                device: device
            )
        }
    }

    /// `ImageRenderer` does not run `.onAppear`, so a timer nobody started reads `--:--:--`.
    /// Started against `CountdownFixture`'s frozen clock, so the corner says the same nineteen
    /// seconds on every run.
    ///
    /// The viewport is passed rather than measured: outside a `GeometryReader` there is none to
    /// read, and a golden of a clamp needs the numbers the clamp was given to be facts of the
    /// test rather than of the renderer. 780 is an iPhone 17's content height inside its safe
    /// area, which is the case the clamp was drawn against; the width is the device's own, so the
    /// pool's column count — and therefore the artwork's share — differs between SE and 15ProMax
    /// exactly as it does in the hand.
    private func screen(
        _ store: RevealStore,
        size: DynamicTypeSize,
        device: SnapshotRenderer.Device
    ) -> some View {
        let clock = ServerClock(uptime: { 1_000 })
        clock.sync(serverNow: CountdownFixture.serverNow)
        let timer = CountdownTimer(clock: clock)
        timer.start(until: store.answersAt, form: Typography.countdownForm(for: size))
        return QuickPassScreen(store: store, timer: timer, onFinish: {})
            .snapshotContent(typeSize: size, availableHeight: 780, availableWidth: device.width)
    }

    private func verify(
        named name: String,
        _ device: SnapshotRenderer.Device,
        _ size: DynamicTypeSize,
        sourceLocation: SourceLocation = #_sourceLocation,
        @ViewBuilder content: () -> some View
    ) {
        let image = SnapshotRenderer.image(of: content(), device: device, typeSize: size)
        SnapshotRenderer.verify(
            image,
            named: "\(name)-\(device.name)-\(size.snapshotName)",
            in: "QuickPass",
            sourceLocation: sourceLocation
        )
    }
}
