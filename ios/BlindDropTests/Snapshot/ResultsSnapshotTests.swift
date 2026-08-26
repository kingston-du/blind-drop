import SwiftUI
import Testing
@testable import BlindDrop

/// File-scope rather than members of the suite: `@Test(arguments:)` evaluates its arguments
/// outside the actor the suite is isolated to.
private let devices = SnapshotRenderer.Device.matrix
private let sizes = SnapshotRenderer.typeSizes

/// The results screen's goldens — `E12-01`'s answers and `E12-02`'s **You** pair.
///
/// The flights come in three lengths, for the reason `RevealSnapshots` splits the same way:
/// `UIImage.pngData()` returns `nil` somewhere above eight thousand pixels of height, and a
/// results card is taller than a reveal card, so the long flights carry only `.large`.
///
/// - **Three cards, the full 2 × 3 matrix.** Nos. 3, 4 and 5 — a guess the caller got, a card
///   they never guessed, and a guess they got wrong — so every mark state is in one image. At
///   `.accessibility1` `FlightCard` reflows its number above the artwork; at `.accessibility5`
///   the question is whether the owner's name, the count and the struck guess all still fit.
/// - **The whole night, `.large`.** The `docs/02` §4.4 round as the fixture sends it, which is
///   the render a person would recognise.
/// - **Mid-sequence, `.large`.** The name-resolve caught halfway: one card settled, one with its
///   name but not yet its mark, one with neither. The geometry has to be identical to the
///   settled render — *nothing lays out during the animation* (`docs/09` §1) — and that is a
///   claim only a picture of the middle can make.
///
/// **What every card golden here cannot show.** Since `E17-03` the answer card's track links are
/// a `Menu` in its top right, and `ImageRenderer` draws a `Menu` as a yellow "unsupported view"
/// placeholder — it is UIKit-backed and there is no host window to build it in. The placeholder
/// occupies the menu's **real 44 × 44 frame**, so the claims these goldens make about it are the
/// true ones: that it sits in the corner, and that nothing collides with it at any type size.
/// Only the ellipsis glyph inside is lost. Do not fix this by branching the card on a test-only
/// flag — the golden would then be a picture of something the app never renders.
@MainActor
@Suite struct ResultsSnapshots {

    private static let markStates = [3, 4, 5]

    @Test(arguments: devices, sizes)
    func threeCards(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        // No. 4's new "who guessed you" disclosure (`E29-01`) adds real height, and at 3× the
        // wide accessibility-five case is now over ImageIO's simulator PNG limit — the same
        // ~8000px ceiling `SnapshotRenderer`'s own docs name. The cap is a no-op at every other
        // size in this matrix; only 15 Pro Max × accessibility5 is anywhere near it.
        verify(named: "Results-3", device, size, maximumPixelCount: 8_000_000) {
            ResultsSnapshotFixture.screen(cards: ResultsSnapshotFixture.cards(Self.markStates))
        }
    }

    /// SE only, not the full `devices` matrix.
    ///
    /// The reason was the track links: two independently 44pt-tall tap targets (`docs/12` §5) and
    /// the gap above them were ~90pt on every card, and eight cards of that on the 15 Pro Max's
    /// wider, higher-scale canvas pushed the render past `UIImage.pngData()`'s ceiling — the same
    /// one this file's header describes trimming `.accessibility1`/`5` off for. `E17-03` spent
    /// that height: the links are now one 44pt ellipsis in the card's top right
    /// (`TrackUtilityMenu`), sharing a row with content that was already taller than it, so they
    /// cost the card nothing at all.
    ///
    /// It stays SE-only anyway. The ceiling is a limit on this golden's *worst* case, not its
    /// current one, and a whole-night render is the picture that grows every time a card gains a
    /// line — the three-card matrix above is where the per-device differences are actually
    /// checked, and this one is here to be recognisable as a night.
    @Test
    func theWholeNight() {
        verify(named: "Results-8", .iPhoneSE, .large) {
            ResultsSnapshotFixture.screen(cards: ResultsSnapshotFixture.allCards)
        }
    }

    /// Halfway through the arrival, at the same three cards the matrix uses.
    @Test(arguments: devices)
    func midSequence(_ device: SnapshotRenderer.Device) {
        verify(named: "Results-3-resolving", device, .large) {
            ResultsSnapshotFixture.screen(
                cards: ResultsSnapshotFixture.cards(Self.markStates),
                named: [3, 4],
                marked: [3]
            )
        }
    }

    // MARK: - §7.2 You (E12-02)

