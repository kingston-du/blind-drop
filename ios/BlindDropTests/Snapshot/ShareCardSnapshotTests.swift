import SwiftUI
import Testing
import UIKit
@testable import BlindDrop

private let variants = ShareCard.Variant.allCases

/// **AC-9** (`docs/15`, `docs/10` §6): the share card renders at exactly 1080 × 1350 and
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

    /// *"Long titles truncate at one line with a middle ellipsis for the title and a tail
    /// ellipsis for the owner. Owner names never truncate before the title does."*
    /// (`docs/10` §3) — `docs/10` §6 asks for exactly this fixture: a 90-character title beside
    /// a 24-character display name.
    @Test(arguments: variants)
    func aLongTitleGivesWayBeforeTheOwnerDoes(_ variant: ShareCard.Variant) {
        verify(
            ShareCardFixture.render(variant: variant, content: ShareCardFixture.longTitles),
            named: "Share-\(variant.rawValue)-long"
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
    @Test func theNumeralsAreNotTheSystemFace() throws {
        let bricolage = ShareCardFixture.number(font: Typography.fixed(
            .display, size: ShareCard.Variant.squareTall.numberSize
        ))
        let system = ShareCardFixture.number(font: .systemFont(
            ofSize: ShareCard.Variant.squareTall.numberSize, weight: .semibold
        ))

        #expect(Typography.uiFont(.displayXL).familyName == Typography.displayFamily,
                "the bundled face is registered at all")
        let difference = try #require(SnapshotRenderer.differingFraction(bricolage, system))
        #expect(difference > 0, "the card's numerals are drawn in the display face")
    }

    private func verify(
        _ image: UIImage,
        named name: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        SnapshotRenderer.verify(image, named: name, in: "Share", sourceLocation: sourceLocation)
    }
}

// MARK: - Fixtures

@MainActor
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
    static func render(
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
    static func number(font: UIFont) -> UIImage {
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
        results: ResultsSnapshotFixture.results,
        groupName: "The Cove",
        date: "10 August"
    )

    /// `docs/10` §6's stress fixture — a 90-character title against a 24-character display name.
    ///
    /// Built by editing the payload and decoding it again, rather than by constructing DTOs: the
    /// types' initialisers are the decoder on purpose (`docs/13` §2), and a fixture assembled
    /// around them would be a picture of a shape the server cannot send.
    static let longTitles: ShareCardContent = {
        // Exactly the two lengths `docs/10` §6 names, built rather than eyeballed — a fixture
        // that is *about* 90 characters proves nothing about the case that breaks at 90.
        let title = String(
            "The Very Long Song Title That Keeps Going Well Past Any Reasonable Width And Then Some More"
                .prefix(90)
        )
        let owner = String("Bartholomew Winterborneiii".prefix(24))
        #expect(title.count == 90)
        #expect(owner.count == 24)

        var json = ResultsSnapshotFixture.payload("results")
        var cards = json["cards"] as? [[String: Any]] ?? []
        for index in cards.indices {
            var card = cards[index]
            var track = card["track"] as? [String: Any] ?? [:]
            track["title"] = title
            card["track"] = track
            card["owner"] = ["user_id": "u_long", "display_name": owner]
            cards[index] = card
        }
        json["cards"] = cards

        let results = try! JSONDecoder.api.decode(
            ResultsDTO.self, from: try! JSONSerialization.data(withJSONObject: json)
        )
        return ShareCardContent(results: results, groupName: "The Cove", date: "10 August")
    }()

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
