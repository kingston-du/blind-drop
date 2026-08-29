import SwiftUI
import Testing
import UIKit
@testable import BlindDrop

private let variants = ShareCard.Variant.allCases

/// **AC-9** (`docs/15`, `docs/10` §6): the share card renders at exactly 1080 × 1800 and
/// 1080 × 1920, at scale 3, in the display face, with the artwork actually loaded.
///
/// This is the app's distribution mechanism (`docs/00` §5), so the goldens here are not a
/// regression net around a minor screen — they are the review surface for the artifact that
/// leaves the device.
@MainActor
@Suite struct ShareCardSnapshots {

    /// The dimensions, from the view's own size and the render scale. Asserted separately from
    /// the goldens because a golden proves the two agree with *each other*; this proves they
    /// agree with `docs/10` §1.
    @Test(arguments: variants)
    func theCardRendersAtItsExactPixelSize(_ variant: ShareCard.Variant) throws {
        let image = ShareCardFixture.render(variant: variant)
        let bitmap = try #require(image.cgImage)

        #expect(CGFloat(bitmap.width) == variant.pixelSize.width)
        #expect(CGFloat(bitmap.height) == variant.pixelSize.height)
        #expect(variant.size.width * ShareCard.scale == variant.pixelSize.width)
    }

    /// The `docs/02` §4.4 night, both artifacts.
    @Test(arguments: variants)
    func theCard(_ variant: ShareCard.Variant) {
        verify(ShareCardFixture.render(variant: variant), named: "Share-\(variant.rawValue)")
    }

    /// The longest name the product allows (`DisplayName.maximumLength`) in the one-line
    /// headline, beside a literal 100% Ear result. The percentage is deliberately rendered,
    /// not inferred from an off-card ranking: this golden catches the exact clipping boundary
    /// that originally cut the final zero off the share image.
    @Test(arguments: variants)
    func theLongestNameAndAHundredPercentTogether(_ variant: ShareCard.Variant) {
        verify(
            ShareCardFixture.render(variant: variant, content: ShareCardFixture.longestName),
            named: "Share-\(variant.rawValue)-longestname"
        )
    }

    /// **The no-personal-night fallback**: the numbered flight and group headline remain, while
    /// the two personal meters and empty room table disappear instead of showing dashes.
    @Test(arguments: variants)
    func theNonSubmitterFallback(_ variant: ShareCard.Variant) {
        verify(
            ShareCardFixture.render(variant: variant, content: ShareCardFixture.nonSubmitter),
            named: "Share-\(variant.rawValue)-nonsubmitter"
        )
    }

    /// **The personal bands' own worst case**: six distinct names in the room's tally, two of
    /// them `DisplayName.maximumLength`, forcing the explicit overflow line. The headline is
    /// deliberately short so this golden isolates the metrics and room table.
    @Test(arguments: variants)
    func thePersonalBandsAtTheirWorstCase(_ variant: ShareCard.Variant) {
        verify(
            ShareCardFixture.render(variant: variant, content: ShareCardFixture.personalStress),
            named: "Share-\(variant.rawValue)-personalstress"
        )
    }

