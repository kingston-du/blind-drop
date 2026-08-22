import SwiftUI
import UIKit

/// Album artwork — **the only imagery in the app**, and the visual anchor of every card
/// (`docs/07` §4).
///
/// Nothing is layered on top of it. No gradient scrim, no play-button chrome, no rounded mask
/// beyond `Radius.artwork`. The one thing drawn behind it is the placeholder, which is Apple's
/// extracted dominant colour at 12% over `surface` and is used for nothing else (`docs/06` §2.1).
struct ArtworkView: View {
    /// Apple's literal `{w}x{h}` template, stored rather than resolved (`docs/06` §2.1).
    let template: String?
    /// `artwork_bg_color` — six hex digits, no `#`. Nullable, and often is.
    let backgroundColor: String?
    /// The drawn size in points. The pixel size requested is this × the display scale.
    let size: CGFloat
    /// Whether the artwork takes the width it is offered instead of `size`, staying square.
    ///
    /// `size` still decides what is *fetched* — the sealed card is as wide as the card it is on,
    /// which is a number the card does not know until it is laid out, and a URL cannot wait for
    /// layout. `Layout.Artwork.confirm` is the size that covers every phone at that spot.
    let fillsWidth: Bool

    @Environment(\.artworkLoader) private var loader
    @Environment(\.displayScale) private var displayScale
    /// The decoded bitmap, keyed to the URL it was decoded from. The key matters: a card whose
    /// track changes in place (a replacement on `SealedScreen`) is the same view instance, so an
    /// un-keyed `UIImage?` would keep showing the first song's artwork while `.task(id: url)`'s
    /// guard then refused to fetch the new one.
    @State private var loaded: (url: URL, image: UIImage)?

    init(template: String?, backgroundColor: String?, size: CGFloat, fillsWidth: Bool = false) {
        self.template = template
        self.backgroundColor = backgroundColor
        self.size = size
        self.fillsWidth = fillsWidth
    }

    init(_ track: TrackDTO, size: CGFloat, fillsWidth: Bool = false) {
        self.init(
            template: track.artworkURL,
            backgroundColor: track.artworkBackgroundColor,
            size: size,
            fillsWidth: fillsWidth
        )
    }

    private var url: URL? {
        ArtworkView.resolvedURL(template: template, points: size, scale: displayScale)
    }

    /// The image to draw, if there is one.
    ///
    /// Read through the loader's **synchronous** cache as well as the `@State` the async load
    /// fills, so a card scrolling back into view redraws with its artwork in the same frame
    /// rather than flashing its placeholder for one runloop. It is also what makes a snapshot
    /// deterministic: `ImageRenderer` never runs `.task`, so a rendered artwork is one the test
    /// put in the cache and nothing else.
    private var image: UIImage? {
        if let loaded, let url, loaded.url == url { return loaded.image }
        guard let url else { return nil }
        return loader.cachedImage(for: url)
    }

    var body: some View {
        placeholder
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .modifier(ArtworkFrame(size: size, fillsWidth: fillsWidth))
            .clipShape(RoundedRectangle(cornerRadius: Radius.artwork, style: .continuous))
            .accessibilityHidden(true)  // the card announces the track; the art is not a fact
            .task(id: url) {
                guard let url, loaded?.url != url else { return }
                loaded = await loader.image(for: url).map { (url: url, image: $0) }
            }
    }

    /// `surface` with the track's dominant colour at 12% over it. Never a gradient, never an
    /// accent, never tinting the card it sits on (`docs/06` §2.1).
    private var placeholder: some View {
        Palette.surface.overlay(ArtworkView.placeholderColor(backgroundColor))
    }

    // MARK: - The two pure parts, which is where the rules actually live

