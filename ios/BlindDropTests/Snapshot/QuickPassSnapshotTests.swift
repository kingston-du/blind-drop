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

    /// The server's four, per card — what this screen is actually built around.
    ///
    /// `RevealStore.shortlist(for:)` narrows a card to the four names the server offered and
    /// **falls back to the whole pool** when a card carries none. `RevealFixture.store(…)` sends
    /// no shortlists by default, so every golden in this suite used to render that fallback: six
    /// names where production shows four. That left the one layout the screen was designed for —
    /// `poolColumns`' *"four is a square"* case, two columns of two rather than a row of three
    /// with a fourth stranded under it — as the only layout with no picture of it.
    ///
    /// Rotated by card number rather than the same four every time, because that is what the
    /// server does and because a fixture that hands every card an identical shortlist cannot tell
    /// a screen that re-sorts per card apart from one that does not. `shortlist(for:)` sorts by
    /// pool order regardless, so the *drawn* order stays Ana-before-Ben on every card — which is
    /// the property being relied on, not a coincidence to be surprised by later.
    ///
    /// `twelvePersonCircle` deliberately keeps the fallback: a server that offers no shortlist is
    /// a real state, and it is the only one that puts eleven names under the artwork.
    private static func shortlists(cards: Int, poolSize: Int) -> [Int: [String]] {
        let names = RevealFixture.members.prefix(poolSize).map(\.displayName)
        return Dictionary(uniqueKeysWithValues: (1...cards).map { number in
            let start = (number - 1) % names.count
            return (number, Array((names[start...] + names[..<start]).prefix(4)))
        })
    }

    /// The ordinary night: a six-person circle, the server's four names, nothing placed yet. The
    /// full matrix, because the reflow — two columns to one, the numeral against its 1.6× ceiling,
    /// the artwork on its floor — is the whole risk on this screen.
    @Test(arguments: devices, sizes)
    func sixPersonCircle(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "QuickPass-6", device, size) {
            screen(
                RevealFixture.store(
                    cardCount: 6,
                    myCardNumber: 3,
                    poolSize: 5,
                    shortlists: Self.shortlists(cards: 6, poolSize: 5)
                ),
                size: size,
                device: device
            )
        }
    }

    /// Eleven names — **the fallback, on purpose.** No shortlists, which is how the store is told
    /// the server expressed no opinion about a card, and the one state that puts the whole pool
    /// under the artwork. `.large` only: the interesting thing here is the artwork giving its
    /// height to a four-row pool, and above `.accessibility1` the pool is a single column on every
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

    /// A cued night, `.large` only, against the same store `sixPersonCircle` renders uncued —
    /// the pair the design's trade is legible in (`E41-04`). The strip itself is free, drawn in
    /// the close row's existing `Spacer`, but `Layout.quickPassCueRow` is spent on every cued
    /// night for the second line a long cue would wrap onto — so the square here is 34pt smaller
    /// than `sixPersonCircle`'s even though *"A song you hate"* does not wrap. That slack is the
    /// deliberate price of not measuring the wrap, and diffing the two goldens is where somebody
    /// changing their mind about it would look.
    @Test(arguments: devices)
    func cued(_ device: SnapshotRenderer.Device) {
        verify(named: "QuickPass-cued", device, .large) {
            screen(
                RevealFixture.store(
                    cardCount: 6,
                    myCardNumber: 3,
                    poolSize: 5,
                    shortlists: Self.shortlists(cards: 6, poolSize: 5)
                ),
                size: .large,
                device: device,
                cue: Self.cue
            )
        }
    }

    /// The same cue at `.accessibility1` and `.accessibility5`, where the strip leaves the close
    /// row — a `displayS` line has no width left to wrap into beside a scaled touch target — and
    /// takes the full column beneath it. Its real height there runs well past the flat
    /// `Layout.quickPassCueRow` the reserve spends, and this is the picture that has to prove the
    /// under-count stays harmless: the artwork lands on `Artwork.quickPassRange`'s floor, and the
    /// page scrolls cleanly with the strip's true height on it rather than clipping or
    /// overlapping the pool beneath.
    @Test(arguments: devices, [DynamicTypeSize.accessibility1, .accessibility5])
    func cuedAccessibilitySize(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "QuickPass-cued-a11y", device, size) {
            screen(
                RevealFixture.store(
                    cardCount: 6,
                    myCardNumber: 3,
                    poolSize: 5,
                    shortlists: Self.shortlists(cards: 6, poolSize: 5)
                ),
                size: size,
                device: device,
                cue: Self.cue
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
                    guesses: [1: "Cal", 2: "Ana"],
                    shortlists: Self.shortlists(cards: 6, poolSize: 5)
                ),
                size: .large,
                device: device
            )
        }
    }

    /// **A mark already placed** (`E46-02`, `docs/19` §8.1).
    ///
    /// The one state the bar has that nothing else in this suite draws: the chosen segment's
    /// symbol switched from its outline to its filled form and picked up the screen's accent, the
    /// word beside it gone from `inkDim` to `ink`. `docs/12` §3 wants state carried by shape as
    /// well as by colour, and this is the picture that proves the shape half — the same job
    /// `NameChip`'s consumed strike has a golden for.
    ///
    /// Across the matrix, because the bar reflows at `.accessibility1` from three columns to
    /// three rows, and the selected row is where a stacked segment's mark and word have to stay
    /// level with each other.
    @Test(arguments: devices, sizes)
    func markPlaced(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "QuickPass-marked", device, size) {
            screen(
                RevealFixture.store(
                    cardCount: 6,
                    myCardNumber: 3,
                    poolSize: 5,
                    shortlists: Self.shortlists(cards: 6, poolSize: 5),
                    // Card 1 is where the run opens, so this is the mark the golden is of.
                    reactions: [1: .interesting]
                ),
                size: size,
                device: device
            )
        }
    }

    /// **`.xxxLarge`, and it is the size the reserve gets wrong if anybody simplifies it.**
    ///
    /// The standard matrix is `large` / `accessibility1` / `accessibility5`, which steps straight
    /// over the band this golden covers: the bar is still in its three-column arrangement here,
    /// and a scaled mark over a scaled `bodyS` word is already taller than the 44pt touch target.
    /// `QuickPassScreen.reactionReserve` asks `ReactionBar.height(for:)` rather than restating the
    /// arithmetic precisely so the two cannot disagree — a flat `minimumTouchTarget` per row was
    /// the first version and was wrong exactly here, with the artwork sized as if the bar were
    /// shorter than it draws.
    @Test(arguments: devices)
    func markPlacedAtAnIntermediateSize(_ device: SnapshotRenderer.Device) {
        verify(named: "QuickPass-marked-xxl", device, .xxxLarge) {
            screen(
                RevealFixture.store(
                    cardCount: 6,
                    myCardNumber: 3,
                    poolSize: 5,
                    shortlists: Self.shortlists(cards: 6, poolSize: 5),
                    reactions: [1: .interesting]
                ),
                size: .xxxLarge,
                device: device
            )
        }
    }

    /// The recap: the run finished, one card left blank, the caller's own card in place. The
    /// beat that makes the run finishable without touching the call sheet, and the one screen in
    /// the run that carries the countdown. Across the matrix because the row reflows at
    /// `.accessibility1` — title and name stop sharing a line, which is the layout an uncapped
    /// label beside an uncapped label gets wrong by starving one of them to nothing.
    @Test(arguments: devices, sizes)
    func recap(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        let store = RevealFixture.store(
            cardCount: 6,
            myCardNumber: 3,
            poolSize: 5,
            guesses: [1: "Cal", 2: "Ana", 4: "Dee", 6: "Eli"],
            shortlists: Self.shortlists(cards: 6, poolSize: 5)
        )
        // No. 5 is left blank, and the run is walked to its end — which is the only way a blank
        // card reaches the recap. A gap in a store is a gap the cursor resumes *onto*; a gap on
        // the recap is one the person went past on purpose.
        var walked = QuickPassSequence(
            cardNumbers: store.cards.map(\.cardNumber),
            isGuessable: store.isGuessable,
            isAssigned: { store.assignments[$0] != nil }
        )
        while !walked.isComplete { walked.advance() }
        verify(named: "QuickPass-recap", device, size) {
            screen(store, size: size, device: device, sequence: walked)
        }
    }

    /// The recap with a cue above it, `.large` only — the picture that proves the cue is drawn
    /// by `header`, stationary above `content(…)`'s `if`, rather than by the card branch alone.
    /// Same round as `recap` above, walked the same way, with the cue added and nothing else
    /// changed: any difference beyond the strip beside the close button is this golden's own bug.
    @Test(arguments: devices)
    func recapWithACue(_ device: SnapshotRenderer.Device) {
        let store = RevealFixture.store(
            cardCount: 6,
            myCardNumber: 3,
            poolSize: 5,
            guesses: [1: "Cal", 2: "Ana", 4: "Dee", 6: "Eli"],
            shortlists: Self.shortlists(cards: 6, poolSize: 5)
        )
        var walked = QuickPassSequence(
            cardNumbers: store.cards.map(\.cardNumber),
            isGuessable: store.isGuessable,
            isAssigned: { store.assignments[$0] != nil }
        )
        while !walked.isComplete { walked.advance() }
        verify(named: "QuickPass-recap-cued", device, .large) {
            screen(store, size: .large, device: device, sequence: walked, cue: Self.cue)
        }
    }

    /// The cue every cued test above shares — built by hand rather than decoded off a fixture,
    /// because a `CueDTO` is a two-field value with no server behaviour behind it and this suite
    /// is about the screen's layout, not the wire.
    private static let cue = CueDTO(key: "song_you_hate", text: "A song you hate")

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
        device: SnapshotRenderer.Device,
        sequence: QuickPassSequence? = nil,
        cue: CueDTO? = nil
    ) -> some View {
        let clock = ServerClock(uptime: { 1_000 })
        clock.sync(serverNow: CountdownFixture.serverNow)
        let timer = CountdownTimer(clock: clock)
        timer.start(until: store.answersAt, form: Typography.countdownForm(for: size))
        return QuickPassScreen(store: store, timer: timer, cue: cue, sequence: sequence, onFinish: {})
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
