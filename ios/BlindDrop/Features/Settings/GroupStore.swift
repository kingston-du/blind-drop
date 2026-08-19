import Foundation

/// The read-only active roster, for whichever circle `CircleStore` currently resolves as
/// active. `GET /groups/{group_id}` already shapes members to exactly `user_id` and
/// `display_name`, alphabetically with id as the duplicate-name tie-breaker.
@Observable @MainActor
final class GroupStore {
    private(set) var state: LoadState<GroupDTO> = .idle

    private let api: APIClient
    private let circles: CircleStore

    init(api: APIClient, circles: CircleStore) {
        self.api = api
        self.circles = circles
    }

    var group: GroupDTO? { state.value }
    var members: [MemberDTO] { group?.members ?? [] }

    func load() async {
        guard !state.isLoading else { return }
        state = .loading
        guard let groupID = await circles.resolveActiveID() else {
            state = .failed(circles.state.error ?? .unreadable)
            return
        }
        do {
            state = .loaded(try await api.send(.group(groupID)))
        } catch {
            state = .failed(error)
        }
    }
}
