import SwiftUI
import Testing
import UIKit
@testable import BlindDrop

/// Draws a view at a given size and Dynamic Type size, and diffs it against a golden PNG.
///
/// Hand-rolled. `docs/13` §1 and `docs/15` §3: the app has **zero third-party dependencies**,
/// and that includes the test target — a snapshot library is a dependency that gets to decide
/// how the app is rendered, which is exactly the decision this file has to make deliberately
/// (`ImageRenderer`, an explicit `displayScale`, no host window, no animation).
///
/// `E08-04` needs it to verify its own components, so it lands here rather than in `E08-07`.
/// `E08-07` builds on top: the device × type-size matrix, the reviewable failure output, the
/// `RECORD_SNAPSHOTS` regeneration path, and the dark-mode test that keeps *light mode only*
/// true.
@MainActor
enum SnapshotRenderer {

    // MARK: - Rendering

    /// Renders a view to a bitmap.
    ///
    /// Deliberately **not** hosted in a `UIWindow`. A hosted render brings a run loop with it,
    /// and with the run loop comes anything asynchronous the view starts: an artwork fetch, a
    /// countdown tick, a `.task`. `ImageRenderer` draws the body exactly once from whatever
    /// state it is handed, which is the only way a golden file means the same thing on the
    /// hundredth run as on the first.
    ///
    /// - Parameters:
    ///   - width: the content width in points. Height is whatever the view asks for, so a
    ///     component that grows at `.accessibility5` produces a taller image rather than a
    ///     clipped one — which is what makes "nothing truncates" (`docs/12` §1) visible in a
    ///     diff instead of invisible behind a fixed frame.
    ///   - scale: points-to-pixels. Fixed per snapshot rather than read from the simulator, so
    ///     the goldens do not depend on which device the suite happened to run on.
    static func image(
        of view: some View,
        width: CGFloat,
        typeSize: DynamicTypeSize,
        scale: CGFloat = 2
    ) -> UIImage {
        let content = view
            .dynamicTypeSize(typeSize)
            .environment(\.displayScale, scale)
            // Every component that draws artwork gets a loader that answers from memory. The
            // real one would return nil here and every card would snapshot its placeholder,
            // which would make the goldens agree about nothing.
            .environment(\.artworkLoader, StubArtworkLoader.shared)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Layout.screenInset)
            // The width is pinned *before* the background, so `paper` covers the whole frame
            // rather than only the intrinsic width of the content. With `isOpaque` on, anything
            // the background does not cover renders black.
            .frame(width: width, alignment: .leading)
            .background(Palette.paper)
            .fixedSize(horizontal: false, vertical: true)

        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        renderer.isOpaque = true
        guard let image = renderer.uiImage else {
            Issue.record("ImageRenderer produced no image — the view failed to lay out")
            return UIImage()
        }
        return image
    }

    // MARK: - Comparison

    /// Compares a render against its golden, recording an issue if they differ.
    ///
    /// - Returns: the mismatch, so a caller that wants to write the actual and the diff
    ///   somewhere reviewable (`E08-07`) has them, or `nil` when the images matched.
    @discardableResult
    static func verify(
        _ image: UIImage,
        named name: String,
        in directory: String,
        record: Bool = isRecording,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> Mismatch? {
        let url = goldenURL(named: name, in: directory)

        guard !record, let data = try? Data(contentsOf: url), let golden = UIImage(data: data) else {
            write(image, to: url, sourceLocation: sourceLocation)
            if !record {
                // A missing golden is not a pass. It is written so the diff is reviewable in
                // the same run, and the test still fails — otherwise a renamed snapshot
                // silently starts asserting nothing.
                Issue.record(
                    "No golden for \(directory)/\(name). Written; review it and re-run.",
                    sourceLocation: sourceLocation
                )
            }
            return nil
        }

        guard let comparison = compare(golden, image) else {
            // Reported in **pixels**. `UIImage.size` is points, and a golden decoded from PNG
            // has scale 1 while a fresh render has scale 2 — comparing those two numbers would
            // print a mismatch for two images that are identical.
            Issue.record(
                """
                \(directory)/\(name): size changed — golden \
                \(golden.cgImage?.width ?? 0)×\(golden.cgImage?.height ?? 0)px, rendered \
                \(image.cgImage?.width ?? 0)×\(image.cgImage?.height ?? 0)px
                """,
                sourceLocation: sourceLocation
            )
            return Mismatch(name: name, directory: directory, expected: golden, actual: image,
                            differingFraction: 1, diff: nil)
        }

        guard comparison.differingFraction > tolerance else { return nil }

        Issue.record(
            """
            \(directory)/\(name): \(percentage(comparison.differingFraction)) of pixels differ \
            (tolerance \(percentage(tolerance))).
            """,
            sourceLocation: sourceLocation
        )
        return Mismatch(
            name: name,
            directory: directory,
            expected: golden,
            actual: image,
            differingFraction: comparison.differingFraction,
            diff: comparison.diff
        )
    }

    /// What a failed comparison produced, for a caller that writes it somewhere.
    struct Mismatch {
        let name: String
        let directory: String
        let expected: UIImage
        let actual: UIImage
        let differingFraction: Double
        /// The differing pixels, in `alert` red over a dimmed copy of the golden.
        let diff: UIImage?
    }

    /// The share of pixels allowed to differ before a snapshot is a failure.
    ///
    /// Not zero, and not a large number either. Text rendering moves by a fraction of a
    /// subpixel between OS point releases, and a zero tolerance turns every one of those into a
    /// wall of red diffs that trains everybody to re-record without looking. Two pixels in a
    /// thousand is below the threshold at which anything a human would call a layout change can
    /// hide.
    static let tolerance = 0.002

    /// Per-channel difference that counts as a differing pixel. Antialiasing noise sits well
    /// under this; a colour token changing sits well over it.
    static let channelTolerance = 12

    /// `RECORD_SNAPSHOTS=1` regenerates goldens instead of asserting against them.
    ///
    /// **It has to be exported to `xcodebuild` as `TEST_RUNNER_RECORD_SNAPSHOTS`:**
    ///
    /// ```
    /// TEST_RUNNER_RECORD_SNAPSHOTS=1 xcodebuild test -scheme BlindDrop \
    ///   -destination '…' -only-testing:BlindDropSnapshotTests
    /// ```
    ///
    /// `xcodebuild` does not forward its whole environment into the simulator; it forwards the
    /// variables prefixed `TEST_RUNNER_`, with the prefix stripped. Two spellings look like they
    /// should work and do not: a plain `RECORD_SNAPSHOTS=1` in front of `xcodebuild` never
    /// leaves the host, and a trailing `TEST_RUNNER_RECORD_SNAPSHOTS=1` *argument* is parsed as
    /// a build setting rather than as an environment variable. Both fail the same quiet way —
    /// the goldens still get written, because a missing golden is written either way, but every
    /// test reports the failure that says so.
    static var isRecording: Bool {
        ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
    }

    // MARK: - Pixels

    private static func compare(_ a: UIImage, _ b: UIImage) -> (differingFraction: Double, diff: UIImage?)? {
        guard let left = raster(a), let right = raster(b),
              left.width == right.width, left.height == right.height
        else { return nil }

        var differing = 0
        var mask = [UInt8](repeating: 0, count: left.width * left.height)
        for pixel in 0..<(left.width * left.height) {
            let offset = pixel * 4
            var isDifferent = false
            for channel in 0..<3 where abs(Int(left.bytes[offset + channel]) - Int(right.bytes[offset + channel])) > channelTolerance {
                isDifferent = true
            }
            if isDifferent {
                differing += 1
                mask[pixel] = 1
            }
        }

        let fraction = Double(differing) / Double(left.width * left.height)
        return (fraction, fraction > 0 ? diffImage(base: left, mask: mask) : nil)
    }

    private struct Raster {
        let width: Int
        let height: Int
        let bytes: [UInt8]
    }

    /// Redraws into one known format — 8-bit sRGB RGBA, premultiplied last — so that two images
    /// are compared as colours rather than as whatever internal representation each arrived in.
    private static func raster(_ image: UIImage) -> Raster? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width, height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let success = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return success ? Raster(width: width, height: height, bytes: bytes) : nil
    }

    /// The golden, dimmed, with every differing pixel painted in `alert` red. A diff nobody can
    /// read is a diff nobody looks at.
    private static func diffImage(base: Raster, mask: [UInt8]) -> UIImage? {
        var bytes = base.bytes
        for pixel in 0..<mask.count {
            let offset = pixel * 4
            if mask[pixel] == 1 {
                bytes[offset] = 0xB3; bytes[offset + 1] = 0x26; bytes[offset + 2] = 0x1E
            } else {
                for channel in 0..<3 {
                    bytes[offset + channel] = UInt8(255 - (255 - Int(bytes[offset + channel])) / 4)
                }
            }
            bytes[offset + 3] = 0xFF
        }
        return image(from: Raster(width: base.width, height: base.height, bytes: bytes))
    }

    private static func image(from raster: Raster) -> UIImage? {
        var bytes = raster.bytes
        return bytes.withUnsafeMutableBytes { buffer -> UIImage? in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: raster.width,
                height: raster.height,
                bitsPerComponent: 8,
                bytesPerRow: raster.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ), let cgImage = context.makeImage() else { return nil }
            return UIImage(cgImage: cgImage)
        }
    }

    // MARK: - Files

    /// `ios/BlindDropTests/__Snapshots__/<directory>/<name>.png`.
    ///
    /// Located from `#filePath` rather than from the test bundle, because a golden has to be
    /// **editable in place**: `RECORD_SNAPSHOTS=1` writes back to the repository, and a copy
    /// inside a built bundle is a file the next build overwrites.
    static func goldenURL(named name: String, in directory: String) -> URL {
        URL(fileURLWithPath: #filePath)          // …/BlindDropTests/Snapshot/SnapshotRenderer.swift
            .deletingLastPathComponent()         // …/BlindDropTests/Snapshot
            .deletingLastPathComponent()         // …/BlindDropTests
            .appending(path: "__Snapshots__")
            .appending(path: directory)
            .appending(path: "\(name).png")
    }

    private static func write(_ image: UIImage, to url: URL, sourceLocation: SourceLocation) {
        guard let data = image.pngData() else {
            Issue.record("Could not encode \(url.lastPathComponent)", sourceLocation: sourceLocation)
            return
        }
        // swift-testing runs these in parallel, so several snapshots reach a missing
        // `__Snapshots__` at once. `withIntermediateDirectories: true` is idempotent about a
        // directory that already exists but not about one appearing mid-call, so the loser of
        // that race throws — which is why the result is discarded and only the write is
        // reported on. A directory that genuinely cannot be made fails at the write anyway.
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        do {
            try data.write(to: url)
        } catch {
            Issue.record("Could not write \(url.path): \(error)", sourceLocation: sourceLocation)
        }
    }

    private static func percentage(_ fraction: Double) -> String {
        String(format: "%.3f%%", fraction * 100)
    }
}

/// An artwork loader that answers from memory and never touches the network.
///
/// Album art in a golden PNG would mean a test that fails when a CDN does, and a licensed
/// image in the repository. A flat colour is enough: what the snapshots are asserting is the
/// *layout* around the artwork and the radius applied to it.
final class StubArtworkLoader: ArtworkLoading {
    static let shared = StubArtworkLoader()

    private let image: UIImage

    init() {
        let size = CGSize(width: 64, height: 64)
        let renderer = UIGraphicsImageRenderer(size: size)
        image = renderer.image { context in
            UIColor(red: 0.11, green: 0.17, blue: 0.23, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    func cachedImage(for url: URL) -> UIImage? { image }
    func image(for url: URL) async -> UIImage? { image }
}