    /// `docs/06` §2.1: substitute at render time, at the display scale, **capped at 1200**.
    ///
    /// > *"Never request a size larger than needed — this runs on cellular at 8pm."*
    ///
    /// The cap is on the pixel size rather than the point size, which is the only reading that
    /// does anything: 300pt of share card at 3× is 900px and fine, while a 600pt confirm card
    /// at 3× would be 1800px of album art fetched over a phone network to be drawn at a third
    /// of that.
    static func resolvedURL(template: String?, points: CGFloat, scale: CGFloat) -> URL? {
        guard let template, !template.isEmpty else { return nil }
        let pixels = min(1200, max(1, Int((points * max(1, scale)).rounded())))
        let resolved = template
            .replacingOccurrences(of: "{w}", with: String(pixels))
            .replacingOccurrences(of: "{h}", with: String(pixels))
        return URL(string: resolved)
    }

    /// The placeholder fill: the six-hex-digit `artwork_bg_color` at 12%, or nothing.
    ///
    /// A colour that will not parse returns clear rather than a guess. `artwork_bg_color` is
    /// nullable in the contract and a card with no dominant colour is a normal card, not a
    /// broken one.
    static func placeholderColor(_ hex: String?) -> Color {
        guard let hex else { return .clear }
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return .clear }
        return Color(hex: value).opacity(0.12)
    }
}

/// Square either way: a fixed side, or the offered width.
private struct ArtworkFrame: ViewModifier {
    let size: CGFloat
    let fillsWidth: Bool

    func body(content: Content) -> some View {
        if fillsWidth {
            content.frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
        } else {
            content.frame(width: size, height: size)
        }
    }
}

// MARK: - Loading

/// What fetches an artwork bitmap.
///
/// A protocol with a synchronous cache read on it, because the view needs to answer *"do I have
/// this already"* while it is building its body — see `ArtworkView.image`. A test substitutes an
/// implementation that answers from a dictionary and never touches the network.
protocol ArtworkLoading: Sendable {
    /// The image if it is already in memory. Must not block.
    func cachedImage(for url: URL) -> UIImage?
    /// The image, fetching it if necessary. Returns `nil` on any failure — a card with no
    /// artwork renders its placeholder, which is a state the design already has.
    func image(for url: URL) async -> UIImage?
}

/// The real one: `URLSession` plus an in-memory cache, no disk layer and no dependency.
///
/// Artwork is already on Apple's CDN behind `URLCache`; a second disk cache would be a second
/// eviction policy to get wrong. This one exists so that scrolling a twelve-card reveal does not
/// re-decode twelve JPEGs on every pass.
final class ArtworkLoader: ArtworkLoading {
    private let session: URLSession
    /// `NSCache` is documented as thread-safe and predates `Sendable`, so the compiler cannot
    /// see what the header guarantees. `nonisolated(unsafe)` says exactly that and nothing more.
    /// It is **not** `@unchecked Sendable` on the class — that would silence the check for every
    /// property this type ever gains, which is why `ios/scripts/lint.sh` rule 5 bans it.
    private nonisolated(unsafe) let cache = NSCache<NSURL, UIImage>()

    init(session: URLSession = .shared) {
        self.session = session
        cache.countLimit = 60
    }

    func cachedImage(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> UIImage? {
        if let cached = cachedImage(for: url) { return cached }
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data)
        else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

private struct ArtworkLoaderKey: EnvironmentKey {
    /// One loader, shared by every view that does not have one injected.
    ///
    /// This is the SwiftUI environment's default value, not a global: there is no
    /// `ArtworkLoader.shared` to reach for, and any subtree — a test, a preview, the share-card
    /// renderer — replaces it with `.environment(\.artworkLoader, …)`. `CLAUDE.md` §4's rule is
    /// about ambient access, and there is none here.
    static let defaultValue: any ArtworkLoading = ArtworkLoader()
}

extension EnvironmentValues {
    var artworkLoader: any ArtworkLoading {
        get { self[ArtworkLoaderKey.self] }
        set { self[ArtworkLoaderKey.self] = newValue }
    }
}
