import SwiftUI
import Testing
@testable import BlindDrop

/// File-scope rather than members of the suite: `@Test(arguments:)` evaluates its arguments
/// outside the actor the suite is isolated to.
private let devices = SnapshotRenderer.Device.matrix
private let sizes = SnapshotRenderer.typeSizes

/// `E11-01`'s verify line: *"snapshot matrix at 6 and 12 cards."*
///
/// Split across three flight lengths, because the two axes prove different things and the long
/// flights cannot carry the type-size axis at all — see the **Open question** in
/// `tasks/E11-reveal-and-guess.md`. In short: `UIImage.pngData()` returns `nil` somewhere above
/// eight thousand pixels of height, and twelve cards at `.accessibility5` is roughly twenty
/// thousand. The renderer reports that honestly rather than writing a truncated file, which is
/// how the ceiling was found.
///
/// What each length is for:
///
/// - **Three cards, the full 2 × 3 matrix.** The reflow axis. At `.accessibility1` the status
///   line stacks and `FlightCard` moves its number above the artwork; at `.accessibility5` the
///   question is whether any of it still fits. Three cards shows all three chip states and
///   stays a picture a person can actually review.
/// - **Six cards, `.large`.** The ordinary night, and the flight's rhythm at the size most
///   people will see it.
/// - **Twelve cards, `.large`.** `docs/08` §6's stress case. Two-digit numbers appear here and
///   nowhere else, and `.large` is the only size where they matter: above `.accessibility1`
///   `FlightCard` stacks, so there is no number *column* left to go ragged.
///
/// The screen's `content` is rendered rather than the screen: a `ScrollView` answers an ideal
/// height request with whatever it was offered, so a golden of one shows a fixed rectangle with
/// the rest of the flight clipped away — the opposite of what a truncation test is for.
@MainActor
@Suite struct RevealSnapshots {

