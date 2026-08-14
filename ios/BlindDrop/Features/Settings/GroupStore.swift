import Foundation

/// The read-only active roster. `GET /groups/current` already shapes members to exactly
/// `user_id` and `display_name`, alphabetically with id as the duplicate-name tie-breaker.
@Observable @MainActor
final class GroupStore {
    private(set) var state: LoadState<GroupDTO> = .idle

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    var group: GroupDTO? { state.value }
    var members: [MemberDTO] { group?.members ?? [] }

    func load() async {
        guard !state.isLoading else { return }
        state = .loading
        do {
            state = .loaded(try await api.send(.currentGroup))
        } catch {
            state = .failed(error)
        }
    }
}