    /// The pair, at the three type sizes `E12-02` asks for. `.accessibility1` is where
    /// `docs/12` §1 requires it to have stacked, and `.accessibility5` is where the two
    /// sentences under the numbers either still fit or visibly do not.
    @Test(arguments: devices, sizes)
    func personalStats(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "Results-you", device, size) {
            ResultsSnapshotFixture.stats(ResultsSnapshotFixture.results.me)
        }
    }

    /// **The `null` ear.** Eli's night: they dropped a song and never opened the sheet, so the
    /// ear is `nil` and renders as *"—"* over *"You sat this one out."* — **never `0%`**
    /// (`docs/04` §4). The golden exists so that a regression to a zero is a picture somebody
    /// can look at.
    @Test(arguments: devices)
    func personalStatsWithNoEar(_ device: SnapshotRenderer.Device) {
        verify(named: "Results-you-noear", device, .large) {
            ResultsSnapshotFixture.stats(PersonalScoreDTO.satOutTheGuessing)
        }
    }

    /// The non-submitter's night: **readability absent, not zero**, and no meter under it —
    /// there is no position on the spectrum for somebody who was not in the room.
    @Test(arguments: devices)
    func personalStatsForANonSubmitter(_ device: SnapshotRenderer.Device) {
        verify(named: "Results-you-nodrop", device, .large) {
            ResultsSnapshotFixture.stats(PersonalScoreDTO.didNotDrop)
        }
    }

    // MARK: - §7.3 Standings (E12-03)

    /// The two lists, and the asymmetry between them: **Best Ear** ranked 1..N down the left,
    /// **Readability** with no number in front of any name (`docs/02` §4.5). The golden is what
    /// makes that difference something a reviewer sees rather than something a comment claims.
    ///
    /// `.large` and `.accessibility1` — the latter is where both rows stack and the readability
    /// row's two fixed columns stop existing. `.accessibility5` is left off deliberately: at
    /// fifteen stacked rows it is well past the height `UIImage.pngData()` will encode, and
    /// `A11yReachabilityTests` is where that size is actually checked.
    @Test(arguments: devices, [DynamicTypeSize.large, .accessibility1])
    func standings(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "Results-standings", device, size) {
            StandingsView(standings: ResultsSnapshotFixture.standings)
        }
    }

    /// The longest names the product allows, in both lists.
    ///
    /// `DisplayName.maximumLength` is 24 characters, and at `.large` that is most of an SE's
    /// width — enough to wrap a name onto a second line and leave its percentage floating beside
    /// the third. Both rows hold their names to one truncating line while they are rows, which is
    /// a claim only a picture of a long name can check.
    @Test(arguments: devices)
    func standingsWithTheLongestNames(_ device: SnapshotRenderer.Device) {
        verify(named: "Results-standings-longnames", device, .large) {
            StandingsView(standings: ResultsSnapshotFixture.standingsWithLongNames)
        }
    }

    // MARK: - E29-01: who guessed you, and tonight's top three

    /// Six guesses against one card, the fixture's own §4.4 shape (`docs/02` §4.3's duplicate —
    /// Ana and Ben both dropped "Ribs" — makes every one of them correct, so this golden is also
    /// the only place four back-to-back `Hit`s are on screen at once).
    @Test(arguments: devices, sizes)
    func guessedYou(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "Results-guessedyou", device, size) {
            GuessedYouDisclosure(guesses: ResultsSnapshotFixture.myGuesses)
        }
    }

    /// Nobody has guessed this card yet — an empty list, not an absent one (`docs/04` §4): the
    /// caller's card exists and no one has opened a sheet against it, which is a different fact
    /// from the `nil` every other card carries.
    @Test(arguments: devices)
    func guessedYouEmpty(_ device: SnapshotRenderer.Device) {
        verify(named: "Results-guessedyou-empty", device, .large) {
            GuessedYouDisclosure(guesses: [])
        }
    }

    /// Cal alone at rank 1, and Fay/Hal tied at rank 3 — the fixture's own boundary tie, kept
    /// whole rather than truncated to three rows.
    @Test(arguments: devices, sizes)
    func tonightTopEar(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "Results-tonight", device, size) {
            TonightTopEarView(rows: ResultsSnapshotFixture.results.tonightTopEar)
        }
    }

    private func verify(
        named name: String,
        _ device: SnapshotRenderer.Device,
        _ size: DynamicTypeSize,
        maximumPixelCount: Int? = nil,
        sourceLocation: SourceLocation = #_sourceLocation,
        @ViewBuilder content: () -> some View
    ) {
        let image = SnapshotRenderer.image(
            of: content(), device: device, typeSize: size, maximumPixelCount: maximumPixelCount
        )
        SnapshotRenderer.verify(
            image,
            named: "\(name)-\(device.name)-\(size.snapshotName)",
            in: "Results",
            sourceLocation: sourceLocation
        )
    }
}

// MARK: - Fixtures

/// The §4.4 answers, as a value.
///
/// Decoded from `ios/Fixtures/payloads/results.json` — the contract verbatim (`E00-05`) — rather
/// than hand-built, so a golden is a picture of the shape the server actually sends. The screen
/// takes a `ResultsViewState`, which is what makes a *mid-sequence* render buildable at all: no
/// store, no network, and no waiting on an animation to be caught halfway.
@MainActor
enum ResultsSnapshotFixture {

