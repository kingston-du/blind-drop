import Foundation

struct RecordRowID: Hashable, Sendable {
    let roundID: String
    let userID: String
}

enum RecordExportState: Sendable, Equatable {
    case idle
    case working
    case succeeded(PlaylistExportResult)
    case failed(PlaylistExportError)
}

/// The archive's pages, member filter, and two deliberately independent export paths.
@Observable @MainActor
final class RecordStore {
    static let pageSize = 50
    static let prefetchDistance = 10

    private(set) var state: LoadState<[RecordDayDTO]> = .idle
    private(set) var group: GroupDTO?
    private(set) var selectedMemberID: String?
    private(set) var nextCursor: String?
    private(set) var isLoadingMore = false
    private(set) var spotifyExport: RecordExportState = .idle
    private(set) var appleExport: RecordExportState = .idle

    private let api: APIClient
    private let spotify: SpotifyExporter
    private let apple: AppleMusicExporter
    private let circles: CircleStore
    private var generation = 0

    init(api: APIClient, spotify: SpotifyExporter, apple: AppleMusicExporter, circles: CircleStore) {
        self.api = api
        self.spotify = spotify
        self.apple = apple
        self.circles = circles
    }

    var days: [RecordDayDTO] { state.value ?? [] }
    var members: [MemberDTO] { group?.members ?? [] }
    var selectedMember: MemberDTO? {
        members.first { $0.userID == selectedMemberID }
    }
    var filterName: String {
        selectedMember?.displayName ?? Copy.string("record.filter.all")
    }
    var calendar: GroupCalendar? { group.map { GroupCalendar(timezone: $0.timezone) } }

    func load() async {
        // Refresh in place, the way `GroupStore`, `InsightsStore` and `MemberProfileStore` already
        // do since `E28-06`. This used to be `guard state.value == nil`, which was correct while
        // each screen owned its own store and a pop destroyed it — but `RouteStoreCache` keeps this
        // one alive for the whole session, so that guard froze the archive at whatever it held the
        // first time the Record was opened after launch. A round that scored later in the evening
        // never appeared. The skeleton is drawn only when there is genuinely nothing to draw over;
        // a failed refresh lands in `.stale` and keeps the list.
        //
        // **No `isLoading` guard**, which is `RoundStore.load()`'s shape and for its reason: this
        // screen's `.task(id:)` cancels the call in flight when a foreground bumps its token, and
        // a guard would make the replacement a no-op while the cancelled one was still unresolved
        // — the cold-launch-then-foreground case would end in a full-screen error and no refetch,
        // which is the exact moment this fix exists for. `generation` already discards the older
        // result, so letting both run is the safe half of the trade.
        if state.value == nil { state = .loading }
        generation += 1
        let requestGeneration = generation

        guard let groupID = await circles.resolveActiveID() else {
            guard generation == requestGeneration else { return }
            state = .failed(circles.state.error ?? .unreadable)
            return
        }

        async let groupResult = result(of: Endpoint<GroupDTO>.group(groupID))
        async let recordResult = result(
            of: Endpoint<RecordDTO>.record(groupID, member: selectedMemberID, limit: Self.pageSize)
        )
        let (loadedGroup, loadedRecord) = await (groupResult, recordResult)
        guard generation == requestGeneration else { return }
        if case let .success(value) = loadedGroup { group = value }
        applyFirstPage(loadedRecord)
    }

    func select(memberID: String?) async {
        guard selectedMemberID != memberID else { return }
        generation += 1
        let requestGeneration = generation
        selectedMemberID = memberID
        state = .loading
        nextCursor = nil
        isLoadingMore = false
        guard let groupID = await circles.resolveActiveID() else {
            guard generation == requestGeneration else { return }
            state = .failed(circles.state.error ?? .unreadable)
            return
        }
        let loaded = await result(
            of: Endpoint<RecordDTO>.record(groupID, member: memberID, limit: Self.pageSize)
        )
        guard generation == requestGeneration else { return }
        applyFirstPage(loaded)
    }