    /// **Amber must not appear** (`docs/10` §3). Nothing on this card is sealed, including the
    /// caller's own song — the one place the reveal screen allowed amber.
    ///
    /// Asserted on the pixels rather than by reading the source, because the leak would arrive
    /// through a component that picks its own accent rather than through a literal in this file.
    @Test(arguments: variants)
    func nothingOnTheCardIsAmber(_ variant: ShareCard.Variant) throws {
        let image = ShareCardFixture.render(variant: variant)
        let amber: [UInt32] = [
            Palette.Hex.amber, Palette.Hex.amberDeep,
            Palette.Hex.amberText, Palette.Hex.amberWash,
        ]

        for hex in amber {
            #expect(!ShareCardFixture.contains(hex, in: image),
                    "amber \(String(hex, radix: 16)) is on the share card")
        }
    }

    /// **The numerals are Bricolage, not the system face** (`docs/10` §4).
    ///
    /// `ImageRenderer` falls back silently if the bundled font is not registered, and a card of
    /// SF Pro numerals looks *fine* — which is exactly why this is a test. Two renders of the
    /// same card, one forced onto the system face, must not produce the same pixels.
    ///
    /// The size is an arbitrary constant of this test's own — `E36-01` retired the card's last
    /// numeral size from the card; it only needs *a* display-face size.
    @Test func theNumeralsAreNotTheSystemFace() throws {
        let testSize: CGFloat = 96
        let bricolage = ShareCardFixture.number(font: Typography.fixed(.display, size: testSize))
        let system = ShareCardFixture.number(font: .systemFont(ofSize: testSize, weight: .semibold))

        #expect(Typography.uiFont(.displayXL).familyName == Typography.displayFamily,
                "the bundled face is registered at all")
        let difference = try #require(SnapshotRenderer.differingFraction(bricolage, system))
        #expect(difference > 0, "the card's numerals are drawn in the display face")
    }

    /// The share sheet (`docs/10` §4): **one square-tall preview, its caption and the button**,
    /// with the live card drawn inside the preview — not the rendered PNG, which is not on disk
    /// yet when the sheet opens.
    ///
    /// Across the device axis still, although the sheet's content is now a fixed width on both:
    /// that is the assertion. A preview sized for one phone is exactly what the old two-thumbnail
    /// picker had to be, and the golden is where a return to that would show up.
    @Test(arguments: SnapshotRenderer.Device.matrix)
    func theSheet(_ device: SnapshotRenderer.Device) {
        SnapshotRenderer.verify(
            SnapshotRenderer.image(of: Self.sheet.snapshotContent, device: device, typeSize: .large),
            named: "Share-sheet-\(device.name)",
            in: "Share"
        )
    }

    /// **The sheet fits the detent it opens at**, measured rather than eyeballed.
    ///
    /// `Layout.shareSheetHeight` is a fixed number arrived at by adding up tokens, and the way that
    /// number goes wrong is silently: a preview one step wider, a caption that grows a line, and
    /// the button is under the fold of a sheet that cannot be dragged for it. The render already
    /// carries the sheet's own `screenInset` on all four sides — `SnapshotRenderer` applies exactly
    /// the padding `body` does — so its height in points is the height the detent has to contain.
    /// On the SE, because a detent that fits the small phone fits every phone.
    @Test func theSheetFitsItsDetent() {
        let image = SnapshotRenderer.image(
            of: Self.sheet.snapshotContent, device: .iPhoneSE, typeSize: .large
        )
        #expect(image.size.height <= Layout.shareSheetHeight,
                "the sheet is \(image.size.height)pt tall against a \(Layout.shareSheetHeight)pt detent")
    }

    // MARK: - Nothing falls off the edge (E36-01)

    /// **The card fits, measured — not eyeballed.**
    ///
    /// `ImageRenderer` does not clip a view that overflows its frame: it draws past the canvas
    /// and the pixels are simply gone, so an overflowing card does not look broken, it looks
    /// *edited*. `E30-01` found exactly this twice by staring at renders (the headline's scale
    /// factor, the Best Ear rate's missing ceiling) before a test existed for it. This is that
    /// test: `ShareCardStack` — the card's content, rendered **without** the fixed outer frame
    /// `ShareCardView` wraps it in — is asked for its natural height at the variant's content
    /// width, and that height has to be no taller than the frame actually gives it.
    ///
    /// Every fixture below is a worst case this card can reach: the longest name the product
    /// allows, a full 100% rate, a room tally past `ShareCard.maximumRoomTallyNames`, and the
    /// fallback with none of the personal bands at all.
    @Test(arguments: variants, ShareCardFixture.fitMatrix)
    func theCardFits(_ variant: ShareCard.Variant, _ content: ShareCardContent) throws {
        let available = variant.size.height - 2 * variant.margin - variant.bottomSafeSpace
        let measured = try ShareCardFixture.measuredHeight(
            of: content,
            variant: variant,
            contentWidth: variant.size.width - 2 * variant.margin
        )
        #expect(measured <= available,
                "\(variant.rawValue) content is \(measured)pt tall against \(available)pt available")
    }

    /// One sheet, built once: it holds a renderer, and every test that draws it wants the same
    /// stubbed one rather than a fresh temporary directory each time.
    private static let sheet = ShareSheet(
        content: ShareCardFixture.tonight,
        renderer: ShareRenderer(loader: StubArtworkLoader.shared)
    )

    private func verify(
        _ image: UIImage,
        named name: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        SnapshotRenderer.verify(image, named: name, in: "Share", sourceLocation: sourceLocation)
    }
}

// MARK: - Fixtures

/// **Not** `@MainActor`, on purpose: `fitMatrix` has to be usable as an `@Test(arguments:)` list,
/// which is evaluated outside actor isolation, and every static fixture here is plain value
/// construction (JSON in, a `ShareCardContent` out) that never needed the actor in the first
/// place. Only `render`/`number`/`measuredHeight` actually touch `ImageRenderer`, which is
/// `@MainActor`-only — those three carry the annotation themselves instead.
enum ShareCardFixture {