    /// The reflow axis, at a length every combination can encode. No. 2 is the caller's own, so
    /// the `Yours` label sits between a guessed card and an open one rather than at an edge.
    @Test(arguments: devices, sizes)
    func threeCards(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "Reveal-3", device, size) {
            screen(
                RevealFixture.store(cardCount: 3, myCardNumber: 2, guesses: [1: "Cal"]),
                size: size
            )
        }
    }

    /// The non-submitter's view (`docs/08` §6, and `E11-05`'s subject): every chip absent, the
    /// flight otherwise whole. Across the matrix because *"the user must see exactly what they
    /// missed"* is a layout claim as much as a copy one — the cards must not collapse into
    /// something shorter and cheaper-looking than the real thing.
    @Test(arguments: devices, sizes)
    func threeCardsUnguessable(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "Reveal-3-blocked", device, size) {
            screen(
                RevealFixture.store(cardCount: 3, myCardNumber: nil, canGuess: false),
                size: size
            )
        }
    }

    /// The ordinary night, at the size most people read it. One card is the caller's own (No. 4,
    /// so `Yours` lands mid-flight), two are guessed, the rest are open.
    @Test(arguments: devices)
    func sixCards(_ device: SnapshotRenderer.Device) {
        verify(named: "Reveal-6", device, .large) {
            screen(
                RevealFixture.store(cardCount: 6, myCardNumber: 4, guesses: [1: "Cal", 3: "Ana"]),
                size: .large
            )
        }
    }

    /// `docs/08` §6's twelve-member case, and the one that sizes `FlightCard`'s number column:
    /// if the column is wrong, No. 10 through No. 12 are where the flight's left edge goes
    /// ragged.
    @Test(arguments: devices)
    func twelveCards(_ device: SnapshotRenderer.Device) {
        verify(named: "Reveal-12", device, .large) {
            screen(
                RevealFixture.store(
                    cardCount: 12,
                    myCardNumber: 7,
                    guesses: [1: "Cal", 2: "Ana", 3: "Dee", 11: "Ben"]
                ),
                size: .large
            )
        }
    }

    // MARK: - The guess sheet (E11-05)

    /// The apparatus as a submitter sees it: the pool, **Lock in guesses**, and the progress
    /// line. `.large` and `.accessibility5` only — the sheet has no reflow of its own to prove at
    /// `.accessibility1`, and `E11-03` is what takes its layout over.
    @Test(arguments: devices, [DynamicTypeSize.large, .accessibility5])
    func guessSheet(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "GuessSheet", device, size) {
            GuessSheet(store: RevealFixture.store(cardCount: 6, myCardNumber: 4, poolSize: 5,
                                                  guesses: [1: "Cal", 3: "Ana"]))
                .content(layout: NamePoolLayout(dynamicTypeSize: size), typeSize: size)
        }
    }

    /// `E26-02`'s open question: a pool small enough to hold more chips than it has. Three names
    /// is the case a scaled minimum width is most likely to look wrong in — a row that could fit
    /// five 72-point pills instead draws three, and the question is whether that reads as a
    /// deliberately short row or as a layout that forgot to fill itself. `.accessibility5` moves
    /// it into the two-column grid, where three chips leave the grid's last row holding a single
    /// pill next to empty space rather than a ragged one.
    @Test(arguments: devices, [DynamicTypeSize.large, .accessibility5])
    func guessSheetThreeMembers(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "GuessSheet-3", device, size) {
            GuessSheet(store: RevealFixture.store(cardCount: 6, myCardNumber: 4, poolSize: 3,
                                                  guesses: [1: "Cal"]))
                .content(layout: NamePoolLayout(dynamicTypeSize: size), typeSize: size)
        }
    }

    /// The non-submitter's sheet. **Disabled, not hidden** (`docs/08` §6): the pool is still
    /// there, dimmed, and the button is replaced by the line that says why. The whole point is
    /// that the user sees exactly what they missed, so the golden has to show a pool.
    @Test(arguments: devices, [DynamicTypeSize.large, .accessibility5])
    func guessSheetNotASubmitter(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "GuessSheet-notsubmitter", device, size) {
            GuessSheet(store: RevealFixture.store(cardCount: 6, canGuess: false,
                                                  reason: .notASubmitter, poolSize: 5))
                .content(layout: NamePoolLayout(dynamicTypeSize: size), typeSize: size)
        }
    }

    /// Same treatment, different line — someone who joined this afternoon is not told they
    /// *"didn't drop tonight"*.
    @Test(arguments: devices, [DynamicTypeSize.large, .accessibility5])
    func guessSheetJoinedLate(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "GuessSheet-joinedlate", device, size) {
            GuessSheet(store: RevealFixture.store(cardCount: 6, canGuess: false,
                                                  reason: .joinedLate, poolSize: 5))
                .content(layout: NamePoolLayout(dynamicTypeSize: size), typeSize: size)
        }
    }

    /// The PRD's large-text stress case. At `.accessibility5` the horizontal strip becomes the
    /// two-column vertical grid; rendering its contents without the scroll container makes all
    /// eleven chips reviewable in one image, while `A11yReachabilityTests` proves the production
    /// container exposes that whole set through its visible vertical scroll indicator.
    @Test(arguments: devices)
    func guessSheetTwelveMembersAtAccessibilityFive(_ device: SnapshotRenderer.Device) {
        verify(named: "GuessSheet-12", device, .accessibility5) {
            GuessSheet(store: RevealFixture.store(cardCount: 12, myCardNumber: 7))
                .content(layout: .verticalGrid, typeSize: .accessibility5)
        }
    }

    // MARK: - Rendering

    /// The screen with a **started** timer.
    ///
    /// `ImageRenderer` does not run `.onAppear`, so a timer nobody started reads `--:--:--` and
    /// the status line snapshots a row of hyphens. Started here against the same frozen clock
    /// `CountdownFixture` uses, so *"01:42:19"* is the same nineteen seconds on every run.
    private func screen(_ store: RevealStore, size: DynamicTypeSize) -> some View {
        let clock = ServerClock(uptime: { 1_000 })
        clock.sync(serverNow: CountdownFixture.serverNow)
        let timer = CountdownTimer(clock: clock)
        timer.start(until: store.answersAt, form: Typography.countdownForm(for: size))
        return RevealScreen(store: store, timer: timer).snapshotContent(typeSize: size)
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
            in: "Reveal",
            sourceLocation: sourceLocation
        )
    }
}