    func loadMoreIfNeeded(row: RecordRowID) async {
        guard let cursor = nextCursor, !isLoadingMore else { return }
        let rows = flattenedRowIDs
        guard let index = rows.firstIndex(of: row),
              index >= max(0, rows.count - Self.prefetchDistance)
        else { return }

        isLoadingMore = true
        let requestGeneration = generation
        guard let groupID = await circles.resolveActiveID() else {
            isLoadingMore = false
            return
        }
        let loaded = await result(
            of: Endpoint<RecordDTO>.record(
                groupID,
                member: selectedMemberID,
                cursor: cursor,
                limit: Self.pageSize
            )
        )
        // Cleared before the generation check, not after it. A refresh that lands mid-page bumps
        // `generation`, and returning above the `defer` used to leave `isLoadingMore` stuck true —
        // pagination dead for the rest of the session. Unreachable while `load()` ran once per
        // store; reachable now that every appearance and every foreground refreshes.
        defer { isLoadingMore = false }
        guard generation == requestGeneration else { return }
        switch loaded {
        case let .success(page):
            state = .loaded(Self.merging(days, with: page.days))
            nextCursor = page.nextCursor
        case let .failure(error):
            state = .stale(days, error)
        }
    }

    func exportToSpotify() async {
        guard spotifyExport != .working else { return }
        spotifyExport = .working
        guard let groupID = await circles.resolveActiveID() else {
            spotifyExport = .failed(.failed)
            return
        }
        do {
            let payload = try await api.send(.export(groupID, .spotify))
            spotifyExport = .succeeded(try await spotify.export(payload))
        } catch {
            spotifyExport = .failed(.failed)
        }
    }

    func exportToAppleMusic() async {
        guard appleExport != .working else { return }
        appleExport = .working
        guard let groupID = await circles.resolveActiveID() else {
            appleExport = .failed(.failed)
            return
        }
        do {
            let payload = try await api.send(.export(groupID, .apple))
            appleExport = .succeeded(try await apple.export(payload))
        } catch let exportError as PlaylistExportError {
            appleExport = .failed(exportError)
        } catch {
            appleExport = .failed(.failed)
        }
    }

    private var flattenedRowIDs: [RecordRowID] {
        days.flatMap { day in
            day.entries.map { RecordRowID(roundID: day.roundID, userID: $0.userID) }
        }
    }

    /// A fresh first page, over whatever is already on screen.
    ///
    /// Three callers, one rule. On a first load and on a filter change `state` is `.loading`, so
    /// `days` is empty and the merge is just the page. On a refresh it is not: the page carries the
    /// newest nights — including one that scored since — and anything the reader had already paged
    /// past is kept behind it rather than collapsing the list back to fifty songs under their
    /// scroll. Both lists are date-descending and the page is a prefix of the archive, so the
    /// leftovers are strictly older than it and the order holds.
    ///
    /// `nextCursor` follows the *last day in the merged list*, which is why it is only replaced
    /// when the merge kept nothing deeper. Adopting the page's cursor while deeper days are still
    /// shown would resume pagination above them, and `merging` would dedupe every row of the
    /// result — a page that loads, changes nothing, and stalls the list forever.
    private func applyFirstPage(_ loaded: Result<RecordDTO, APIError>) {
        switch loaded {
        case let .success(page):
            let merged = Self.merging(page.days, with: days)
            state = .loaded(merged)
            if merged.count == page.days.count { nextCursor = page.nextCursor }
        case let .failure(error):
            // `LoadState.apply`'s stale transition: a failed refresh keeps the days already on
            // screen, and their cursor with them, so paging still works over what is visible. A
            // failed first load has nothing to keep and lands in `.failed`.
            state.apply(.failure(error))
            if state.value == nil { nextCursor = nil }
        }
    }

    private func result<R: Decodable & Sendable>(
        of endpoint: Endpoint<R>
    ) async -> Result<R, APIError> {
        do { return .success(try await api.send(endpoint)) }
        catch { return .failure(error) }
    }

    static func merging(_ existing: [RecordDayDTO], with page: [RecordDayDTO]) -> [RecordDayDTO] {
        var seen = Set(existing.map(\.roundID))
        return existing + page.filter { seen.insert($0.roundID).inserted }
    }
}
