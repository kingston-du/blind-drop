import OSLog
import SwiftUI
import UIKit

/// Turns a `ShareCardView` into a PNG on disk (`docs/10` §4–5).
///
/// Three rules shape this type, and each of them is a way the naive version is quietly wrong:
///
/// 1. **The artwork has to be there.** `ImageRenderer` never runs `.task`, so a card rendered
///    without a prefetch is four `artwork_bg_color` squares — *"render placeholders into a share
///    image and the card is worthless"*. So every image is awaited first, with a **3 second**
///    ceiling, after which the card is rendered with the colour blocks **and the fact is
///    logged** rather than shipped silently.
/// 2. **The face has to be loaded.** `ImageRenderer` falls back to the system face without
///    complaint, and a card in SF Pro looks fine — which is why `Typography.registerDisplayFace`
///    is called here rather than trusted from `Info.plist`.
/// 3. **The file is private and temporary.** *"Never written outside the app's temporary
///    directory, and the temporary file is deleted after the share sheet dismisses"*
///    (`docs/10` §5). The card carries real display names and real song choices from a private
///    group; it exists for exactly as long as the share sheet is up.
@Observable @MainActor
final class ShareRenderer {

    /// *"Await all four image loads, 3s timeout; on timeout render with `artwork_bg_color`
    /// blocks and log it."* (`docs/10` §4)
    static let artworkTimeout = Duration.seconds(3)

    /// The renders this instance has on disk, by variant, so switching thumbnails twice does not
    /// render twice — and so **every** file it has written can be deleted when the sheet closes.
    private(set) var rendered: [ShareCard.Variant: URL] = [:]

    /// Whether a render is in flight. The picker draws a `paperSunk` skeleton meanwhile
    /// (`docs/10` §4).
    private(set) var isRendering = false

    private let loader: any ArtworkLoading
    private let log = Logger(subsystem: "app.blinddrop", category: "share")

    init(loader: any ArtworkLoading) {
        self.loader = loader
    }

    /// The PNG for a variant, rendering it if it is not already on disk.
    ///
    /// - Returns: a file URL inside the app's temporary directory, or `nil` if the render
    ///   failed. A `nil` leaves the picker on its skeleton rather than offering a share of
    ///   nothing.
    func png(for content: ShareCardContent, variant: ShareCard.Variant) async -> URL? {
        if let existing = rendered[variant] { return existing }
        isRendering = true
        defer { isRendering = false }

        // Rule 2, before anything is drawn.
        if !Typography.registerDisplayFace() {
            log.error("share card rendering without the display face — numerals will be SF Pro")
        }
        // Rule 1. The wait is shared across variants because the two cards show the same four
        // tracks: switching to the story thumbnail never re-downloads anything.
        await loadArtwork(for: content)

        guard let image = render(content, variant: variant) else {
            log.error("ImageRenderer produced no share card")
            return nil
        }
        guard let url = await write(image, variant: variant) else { return nil }
        rendered[variant] = url
        return url
    }

    /// Deletes every file this renderer wrote.
    ///
    /// Called from the share sheet's completion handler and from the picker's dismissal — both,
    /// because a user who backs out of the picker without sharing has still had a card written
    /// for them, and `docs/10` §5 does not make the deletion conditional on the share happening.
    func discard() {
        for url in rendered.values {
            try? FileManager.default.removeItem(at: url)
        }
        rendered = [:]
    }

    // MARK: - Rule 1 — the artwork

    /// Awaits every row's artwork, giving up as a group after `artworkTimeout`.
    ///
    /// The timeout is on the **whole** set rather than per image: what the card needs is all four
    /// or a decision, and four sequential three-second waits would be twelve seconds of a person
    /// looking at a skeleton.
    private func loadArtwork(for content: ShareCardContent) async {
        let urls = content.rows.compactMap { card in
            ArtworkView.resolvedURL(
                template: card.track.artworkURL,
                points: ShareCard.artwork,
                scale: ShareCard.scale
            )
        }
        guard !urls.isEmpty else { return }

        /// What one member of the wait reported.
        enum Outcome: Sendable {
            case loaded(Bool)
            case timedOut
            /// The timer, cancelled because the images all landed first.
            case cancelled
        }

        let loader = self.loader
        let loaded = await withTaskGroup(of: Outcome.self, returning: Int.self) { group in
            for url in urls {
                group.addTask { .loaded(await loader.image(for: url) != nil) }
            }
            // The timer is a member of the same group, so whichever finishes first ends the
            // wait and `cancelAll` takes the rest with it — structured, with nothing still
            // running behind the render.
            group.addTask {
                do {
                    try await Task.sleep(for: ShareRenderer.artworkTimeout)
                } catch {
                    return .cancelled
                }
                return .timedOut
            }

            var succeeded = 0
            var reported = 0
            for await outcome in group {
                switch outcome {
                case let .loaded(didLoad):
                    if didLoad { succeeded += 1 }
                    reported += 1
                case .timedOut:
                    reported = urls.count
                case .cancelled:
                    continue
                }
                if reported >= urls.count { break }
            }
            group.cancelAll()
            return succeeded
        }

        if loaded < urls.count {
            // Logged, never hidden: a card of colour blocks is a card worth knowing about.
            log.notice("share card artwork incomplete: \(loaded, privacy: .public) of \(urls.count, privacy: .public)")
        }
    }

    // MARK: - Rendering and writing

    /// `ImageRenderer` is `@MainActor` by construction — a SwiftUI view is laid out on the main
    /// actor and there is no API that is not. So the *drawing* happens here, and the expensive
    /// half, the PNG encode, is what moves off (see `write`).
    private func render(_ content: ShareCardContent, variant: ShareCard.Variant) -> UIImage? {
        let card = ShareCardView(content: content, variant: variant)
            .environment(\.artworkLoader, loader)
            .environment(\.displayScale, ShareCard.scale)

        let renderer = ImageRenderer(content: card)
        renderer.scale = ShareCard.scale
        renderer.proposedSize = ProposedViewSize(variant.size)
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// PNG-encodes off the main actor and writes into the app's temporary directory.
    ///
    /// **The temporary directory and nowhere else** (`docs/10` §5). Not the caches directory,
    /// not the documents directory, not a shared container: the file contains real names and
    /// real song choices from a private group, and the only correct lifetime for it is the one
    /// the share sheet has.
    private func write(_ image: UIImage, variant: ShareCard.Variant) async -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "blind-drop-\(variant.rawValue)-\(UUID().uuidString).png")

        // `docs/10` §1: *"Output PNG. Typical size ~800KB — do not JPEG the artwork."*
        let encoded = await Task.detached(priority: .userInitiated) {
            image.pngData()
        }.value

        guard let encoded else {
            log.error("share card would not encode as PNG")
            return nil
        }
        do {
            // `.completeFileProtection` is the default for the temporary directory on iOS; the
            // atomic write is what stops the share sheet reading a half-written file on a slow
            // device.
            try encoded.write(to: url, options: .atomic)
            return url
        } catch {
            log.error("share card could not be written: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
