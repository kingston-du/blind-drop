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
    private var generation = 0

    init(api: APIClient, spotify: SpotifyExporter, apple: AppleMusicExporter) {
        self.api = api
        self.spotify = spotify
        self.apple = apple
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
        guard state.value == nil else { return }
        state = .loading
        generation += 1
        let requestGeneration = generation

        async let groupResult = result(of: Endpoint<GroupDTO>.currentGroup)
        async let recordResult = result(
            of: Endpoint<RecordDTO>.record(member: selectedMemberID, limit: Self.pageSize)
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
        let loaded = await result(
            of: Endpoint<RecordDTO>.record(member: memberID, limit: Self.pageSize)
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
        let loaded = await result(
            of: Endpoint<RecordDTO>.record(
                member: selectedMemberID,
                cursor: cursor,
                limit: Self.pageSize
            )
        )
        guard generation == requestGeneration else { return }
        defer { isLoadingMore = false }
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
        do {
            let payload = try await api.send(.export(.spotify))
            spotifyExport = .succeeded(try await spotify.export(payload))
        } catch {
            spotifyExport = .failed(.failed)
        }
    }

    func exportToAppleMusic() async {
        guard appleExport != .working else { return }
        appleExport = .working
        do {
            let payload = try await api.send(.export(.apple))
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

    private func applyFirstPage(_ loaded: Result<RecordDTO, APIError>) {
        switch loaded {
        case let .success(page):
            state = .loaded(page.days)
            nextCursor = page.nextCursor
        case let .failure(error):
            state = .failed(error)
            nextCursor = nil
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