    /// The card, rendered the way `docs/10` §1 and §4 say to render it.
    ///
    /// Its own `ImageRenderer` rather than `SnapshotRenderer.image` because the two want
    /// opposite things: the screen renderer proposes a device width, applies the screen inset
    /// and lets the height grow, and the card is a **fixed** rectangle with its own margins that
    /// must come out at an exact pixel size.
    ///
    /// The artwork loader answers from memory, which is not a shortcut but the same rule the
    /// production renderer follows: `ImageRenderer` never runs `.task`, so an image is on the
    /// card only if something put it in the cache first (`docs/10` §4).
    @MainActor static func render(
        variant: ShareCard.Variant,
        content: ShareCardContent = tonight
    ) -> UIImage {
        let card = ShareCardView(content: content, variant: variant)
            .environment(\.artworkLoader, StubArtworkLoader.shared)
            .environment(\.displayScale, ShareCard.scale)

        let renderer = ImageRenderer(content: card)
        renderer.scale = ShareCard.scale
        renderer.proposedSize = ProposedViewSize(variant.size)
        renderer.isOpaque = true
        guard let image = renderer.uiImage else {
            Issue.record("ImageRenderer produced no share card")
            return UIImage()
        }
        return image
    }

    /// One card number drawn on its own, for the display-face check. Small, so the comparison is
    /// about the glyph rather than about everything around it.
    @MainActor static func number(font: UIFont) -> UIImage {
        let view = Text(verbatim: "4")
            .font(Font(font))
            .foregroundStyle(Palette.ink)
            .frame(width: ShareCard.artwork * 2, height: ShareCard.artwork * 2)
            .background(Palette.paper)

        let renderer = ImageRenderer(content: view)
        renderer.scale = ShareCard.scale
        renderer.isOpaque = true
        return renderer.uiImage ?? UIImage()
    }

    /// The `docs/02` §4.4 night: eight cards, four rows and four more.
    static let tonight = ShareCardContent(
        results: results,
        groupName: "The Cove",
        date: "10 August"
    )

    /// `docs/10` §3's width extremes at once: `DisplayName.maximumLength` in the headline and a
    /// caller Ear value of exactly 100%. Both are visible on the artifact.
    static let longestName: ShareCardContent = {
        let name = String("Bartholomew Winterborneiii".prefix(DisplayName.maximumLength))
        #expect(name.count == DisplayName.maximumLength)
        let calID = "a0000000-0000-4000-8000-000000000003"

        var json = payload("results")
        json["people"] = rename(json["people"], id: calID, to: name, idKey: "user_id")
        var me = json["me"] as? [String: Any] ?? [:]
        me["ear"] = 1.0
        json["me"] = me

        return content(from: json)
    }()

    /// **The no-personal-night fallback** (`E36-01`, `docs/10` §2): the caller never dropped a
    /// song, so no card is theirs, `me`'s two rates are both `nil`, and the card falls all the
    /// way back to `E30-01`'s shape.
    static let nonSubmitter: ShareCardContent = {
        var json = payload("results")
        json["cards"] = (json["cards"] as? [[String: Any]] ?? []).map { card -> [String: Any] in
            var card = card
            card["my_guess"] = NSNull()
            card["guesses"] = NSNull()
            return card
        }
        json["me"] = [
            "readability": NSNull(), "readability_correct": NSNull(),
            "readability_possible": NSNull(), "ear": NSNull(),
            "ear_correct": NSNull(), "ear_possible": NSNull(),
        ]
        return content(from: json)
    }()

    /// **The room tally at its own worst case**. Six distinct names are guessed on the caller's
    /// card (past `maximumRoomTallyNames`), two of them the longest the product allows.
    /// `me.readability` sits in the `unreadable` band on purpose so the golden isolates the
    /// table and metrics rather than repeating the headline stress case.
    static let personalStress: ShareCardContent = {
        let longA = String("Bartholomew Winterborneiii".prefix(DisplayName.maximumLength))
        let longB = String("Persephone Castellanosii".prefix(DisplayName.maximumLength))
        #expect(longA.count == DisplayName.maximumLength)
        #expect(longB.count == DisplayName.maximumLength)
        let ownerID = "a0000000-0000-4000-8000-000000000001"

        var json = payload("results")
        json["cards"] = (json["cards"] as? [[String: Any]] ?? []).map { card -> [String: Any] in
            var card = card
            guard card["card_no"] as? Int == 4 else { return card }
            // Six distinct guessed people, the caller's own name (`ownerID`) the only repeat —
            // the tally's "isMe" highlight is exactly this row.
            let guessed: [(id: String, name: String, count: Int)] = [
                (ownerID, "Ana", 2), ("g-long-1", longA, 1), ("g-long-2", longB, 1),
                ("g-ben", "Ben", 1), ("g-dee", "Dee", 1), ("g-fay", "Fay", 1),
            ]
            card["guesses"] = guessed.flatMap { entry in
                (0..<entry.count).map { _ -> [String: Any] in
                    [
                        "guesser_id": "g-guesser", "guesser_name": "Guesser",
                        "guessed_user_id": entry.id, "guessed_name": entry.name,
                        "is_correct": entry.id == ownerID,
                    ]
                }
            }
            return card
        }
        json["me"] = [
            "readability": 0.14, "readability_correct": 1, "readability_possible": 7,
            "ear": 0.5, "ear_correct": 2, "ear_possible": 4,
        ]
        return content(from: json)
    }()

