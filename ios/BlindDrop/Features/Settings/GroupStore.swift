import Foundation

/// The active roster for whichever circle `CircleStore` currently resolves as active, ranked
/// by all-time Ear (`E24-01`, `docs/02` §4). `GET /groups/{group_id}` shapes members to exactly
/// `user_id` and `display_name`, alphabetically with id as the duplicate-name tie-breaker;
/// `GET /groups/{group_id}/standings` carries the ranking itself, already tie-broken on the
/// server (`docs/02` §4.2) — this store never re-derives a rank, only renders the one it is
/// given.
@Observable @MainActor
final class GroupStore {
    private(set) var state: LoadState<GroupDTO> = .idle

    /// Its own `LoadState`, the same split `ResultsStore` makes between the answers and the
    /// standings: two different routes with different lifetimes, and a standings failure must
    /// not blank the roster underneath it.
    private(set) var standings: LoadState<StandingsDTO> = .idle

    /// Below this many rounds, a ranked percentage is noise wearing a standing's clothes
    /// (`tasks/E24-leaderboard-profiles.md`: *"do not print a confident percentage over four
    /// data points"*). `StandingsDTO` carries no per-member denominator, so this is judged at
    /// the circle level, on `rounds_played`.
    static let thinHistoryThreshold = 4

    private let api: APIClient
    private let circles: CircleStore

    init(api: APIClient, circles: CircleStore) {
        self.api = api
        self.circles = circles
    }

    var group: GroupDTO? { state.value }
    var members: [MemberDTO] { group?.members ?? [] }

    /// `true` once the standings have loaded and the circle has not yet played enough rounds to
    /// rank with a straight face. `false` while standings are still loading or missing — there
    /// is nothing confident *or* unconfident to say yet, so the leaderboard section renders its
    /// own loading state instead.
    var isThinHistory: Bool {
        guard let value = standings.value else { return false }
        return value.roundsPlayed < Self.thinHistoryThreshold
    }

    var bestEar: [EarStandingDTO] { standings.value?.bestEar ?? [] }

    var readabilityByUserID: [String: ReadabilityStandingDTO] {
        Dictionary(uniqueKeysWithValues: (standings.value?.readability ?? []).map { ($0.userID, $0) })
    }

    func load() async {
        guard !state.isLoading else { return }
        state = .loading
        if standings.value == nil { standings = .loading }

        guard let groupID = await circles.resolveActiveID() else {
            let error = circles.state.error ?? .unreadable
            state = .failed(error)
            standings = .failed(error)
            return
        }

        async let groupResult = result(of: .group(groupID))
        async let standingsResult = result(of: Endpoint<StandingsDTO>.standings(groupID))

        state.apply(await groupResult)
        standings.apply(await standingsResult)
    }

    /// `APIClient.send` throws `APIError` and nothing else — a typed `throws`, so there is no
    /// second `catch` here for an error that cannot arrive.
    private func result<R: Decodable & Sendable>(of endpoint: Endpoint<R>) async -> Result<R, APIError> {
        do {
            return .success(try await api.send(endpoint))
        } catch {
            return .failure(error)
        }
    }
}
