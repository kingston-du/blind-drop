import Foundation

/// Search, link resolution, and the seal (`docs/08` §3, `docs/04` §4 and §6).
///
/// One store for the sheet, because the sheet is one flow: a query becomes results, a result
/// becomes a chosen track, and the chosen track becomes a sealed submission. Splitting it per
/// screen would put the chosen track in two places and make "did the seal succeed" a question
/// two objects could answer differently.
///
/// **The link path (`pasted`, `resolve()`) has no screen behind it.** The paste-a-link box was
/// removed from both hosts (`docs/08` §2); `POST /tracks/resolve` and `SongLink` are kept, and
/// kept tested, because the parsing is correct and the route is real — but nothing in the app
/// currently calls `resolve()`. Treat it as a route with no door, not as live behaviour.
///
/// **Nothing here runs the animation.** `docs/08` §3.2: the seal is *"a confirmation of a fact,
/// and it must never have lied"* — so `seal(_:)` returns whether the server said yes, and the
/// screen animates only on `true`.
@Observable @MainActor
final class SubmitStore {

    // MARK: - Searching

    /// The field's contents. Every change re-arms the debounce.
    var query = "" {
        didSet { if query != oldValue { scheduleSearch() } }
    }

    /// The results, or the reason there are none.
    ///
    /// `.idle` is the **empty query** and it is a real state, not a missing one: `docs/08` §3.1
    /// says an empty query shows *"a blank sheet with the field focused. This app does not have
    /// opinions about what you should drop."* No suggestions, no trending, no recents.
    private(set) var results: LoadState<[TrackDTO]> = .idle

    /// Whether anything has come back to look at. `.idle` and an empty result set are the same
    /// screen: a field, and room under it. `SongSearch` reads this and hands the answer down to
    /// its `header` closure (`E26-03`), so a host with something to give up while browsing —
    /// `SubmitScreen`'s subhead — does not need its own copy of the same check.
    var isBrowsingResults: Bool {
        !(results.value ?? []).isEmpty
    }

    /// The copy key for a failed search (`docs/11` — `search.error`, `search.error.offline`), or
    /// `nil`. Distinct from `results.error` because the two failures read differently: offline is
    /// *"nothing can be dropped right now"*, and an upstream outage is *"try again in a moment"*.
    var searchErrorKey: String? {
        switch results.error {
        case nil: nil
        case .offline: "search.error.offline"
        default: "search.error"
        }
    }

    /// The one search task, cancelled and replaced on every keystroke (`docs/13` §6 — never a
    /// detached task, never a timer that outlives the screen).
    private var searchTask: Task<Void, Never>?

    /// The deliberate client-side wait, exposed to the UI-test accessibility tree. AC-10 stubs
    /// server waits; staging request p95 belongs to E14-03. Keeping this value derived from the
    /// production token means the UI test catches a debounce drift without measuring XCTest host
    /// contention as if it were product latency.
    var debugSearchDelayMilliseconds: Int? {
        #if DEBUG
        let parts = Self.debounce.components
        return Int(parts.seconds * 1_000)
            + Int(parts.attoseconds / 1_000_000_000_000_000)
        #else
        return nil
        #endif
    }

    /// `docs/08` §3.1: debounce 250ms, minimum two characters. The debounce is the reason
    /// `GET /tracks/search` stays inside AC-10's 400ms budget — the server caches on
    /// `(storefront, query)` for ten minutes (`docs/06` §4) and a per-keystroke request would miss
    /// that cache on every prefix.
    static let debounce = Duration.milliseconds(250)
    static let minimumQueryLength = 2

    private func scheduleSearch() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count >= Self.minimumQueryLength else {
            // Back to the blank sheet, including after a delete: leaving the last results up under
            // an emptied field would be the app having an opinion about a query nobody made.
            results = .idle
            return
        }

        searchTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled, let self else { return }
            await self.search(trimmed)
        }
    }

    private func search(_ term: String) async {
        do {
            let found = try await api.send(.search(term))
            guard !Task.isCancelled else { return }
            results = .loaded(found.results)
        } catch let error {
            guard !Task.isCancelled else { return }
            results = .failed(error)
        }
    }

    // MARK: - Pasting

    /// A song link, on its way to `resolve()`. **No screen writes this any more** — see the
    /// note on the type. It is the input the route takes, kept alongside it.
    var pasted = "" {
        didSet { if pasted != oldValue { pasteErrorKey = nil } }
    }

    private(set) var pasteErrorKey: String?
    private(set) var isResolving = false

    /// `POST /tracks/resolve`.
    ///
    /// A string that is not a song link is refused **here**, without a request: the server answers
    /// an unparseable link and an unfindable song with the same `INVALID_INPUT`, and the copy deck
    /// gives them different words. `SongLink` is the parser that tells them apart.
    func resolve() async -> TrackDTO? {
        guard let link = SongLink(pasted) else {
            pasteErrorKey = "resolve.error.badlink"
            return nil
        }
        isResolving = true
        pasteErrorKey = nil
        defer { isResolving = false }

        do {
            return try await api.send(.resolve(link.input))
        } catch APIError.invalidInput {
            // Parseable, and the catalog does not have it. *"That song isn't in the Apple catalog.
            // Search for it instead."*
            pasteErrorKey = "resolve.error.notfound"
        } catch let error {
            pasteErrorKey = error == .offline ? "search.error.offline" : error.copyKey
        }
        return nil
    }

    // MARK: - Sealing

    private(set) var isSealing = false
    /// The `alert`-coloured line under the button (`docs/08` §3.2). Cleared on every new attempt.
    private(set) var sealErrorKey: String?

    /// `PUT /rounds/{group_id}/current/submission`, and nothing else.
    ///
    /// - Returns: the submission the server sealed, or `nil` if it refused. The caller runs the
    ///   animation only on a non-`nil` result — *"the seal animation never runs speculatively"*
    ///   (`docs/08` §3.2). Sealing offline **fails honestly**; it is never queued (`docs/13` §7).
    func seal(_ track: TrackDTO) async -> SubmissionDTO? {
        guard !isSealing else { return nil }
        isSealing = true
        sealErrorKey = nil
        defer { isSealing = false }

        guard let groupID = await circles.resolveActiveID() else {
            sealErrorKey = "search.error.offline"
            return nil
        }

        do {
            // `apple_music_id` rather than the track key: the id is what `docs/04` §4 takes, and
            // the server re-resolves it so the sealed snapshot is the server's, not the client's.
            return try await api.send(.seal(groupID, .appleMusicID(track.appleMusicID)))
        } catch APIError.offline {
            sealErrorKey = "search.error.offline"
        } catch let error {
            // *"That didn't seal. Try again."* — one line, in `alert`, and nothing is sealed. A
            // phase error gets its own words, because trying again will not help at 20:01.
            sealErrorKey = error == .wrongPhase(state: .revealed) ? error.copyKey : "confirm.error"
        }
        return nil
    }

    // MARK: - Wiring

    private let api: APIClient
    private let circles: CircleStore

    /// - Parameter previewResults: seeds `results` as already `.loaded`, for a snapshot or a
    ///   preview that needs the browsing layout without a live search running through
    ///   `ImageRenderer`, which never fires the task the debounce would otherwise start.
    init(api: APIClient, circles: CircleStore, previewResults: [TrackDTO]? = nil) {
        self.api = api
        self.circles = circles
        if let previewResults { results = .loaded(previewResults) }
    }

    /// Drops the in-flight search. Called when the sheet closes — a request whose screen has gone
    /// away has nothing to render into.
    func cancel() {
        searchTask?.cancel()
        searchTask = nil
    }
}
