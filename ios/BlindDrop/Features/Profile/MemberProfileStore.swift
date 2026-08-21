import Foundation

/// One member's finished history in the active circle. The server owns both the active-circle
/// lookup and the scored-round filter; the store only coordinates loading and retrying.
@Observable @MainActor
final class MemberProfileStore {
    private(set) var state: LoadState<MemberProfileDTO> = .idle

    private let member: MemberDTO
    private let api: APIClient
    private let circles: CircleStore

    init(member: MemberDTO, api: APIClient, circles: CircleStore) {
        self.member = member
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
            state = .loaded(try await api.send(.memberProfile(member.userID, in: groupID)))
        } catch {
            state = .failed(error)
        }
    }
}
