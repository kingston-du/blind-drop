import SwiftUI
import Testing
@testable import BlindDrop

/// File-scope rather than members of the suite: `@Test(arguments:)` evaluates its arguments
/// outside the actor the suite is isolated to.
private let devices = SnapshotRenderer.Device.matrix
private let sizes = SnapshotRenderer.typeSizes

/// `E12-01`'s verify line: the snapshot matrix over the answers.
///
/// Three lengths, for the reason `RevealSnapshots` splits the same way — `UIImage.pngData()`
/// returns `nil` somewhere above eight thousand pixels of height, and a results card is taller
/// than a reveal card, so the long flights carry only `.large`.
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
@MainActor
@Suite struct ResultsSnapshots {

    private static let markStates = [3, 4, 5]

    @Test(arguments: devices, sizes)
    func threeCards(_ device: SnapshotRenderer.Device, _ size: DynamicTypeSize) {
        verify(named: "Results-3", device, size) {
            ResultsSnapshotFixture.screen(cards: ResultsSnapshotFixture.cards(Self.markStates))
        }
    }

    @Test(arguments: devices)
    func theWholeNight(_ device: SnapshotRenderer.Device) {
        verify(named: "Results-8", device, .large) {
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

    /// Force-unwrapped on purpose: a fixture payload that does not decode is a broken
    /// repository, and one loud failure here reads better than every golden failing for a
    /// reason none of them names.
    ///
    /// Read from `ios/Fixtures/payloads` directly, because `BlindDropTests/Unit` and
    /// `BlindDropTests/Snapshot` are separate targets and share no code — the same reason
    /// `SubmitSnapshots` carries its own loader.
    static let results: ResultsDTO = {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Snapshot
            .deletingLastPathComponent()   // BlindDropTests
            .deletingLastPathComponent()   // ios
        return try! JSONDecoder.api.decode(
            ResultsDTO.self,
            from: try! Data(contentsOf: root.appending(path: "Fixtures/payloads/results.json"))
        )
    }()
}
