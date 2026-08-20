import Foundation

/// The active circle's settings and standings. The two reads are deliberately independent: a
/// standings failure must never hide the circle a person is trying to manage.
@Observable @MainActor
final class GroupStore {
    private(set) var state: LoadState<GroupDTO> = .idle
    private(set) var standings: LoadState<StandingsDTO> = .idle
    private(set) var isSaving = false
    private(set) var isLeaving = false
    private(set) var errorKey: String?
    private(set) var revealHourEffectiveFrom: String?

    /// Four or fewer completed rounds are shown without percentages or rank.
    static let thinHistoryThreshold = 5

    private let api: APIClient
    private let circles: CircleStore

    init(api: APIClient, circles: CircleStore) {
        self.api = api
        self.circles = circles
    }

    var group: GroupDTO? { state.value }
    var members: [MemberDTO] { group?.members ?? [] }
    var isThinHistory: Bool {
        guard let standings = standings.value else { return false }
        return standings.roundsPlayed < Self.thinHistoryThreshold
    }
    var bestEar: [EarStandingDTO] { standings.value?.bestEar ?? [] }
    var readabilityByUserID: [String: ReadabilityStandingDTO] {
        Dictionary(uniqueKeysWithValues: (standings.value?.readability ?? []).map { ($0.userID, $0) })
    }
    var unrankedMembers: [MemberDTO] {
        guard standings.value != nil, !isThinHistory else { return members }
        let rankedIDs = Set(bestEar.map(\.userID))
        return members.filter { !rankedIDs.contains($0.userID) }
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

    private func result<R: Decodable & Sendable>(of endpoint: Endpoint<R>) async -> Result<R, APIError> {
        do { return .success(try await api.send(endpoint)) }
        catch { return .failure(error) }
    }

    func rename(to name: String) async -> Bool {
        guard let groupID = group?.id else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSaving else { return false }
        isSaving = true
        errorKey = nil
        defer { isSaving = false }
        do {
            let patch = try await api.send(.updateGroup(groupID, name: trimmed, revealHour: nil))
            state = .loaded(patch.group)
            return true
        } catch {
            errorKey = error.copyKey
            return false
        }
    }

    func setRevealHour(_ hour: Int) async -> Bool {
        guard let groupID = group?.id, !isSaving else { return false }
        isSaving = true
        errorKey = nil
        defer { isSaving = false }
        do {
            let patch = try await api.send(.updateGroup(groupID, name: nil, revealHour: hour))
            state = .loaded(patch.group)
            revealHourEffectiveFrom = patch.effectiveFrom
            return true
        } catch {
            errorKey = error.copyKey
            return false
        }
    }

    func leave() async -> Bool {
        guard let groupID = group?.id, !isLeaving else { return false }
        isLeaving = true
        errorKey = nil
        defer { isLeaving = false }
        do {
            _ = try await api.send(.leaveGroup(groupID))
            await circles.load()
            return true
        } catch {
            errorKey = error.copyKey
            return false
        }
    }
}
