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
        // `E28-06`: refresh in place rather than clearing an already-loaded profile back to
        // `.loading` — the same fix `GroupStore` makes, for the same reason: a return trip to a
        // profile screen the caller was just on should not draw its skeleton again.
        if state.value == nil { state = .loading }
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