    /// Every fixture `theCardFits` checks — the base night plus every worst case above. A
    /// `Sequence` literal rather than `allCases`: these are hand-picked stress shapes, not an
    /// enum's every member.
    static let fitMatrix: [ShareCardContent] = [tonight, longestName, nonSubmitter, personalStress]

    /// `ShareCardStack`'s natural height at a given content width, with **no ceiling** — the
    /// measurement `theCardFits` compares against the frame `ShareCardView` actually gives it.
    /// `ImageRenderer` is asked for an unbounded height (`ProposedViewSize(width:height:)` with
    /// `height: nil`) so it reports what the content actually needs, not what a canvas would
    /// crop it to.
    @MainActor
    static func measuredHeight(
        of content: ShareCardContent,
        variant: ShareCard.Variant,
        contentWidth: CGFloat
    ) throws -> CGFloat {
        let stack = ShareCardStack(content: content, variant: variant)
            .frame(width: contentWidth, alignment: .topLeading)
            .environment(\.artworkLoader, StubArtworkLoader.shared)
            .environment(\.displayScale, ShareCard.scale)

        let renderer = ImageRenderer(content: stack)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: contentWidth, height: nil)
        renderer.isOpaque = false
        let image = try #require(renderer.uiImage, "ImageRenderer produced no content stack")
        return image.size.height
    }

    /// The `docs/02` §4.4 night's own contract payload.
    ///
    /// Loaded here rather than reused from `ResultsSnapshotFixture` **on purpose**: that type is
    /// `@MainActor` (it builds `ResultsScreen` views), and `fitMatrix` above has to be a plain
    /// value usable outside actor isolation for `@Test(arguments:)`. `ResultsSnapshotFixture`'s
    /// own comment already names the reason two fixture loaders exist here rather than one —
    /// `BlindDropTests/Unit` and `BlindDropTests/Snapshot` share no code, and now two fixture
    /// types inside `Snapshot` don't either, for the same actor-isolation reason.
    static let results: ResultsDTO = {
        try! JSONDecoder.api.decode(ResultsDTO.self, from: data("results"))
    }()

    /// A payload as loose JSON, for a fixture that needs to **edit** the contract before
    /// decoding it.
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

    /// Edits one member's `display_name` by id, in either `people` or `tonight_top_ear` — both
    /// arrays under the same two keys (`user_id`, `display_name`).
    private static func rename(_ list: Any?, id: String, to name: String, idKey: String) -> [[String: Any]] {
        (list as? [[String: Any]] ?? []).map { row -> [String: Any] in
            var row = row
            if row[idKey] as? String == id { row["display_name"] = name }
            return row
        }
    }

    /// Loose JSON, decoded and wrapped — every stress fixture above ends here.
    private static func content(from json: [String: Any]) -> ShareCardContent {
        let results = try! JSONDecoder.api.decode(
            ResultsDTO.self, from: try! JSONSerialization.data(withJSONObject: json)
        )
        return ShareCardContent(results: results, groupName: "The Cove", date: "10 August")
    }

    /// Whether a colour token appears anywhere in the image.
    ///
    /// An exact match on the token's own sRGB value: the card draws flat fills, so a token that
    /// is present is present at full strength somewhere. A tolerance would start matching the
    /// artwork stub, which is a colour nobody chose.
    static func contains(_ hex: UInt32, in image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        let width = cgImage.width, height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return false }

        let red = UInt8((hex >> 16) & 0xFF)
        let green = UInt8((hex >> 8) & 0xFF)
        let blue = UInt8(hex & 0xFF)
        for pixel in stride(from: 0, to: bytes.count, by: 4)
        where bytes[pixel] == red && bytes[pixel + 1] == green && bytes[pixel + 2] == blue {
            return true
        }
        return false
    }
}
