import Foundation
import Testing
import UIKit
@testable import BlindDrop

/// `E12-05` and **AC-9**'s two behavioural rows (`docs/10` §6): *"all artwork loaded before
/// render, placeholder path only on timeout"* and *"temp file deleted after the share sheet
/// completes"*.
///
/// The pixels are `ShareCardSnapshots`' business. What is asserted here is everything around
/// them — the wait, the timeout, where the file goes, and when it stops existing.
@MainActor
// These tests all PNG-encode full-resolution share cards. Running the suite's cases against one
// another turns the performance guard into a measurement of concurrent test contention rather
// than one render, and makes every cleanup assertion harder to reason about. Other suites still
// run in parallel; the renderer's own lifecycle is intentionally exercised serially.
@Suite(.serialized) struct ShareRendererTests {

    // MARK: - The artwork (docs/10 §4)

    /// **Every image is awaited before a single pixel is drawn.**
    ///
    /// `ImageRenderer` never runs `.task`, so a card rendered without this is four
    /// `artwork_bg_color` squares — *"render placeholders into a share image and the card is
    /// worthless"*. The loader counts what it was asked for and, more to the point, *when*.
    @Test func everyArtworkIsLoadedBeforeTheCardIsDrawn() async throws {
        let loader = CountingArtworkLoader()
        let renderer = ShareRenderer(loader: loader)

        let url = try #require(await renderer.png(for: ShareFixture.tonight, variant: .squareTall))
        defer { renderer.discard() }

        // Every artwork the four rows point at, fetched before the render. Three rather than
        // four, because Ana and Ben both dropped *Ribs* in the `docs/02` §4.4 round — which is
        // exactly why the expectation is derived from the content rather than written as a
        // number. `loadedBeforeFirstCacheRead` is the *before*: the render reads the cache, so a
        // cache read while a load is still in flight is a card drawn on placeholders.
        #expect(loader.requested == ShareFixture.artworkURLs)
        #expect(loader.loadedBeforeFirstCacheRead)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    /// **A slow CDN does not hold the card hostage.** After the timeout the render happens
    /// anyway, with the `artwork_bg_color` blocks `ArtworkView` already draws — the state
    /// `docs/10` §4 explicitly allows, *"and log it"*.
    ///
    /// The timeout is shortened by handing the loader a wait longer than the test wants to
    /// spend; what is asserted is that the render still produced a file rather than hanging.
    @Test func aSlowArtworkFetchStillProducesACard() async throws {
        let loader = CountingArtworkLoader(delay: .milliseconds(80), succeeds: false)
        let renderer = ShareRenderer(loader: loader)

        let url = try #require(await renderer.png(for: ShareFixture.tonight, variant: .squareTall))
        defer { renderer.discard() }

        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(loader.requested == ShareFixture.artworkURLs, "it still tried")
    }

    // MARK: - The file (docs/10 §5)

    /// **Only the temporary directory.** Not caches, not documents, not a shared container: the
    /// card carries real display names and real song choices from a private group.
    @Test func theCardIsWrittenOnlyToTheTemporaryDirectory() async throws {
        let renderer = ShareRenderer(loader: CountingArtworkLoader())
        let url = try #require(await renderer.png(for: ShareFixture.tonight, variant: .squareTall))
        defer { renderer.discard() }

        let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.path
        #expect(url.standardizedFileURL.path.hasPrefix(temporary))
        #expect(url.pathExtension == "png")
    }

    /// **The file is absent after the completion handler runs** (`docs/10` §6). `discard()` is
    /// what the share sheet's `completionWithItemsHandler` calls, so this is that handler.
    @Test func theTempFileIsGoneAfterTheShareSheetCompletes() async throws {
        let renderer = ShareRenderer(loader: CountingArtworkLoader())
        let url = try #require(await renderer.png(for: ShareFixture.tonight, variant: .squareTall))
        #expect(FileManager.default.fileExists(atPath: url.path))

        renderer.discard()

        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    /// **Both** variants are cleaned up, not only the one that was shared.
    ///
    /// The UI asks for one shape now (`ShareSheet` draws square-tall and offers no choice), so this
    /// is the renderer's contract rather than a sequence a user can currently produce: `discard()`
    /// answers for everything it wrote, whatever asked for it. `.story` is still spec'd, still
    /// rendered on demand, and a cleanup that only swept the shape the UI happened to use would be
    /// a card of real display names left in the temporary directory the day the other one is asked
    /// for again.
    @Test func everyVariantWrittenIsAlsoDeleted() async throws {
        let renderer = ShareRenderer(loader: CountingArtworkLoader())
        var urls: [URL] = []
        for variant in ShareCard.Variant.allCases {
            urls.append(try #require(await renderer.png(for: ShareFixture.tonight, variant: variant)))
        }
        #expect(urls.count == 2)

        renderer.discard()

        for url in urls {
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    /// **Two asks for the same variant at once produce one file, not two.**
    ///
    /// This is the sheet's ordinary sequence, not a contrived one: it starts the card rendering the
    /// moment it appears and the button asks for the same one as soon as a thumb lands, well inside
    /// the time a render takes. Two renders would mean two files and one of them orphaned — a card
    /// of real names left in the temporary directory with nothing holding its name.
    @Test func twoSimultaneousAsksForOneVariantRenderOnce() async throws {
        let renderer = ShareRenderer(loader: CountingArtworkLoader(delay: .milliseconds(20)))

        async let first = renderer.png(for: ShareFixture.tonight, variant: .squareTall)
        async let second = renderer.png(for: ShareFixture.tonight, variant: .squareTall)
        let urls = try #require(await [first, second] as? [URL])

        #expect(urls[0] == urls[1])
        renderer.discard()
        #expect(!FileManager.default.fileExists(atPath: urls[0].path))
    }

    /// And whatever *did* reach disk is deleted, however it got there. `discard()` works from
    /// the list of files written rather than from the by-variant cache, so a second render that
    /// replaced a cache entry cannot leave the first file behind.
    @Test func everyFileEverWrittenIsDeleted() async throws {
        let renderer = ShareRenderer(loader: CountingArtworkLoader())
        var urls: [URL] = []
        for _ in 0..<2 {
            urls.append(try #require(await renderer.png(for: ShareFixture.tonight, variant: .story)))
            // Clearing the cache without clearing the files is exactly the shape of the bug:
            // the next render writes a second file and the first has nowhere to be found.
            renderer.forgetCachedRendersForTesting()
        }
        #expect(Set(urls).count == 2, "the cache really was cleared between renders")

        renderer.discard()

        for url in urls {
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    /// **A render still in flight when the sheet closes cleans up after itself.**
    ///
    /// `discard()` sweeps the files it knows about, and a render that has not written yet is not
    /// one of them — so without a generation check the sweep runs, the render finishes, and a
    /// card of real display names is left in the temporary directory with nothing holding its
    /// name. Dismissing the sheet the moment it opens is all it takes.
    @Test func aRenderThatFinishesAfterDiscardCleansUpAfterItself() async throws {
        let renderer = ShareRenderer(loader: CountingArtworkLoader(delay: .milliseconds(500)))

        async let pending = renderer.png(for: ShareFixture.tonight, variant: .squareTall)
        // Yield until the render has actually started rather than sleeping a guessed interval:
        // under a full parallel suite a fixed sleep can resume after the render has finished,
        // and a test that only sometimes exercises the race is worse than no test.
        while !renderer.isRendering { await Task.yield() }
        renderer.discard()
        let url = await pending

        #expect(url == nil, "a render the sheet no longer wants is not offered")
        // Asserted on the renderer's own ledger rather than on the temporary directory: suites
        // run in parallel, so a listing of `blind-drop-*` files is somebody else's business as
        // much as this test's. Without the generation check `written` holds one URL here — the
        // file appended *after* `discard()` swept — and the file it names is still on disk.
        #expect(renderer.written.isEmpty, "and nothing of it is left behind")
    }

    /// A second ask for the same variant re-uses the file rather than rendering again — which is
    /// also what keeps `discard()` able to name everything it wrote.
    @Test func aSecondRenderOfTheSameVariantIsTheSameFile() async throws {
        let renderer = ShareRenderer(loader: CountingArtworkLoader())
        let first = try #require(await renderer.png(for: ShareFixture.tonight, variant: .squareTall))
        let second = try #require(await renderer.png(for: ShareFixture.tonight, variant: .squareTall))
        defer { renderer.discard() }

        #expect(first == second)
    }

    /// *"Render happens off the main thread, target < 250ms"* (`docs/10` §4).
    ///
    /// Two honest caveats, both of them worth writing down rather than dressing up:
    ///
    /// - `ImageRenderer` is `@MainActor` by construction — a SwiftUI view is laid out on the
    ///   main actor and there is no API that is not. What moves off is the PNG encode, which is
    ///   the expensive half.
    /// - The ceiling asserted here is **not** the target. A simulator sharing a machine with a
    ///   build is not the phone the 250ms is about, so a test that gated on it would fail for
    ///   reasons that have nothing to do with this code. What this catches is the shape of a
    ///   regression — an accidental synchronous download, a render per body pass — while the
    ///   target itself belongs to `E14-03`'s Instruments pass.
    @Test func theRenderIsQuickWithItsArtworkAlreadyInHand() async throws {
        let renderer = ShareRenderer(loader: CountingArtworkLoader())
        let started = ContinuousClock.now
        _ = try #require(await renderer.png(for: ShareFixture.tonight, variant: .squareTall))
        let elapsed = ContinuousClock.now - started
        renderer.discard()

        #expect(elapsed < .seconds(2))
    }

    // MARK: - The face (docs/10 §4)

    /// The display face is available before a card is drawn. In the app it comes from
    /// `UIAppFonts`; the point of asking is that a `false` here means every numeral on every
    /// shared card is SF Pro, silently.
    @Test func theDisplayFaceIsRegisteredBeforeRendering() {
        #expect(Typography.registerDisplayFace())
        #expect(Typography.isDisplayFaceAvailable)
    }

    // MARK: - The entry point (docs/10 §5)

    /// **"The share entry point does not exist in any other phase."**
    ///
    /// A source scan rather than a UI test, for the same reason `PaletteContrastTests` scans the
    /// tree: the rule is about where the code is allowed to be, and the failure it guards
    /// against is somebody adding a share button to the sealed screen because it would be nice
    /// there. `Features/Results/` is `scored`-only by construction — a `ResultsStore` only ever
    /// exists because the server already said `scored`, and `ResultsStore` (inside
    /// `Features/Results/`) is now the **only** place a `ShareEntry` is built: `RoundScreen` and
    /// `RecordScreen` both just ask a `ResultsStore` for one rather than building their own, so
    /// neither needs to reach these types directly any more.
    @Test func nothingOutsideResultsCanRenderAShareCard() throws {
        let features = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Unit
            .deletingLastPathComponent()   // BlindDropTests
            .deletingLastPathComponent()   // ios
            .appending(path: "BlindDrop/Features")

        let offenders = try swiftFiles(in: features).filter { url in
            guard !url.path.contains("/Features/Results/") else { return false }
            guard let source = try? String(contentsOf: url, encoding: .utf8) else { return false }
            return source.contains("ShareCardView")
                || source.contains("ShareRenderer(")
                || source.contains("ShareSheet(")
        }

        #expect(offenders.isEmpty,
                "only Features/Results/ may reach the share card, and only under .scored")
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
        let enumerator = FileManager.default.enumerator(atPath: directory.path)
        return (enumerator?.allObjects as? [String] ?? [])
            .filter { $0.hasSuffix(".swift") }
            .map { directory.appending(path: $0) }
    }
}

// MARK: - Fixtures

/// A loader that answers instantly from memory and remembers the order it was used in.
///
/// The order is the point: `loadedBeforeFirstCacheRead` is how *"all artwork fully loaded
/// **before** rendering"* becomes a thing a test can see, since the render itself only ever
/// reads the synchronous cache.
final class CountingArtworkLoader: ArtworkLoading, @unchecked Sendable {
    private(set) var requested: Set<URL> = []
    private(set) var loadedBeforeFirstCacheRead = true

    private let image: UIImage
    private let delay: Duration?
    private let succeeds: Bool
    private var outstanding = 0
    private let lock = NSLock()

    init(delay: Duration? = nil, succeeds: Bool = true) {
        self.delay = delay
        self.succeeds = succeeds
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        image = renderer.image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    func cachedImage(for url: URL) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        // A cache read while an async load is still in flight means the card is being drawn on
        // top of a fetch that has not landed — exactly the failure `docs/10` §4 is about.
        if outstanding > 0 { loadedBeforeFirstCacheRead = false }
        return succeeds ? image : nil
    }

    func image(for url: URL) async -> UIImage? {
        begin(url)
        defer { end() }
        if let delay { try? await Task.sleep(for: delay) }
        return succeeds ? image : nil
    }

    // The two halves of `image(for:)`'s bookkeeping, out of the async function: `NSLock.lock()`
    // is unavailable from an async context — holding a lock across a suspension is how a
    // deadlock is written — and these two never suspend.
    private func begin(_ url: URL) {
        lock.lock(); defer { lock.unlock() }
        requested.insert(url)
        outstanding += 1
    }

    private func end() {
        lock.lock(); defer { lock.unlock() }
        outstanding -= 1
    }
}

@MainActor
enum ShareFixture {
    static let tonight = ShareCardContent(
        results: results,
        groupName: "The Cove",
        date: "10 August"
    )

    /// Every artwork the card's four rows point at, at the size and scale the renderer asks
    /// for. A set, because two of the §4.4 rows are the same song.
    static let artworkURLs: Set<URL> = Set(
        tonight.rows.compactMap { card in
            ArtworkView.resolvedURL(
                template: card.track.artworkURL,
                points: ShareCard.artwork,
                scale: ShareCard.scale
            )
        }
    )

    static let results: ResultsDTO = {
        // A payload that will not decode is a broken repository; one loud failure reads better
        // than six tests failing for a reason none of them names.
        try! JSONDecoder.api.decode(ResultsDTO.self, from: try! RoundFixture.payload("results"))
    }()
}
