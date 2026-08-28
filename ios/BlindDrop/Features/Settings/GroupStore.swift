import Foundation

/// The active circle's settings and standings. The two reads are deliberately independent: a
/// standings failure must never hide the circle a person is trying to manage.
@Observable @MainActor
final class GroupStore {
    private(set) var state: LoadState<GroupDTO> = .idle
    private(set) var standings: LoadState<StandingsDTO> = .idle
    private(set) var isSaving = false
    private(set) var isLeaving = false
    private(set) var isManagingMember = false
    private(set) var errorKey: String?
    private(set) var revealHourEffectiveFrom: String?
    private(set) var cueEffectiveFrom: String?

    /// Four or fewer completed rounds used to be shown without percentages or rank.
    // Restore before public beta (`E28-06`, amendment A1): the test stage wants every number a
    // tester can see, however little history is behind it, so `isThinHistory` below is pinned to
    // `false` rather than reading this. Left in place — not deleted — so restoring the gate is a
    // one-line revert instead of relearning what the number was.
    static let thinHistoryThreshold = 5

    private let api: APIClient
    private let circles: CircleStore

    init(api: APIClient, circles: CircleStore) {
        self.api = api
        self.circles = circles
    }

    var group: GroupDTO? { state.value }
    var members: [MemberDTO] { group?.members ?? [] }
    // Restore before public beta: `standings.value.map { $0.roundsPlayed < Self.thinHistoryThreshold } ?? false`.
    var isThinHistory: Bool { false }
    /// The circle's own scored-round count (`E28-08`'s `SheetMeta` line) — `nil` while standings
    /// have not loaded, same as every other standings-derived value here.
    var roundsPlayed: Int? { standings.value?.roundsPlayed }
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
        // `E28-06`: refresh in place. This used to clear to `.loading` unconditionally, which is
        // why leaving a member's profile and returning to Group showed the skeleton every time —
        // `GroupScreen` had a group to draw and drew nothing instead while a refetch it did not
        // need to wait on was in flight. `standings` already only did this on a genuinely first
        // load; `state` now matches it. A failed refresh still lands in `LoadState.stale`, which
        // is what keeps the old value on screen if the network says no.
        if state.value == nil { state = .loading }
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

    func setCueCadence(_ cadence: Int) async -> Bool {
        guard let groupID = group?.id, !isSaving else { return false }
        isSaving = true
        errorKey = nil
        defer { isSaving = false }
        do {
            let patch = try await api.send(
                .updateGroup(groupID, name: nil, revealHour: nil, cueCadence: cadence)
            )
            state = .loaded(patch.group)
            cueEffectiveFrom = patch.group.cueEffectiveFrom
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

    func setRole(_ role: String, for userID: String) async -> Bool {
        guard let groupID = group?.id, !isManagingMember else { return false }
        isManagingMember = true
        errorKey = nil
        defer { isManagingMember = false }
        do {
            state = .loaded(try await api.send(.updateMemberRole(userID, in: groupID, role: role)))
            return true
        } catch {
            errorKey = error.copyKey
            return false
        }
    }

    func remove(_ userID: String) async -> Bool {
        guard let groupID = group?.id, !isManagingMember else { return false }
        isManagingMember = true
        errorKey = nil
        defer { isManagingMember = false }
        do {
            _ = try await api.send(.removeMember(userID, from: groupID))
            // A removal returns 204 so its own historical data cannot accidentally become a
            // roster payload. Reload the two independent group-screen reads instead.
            await load()
            return state.value != nil
        } catch {
            errorKey = error.copyKey
            return false
        }
    }
}
