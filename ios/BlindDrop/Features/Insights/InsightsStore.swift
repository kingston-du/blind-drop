import Foundation

/// The active circle's scored relationships. The server owns the aggregation and all phase
/// filtering; this store only resolves the selected circle and coordinates loading and retrying.
@Observable @MainActor
final class InsightsStore {
    private(set) var state: LoadState<InsightsDTO> = .idle

    private let api: APIClient
    private let circles: CircleStore

    init(api: APIClient, circles: CircleStore) {
        self.api = api
        self.circles = circles
    }

    func load() async {
        guard !state.isLoading else { return }
        state = .loading
        guard let groupID = await circles.resolveActiveID() else {
            state = .failed(circles.state.error ?? .unreadable)
            return
        }
        do {
            state = .loaded(try await api.send(.insights(in: groupID)))
        } catch {
            state = .failed(error)
        }
    }
}