// MARK: - Fixtures

/// Rounds of an arbitrary size, built from the two tracks the component snapshots already use.
///
/// `BlindDropTests/Unit` and `BlindDropTests/Snapshot` are separate targets and share no code,
/// so `RevealTests` carries its own minimal version of this. The two are deliberately not the
/// same: the rule tests want a track that merely exists, and these want the two the goldens are
/// already drawn with.
///
/// `@MainActor` because it anchors off `CountdownFixture`'s frozen `server_now`, which is. Every
/// use is inside a test body of this suite, which is main-actor too, so the isolation costs
/// nothing and keeps the two fixtures agreeing on one instant rather than on two literals that
/// have to be kept equal by hand.
@MainActor
enum RevealFixture {

    /// The answers land at a fixed offset from the frozen `server_now`, so the status line
    /// renders the same digits on every run. 6 139 seconds is 01:42:19 — the exact countdown
    /// `docs/08` §6 draws in its header.
    static let answersAt = CountdownFixture.serverNow.addingTimeInterval(6_139)

    /// Card `n`, alternating between the two fixture tracks so a twelve-card golden is not
    /// twelve identical rows — a repeated row hides an alignment bug by making every line wrong
    /// in the same way.
    static func card(number: Int) -> CardDTO {
        CardDTO(cardNumber: number, track: number.isMultiple(of: 2) ? .ribs : .motionSickness)
    }

    /// Eleven names plus the caller — the largest pool the product allows (`docs/02`).
    static let members = ["Ana", "Ben", "Cal", "Dee", "Eli", "Fay", "Gus", "Hal", "Ivy", "Jo", "Kit"]
        .enumerated()
        .map { MemberDTO(userID: "u\($0.offset)", displayName: $0.element) }

    /// The caller. Present in the pool the server sends and removed by the store, which is the
    /// behaviour worth exercising rather than stubbing around.
    static let me = MemberDTO(userID: "me", displayName: "You")

    /// A store standing in the state a golden is a picture of.
    ///
    /// `guesses` is keyed by card number and valued by **display name**, because that is what
    /// reads at a call site; it is mapped back to the `user_id` the store actually holds here.
    /// - Parameter poolSize: how many names the round's pool holds.
    ///
    ///   The sheet goldens use five — a real six-person group, and a row that fits on an SE.
    ///   Eleven chips do not fit, and the interesting thing about that is the trailing fade and
    ///   the two-row grid that `E11-03` adds, which do not exist yet. Rendering the overflow now
    ///   would only prove that a row wider than the screen is wider than the screen, and it would
    ///   drag the sheet's whole width out with it — `.fixedSize()` propagates its ideal width to
    ///   the enclosing stack, so the copy underneath ends up centred against a phantom width.
    static func store(
        cardCount: Int,
        myCardNumber: Int? = nil,
        canGuess: Bool = true,
        reason: CannotGuessReason? = nil,
        poolSize: Int = members.count,
        guesses: [Int: String] = [:]
    ) -> RevealStore {
        let store = RevealStore(
            cards: (1...cardCount).map(card(number:)),
            pool: Array(members.prefix(poolSize)) + [me],
            myCardNumber: myCardNumber,
            canGuess: canGuess,
            cannotGuessReason: reason,
            me: me.userID
        )
        store.answersAt = answersAt
        let byName = Dictionary(members.map { ($0.displayName, $0.userID) }, uniquingKeysWith: { a, _ in a })
        store.adopt(guesses.compactMap { card, name in
            byName[name].map { GuessDTO(cardNumber: card, guessedUserID: $0) }
        })
        return store
    }
}
