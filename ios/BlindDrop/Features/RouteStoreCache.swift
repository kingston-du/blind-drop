import Foundation

/// The loaded feature stores for this session, keyed by circle so a screen can be pushed, popped,
/// and pushed again without rebuilding the store it was just showing.
///
/// Each screen's store used to be a `@State` on that screen, destroyed when the route is popped;
/// the next push built a fresh store with `state == nil`, so `.task` drew the skeleton and
/// refetched. This cache lives on `AppEnvironment` — the same place `CircleStore` lives — so a
/// store survives navigation, and its "refresh in place" `load()` then re-fetches silently over
/// already-rendered content instead of flashing a skeleton.
///
/// Keying by circle id (and by member id for profiles) means a circle switch naturally gets fresh
/// stores — a different key is a different store — with no explicit invalidation. `reset()` exists
/// for the one case keys cannot see: sign-out, where the *same* circle id must never be served to
/// a different account.
@Observable @MainActor
final class RouteStoreCache {
    private let api: APIClient
    private let circles: CircleStore
    /// Builds a `RecordStore` for a circle. A closure rather than a direct call because the
    /// record store needs the Spotify exporter and the app's Spotify configuration, which belong
    /// to `AppEnvironment`, not to this cache. Main-actor-isolated because it captures
    /// `CircleStore` and constructs a `@MainActor` store.
    private let makeRecordStore: @MainActor () -> RecordStore

    private var groups: [String: GroupStore] = [:]
    private var insights: [String: InsightsStore] = [:]
    private var profiles: [ProfileKey: MemberProfileStore] = [:]
    private var records: [String: RecordStore] = [:]
    private var results: [String: ResultsStore] = [:]

    private struct ProfileKey: Hashable {
        let circleID: String
        let userID: String
    }

    init(
        api: APIClient,
        circles: CircleStore,
        makeRecordStore: @escaping @MainActor () -> RecordStore
    ) {
        self.api = api
        self.circles = circles
        self.makeRecordStore = makeRecordStore
    }

    func groupStore(for circleID: String?) -> GroupStore {
        guard let circleID else { return GroupStore(api: api, circles: circles) }
        if let existing = groups[circleID] { return existing }
        let built = GroupStore(api: api, circles: circles)
        groups[circleID] = built
        return built
    }

    func insightsStore(for circleID: String?) -> InsightsStore {
        guard let circleID else { return InsightsStore(api: api, circles: circles) }
        if let existing = insights[circleID] { return existing }
        let built = InsightsStore(api: api, circles: circles)
        insights[circleID] = built
        return built
    }

    func recordStore(for circleID: String?) -> RecordStore {
        guard let circleID else { return makeRecordStore() }
        if let existing = records[circleID] { return existing }
        let built = makeRecordStore()
        records[circleID] = built
        return built
    }

    /// A past night's results (`E44-03`).
    ///
    /// **Keyed by round id, not circle id**, because a night is the thing being looked at: the
    /// same circle has one of these per evening, and two nights are two stores. It is the only
    /// entry here that is not circle-scoped, which is why it does not take the `nil` fallback the
    /// others do — a round id is never unresolved at the point this is asked for. The screen has
    /// one in its hand; that is how it got there.
    ///
    /// **Built by the caller rather than here.** `ResultsStore` needs the artwork loader, which
    /// is a SwiftUI environment value and belongs to the view reading it, not to this cache — the
    /// same reasoning `makeRecordStore` uses for the Spotify exporter, arranged as a parameter
    /// instead of an init closure because this one varies per call site rather than per app.
    func resultsStore(for roundID: String, build: () -> ResultsStore) -> ResultsStore {
        if let existing = results[roundID] { return existing }
        let built = build()
        results[roundID] = built
        return built
    }

    func profileStore(member: MemberDTO, circleID: String?) -> MemberProfileStore {
        guard let circleID else {
            return MemberProfileStore(member: member, api: api, circles: circles)
        }
        let key = ProfileKey(circleID: circleID, userID: member.userID)
        if let existing = profiles[key] { return existing }
        let built = MemberProfileStore(member: member, api: api, circles: circles)
        profiles[key] = built
        return built
    }

    func reset() {
        groups.removeAll()
        insights.removeAll()
        profiles.removeAll()
        records.removeAll()
        results.removeAll()
    }
}