    /// The screen, drawn without its scroll container — `ImageRenderer` does not draw one at
    /// all, so a golden of `body` would be a picture of an empty rectangle.
    ///
    /// - Parameters:
    ///   - named: the cards whose owner has arrived, or `nil` for *all of them*.
    ///   - marked: the cards whose mark has arrived, or `nil` for *all of them*.
    static func screen(
        cards: [ResultCardDTO],
        named: Set<Int>? = nil,
        marked: Set<Int>? = nil
    ) -> some View {
        ResultsScreen(
            state: ResultsViewState(cards: cards, namedCards: named, markedCards: marked)
        )
        .snapshotContent
    }

    /// Cards picked by number rather than by a prefix.
    ///
    /// The §4.4 night opens with three cards the caller got right, which would make a
    /// three-card golden a picture of one mark state repeated. Nos. 3, 4 and 5 are a correct
    /// guess, no guess at all, and a wrong one — every state the card can be in, in one image.
    static func cards(_ numbers: [Int]) -> [ResultCardDTO] {
        numbers.compactMap { number in results.cards.first { $0.cardNumber == number } }
    }

    /// The whole night, in the order the server sent it.
    static var allCards: [ResultCardDTO] { results.cards }

    /// Every guess against card No. 4 — Ana's own — the six-entry list `E29-01`'s "who guessed
    /// you" disclosure draws.
    static var myGuesses: [CardGuessDTO] {
        results.cards.first { $0.cardNumber == 4 }?.guesses ?? []
    }

    /// The **You** pair on its own, so the two absent-rate goldens are pictures of the pair
    /// rather than of a whole screen with an empty flight above it.
    static func stats(_ me: PersonalScoreDTO) -> some View {
        PersonalStats(me: me)
    }

    /// Force-unwrapped on purpose: a fixture payload that does not decode is a broken
    /// repository, and one loud failure here reads better than every golden failing for a
    /// reason none of them names.
    ///
    /// Read from `ios/Fixtures/payloads` directly, because `BlindDropTests/Unit` and
    /// `BlindDropTests/Snapshot` are separate targets and share no code — the same reason
    /// `SubmitSnapshots` carries its own loader.
    static let results: ResultsDTO = decoded("results")

    /// The group's all-time lists, with Fay's readability deliberately absent. She is in Best
    /// Ear because she guesses, but has never dropped a song to be read; the row must render
    /// `Read —`, never `Read 0%`. The normal standings matrix rather than a special one carries
    /// this case so the product's default table continues to picture the honest absence.
    static let standings: StandingsDTO = {
        var json = payload("standings")
        json["readability"] = (json["readability"] as? [[String: Any]] ?? []).filter {
            $0["user_id"] as? String != "a0000000-0000-4000-8000-000000000006"
        }
        return try! JSONDecoder.api.decode(
            StandingsDTO.self, from: try! JSONSerialization.data(withJSONObject: json)
        )
    }()

    /// The same standings with every name at `DisplayName.maximumLength`.
    ///
    /// Built by editing the payload and decoding it again — the DTOs' initialiser is the decoder
    /// on purpose (`docs/13` §2), so a fixture is JSON.
    static let standingsWithLongNames: StandingsDTO = {
        let name = String("Bartholomew Winterborneiii".prefix(DisplayName.maximumLength))
        #expect(name.count == DisplayName.maximumLength)

        var json = payload("standings")
        for list in ["best_ear", "readability"] {
            json[list] = (json[list] as? [[String: Any]] ?? []).map { row in
                var row = row
                row["display_name"] = name
                return row
            }
        }
        return try! JSONDecoder.api.decode(
            StandingsDTO.self, from: try! JSONSerialization.data(withJSONObject: json)
        )
    }()

    private static func decoded<T: Decodable>(_ name: String) -> T {
        try! JSONDecoder.api.decode(T.self, from: data(name))
    }

    /// A payload as loose JSON, for a fixture that needs to **edit** the contract before
    /// decoding it — the long-title share card is the only one (`docs/10` §6).
    static func payload(_ name: String) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: data(name)) as? [String: Any] ?? [:]
    }

    private static func data(_ name: String) -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Snapshot
            .deletingLastPathComponent()   // BlindDropTests
            .deletingLastPathComponent()   // ios
        return try! Data(contentsOf: root.appending(path: "Fixtures/payloads/\(name).json"))
    }
}

extension PersonalScoreDTO {

    /// Eli's night in `docs/02` §4.4: dropped a song, opened nothing. **`ear` is `nil`, not
    /// `0`** — and the counts beside it go `nil` with it, because "of how many" is meaningless
    /// for a sheet nobody filled in.
    static let satOutTheGuessing = PersonalScoreDTO(
        readability: 0.143,
        readabilityCorrect: 1,
        readabilityPossible: 7,
        ear: nil,
        earCorrect: nil,
        earPossible: nil
    )

    /// Ivy's night: no drop, so **no readability at all**. Not a zero — no card of hers was in
    /// the room for anybody to read (`docs/04` §4).
    static let didNotDrop = PersonalScoreDTO(
        readability: nil,
        readabilityCorrect: nil,
        readabilityPossible: nil,
        ear: nil,
        earCorrect: nil,
        earPossible: nil
    )
}
