import Foundation

/// The caller's own circles, and which one every other store resolves as "the active one"
/// (`docs/01` ADR-011, `E19-01`).
///
/// This is the type `E18`'s `/groups/current` compatibility route existed to buy time for: every
/// group-scoped store used to assume there was exactly one circle, and now asks this one instead.
/// Nothing here is a switcher — there is no UI, and `activeGroupID` picks the same circle
/// `/groups/current` used to resolve — but every store built against this type rather than a
/// hardcoded default is a store `E19-02` can re-scope by calling `select(_:)` without touching
/// its load path at all.
@Observable @MainActor
final class CircleStore {

    private(set) var state: LoadState<[CircleSummaryDTO]> = .idle

    private let api: APIClient
    private let flags: LocalFlags
    /// Set by `AppEnvironment`, `weak` for the same reason `SessionStore`'s reciprocal reference
    /// to this type is: neither is the composition root. Used for exactly one thing — see
    /// `load()`'s empty-list branch.
    private weak var session: SessionStore?
    /// The one fetch in flight, if any — the same de-duplication `SessionStore.refreshCredentials`
    /// uses, so three stores resolving their group id on the same launch produce one request.
    private var loadTask: Task<Void, Never>?

    init(api: APIClient, flags: LocalFlags) {
        self.api = api
        self.flags = flags
    }

    func attach(_ session: SessionStore) {
        self.session = session
    }

    var circles: [CircleSummaryDTO] { state.value ?? [] }

    /// The circle every store defaults to: the persisted choice, if it still names one of the
    /// caller's circles, else the server's own oldest-active-first ordering — precisely what
    /// `/groups/current` used to resolve, which is what makes "nothing changes" true for a user
    /// who has never switched.
    var activeGroupID: String? {
        if let saved = flags.activeCircleID, circles.contains(where: { $0.id == saved }) {
            return saved
        }
        return circles.first?.id
    }

    /// Fetches `GET /groups`. A refresh failure keeps the list already on screen
    /// (`LoadState.apply` → `.stale`) — the same reasoning every other store applies, here
    /// because a circle that briefly failed to refresh must not make every store that resolves
    /// against it fail too.
    ///
    /// **An empty list is `docs/04` §3's `NO_GROUP`, restated.** `/rounds/current` used to 409
    /// `NO_GROUP` for a caller with no active circle, and `APIClient` fed every failure to
    /// `SessionStore.noteServerSaid(_:)`, which is what routed a person removed from their only
    /// circle back to onboarding (`docs/04` §2). `GET /groups` answers the same fact with a 200
    /// and `{"circles": []}` — a valid response, not an error — so nothing would ever reach
    /// `noteServerSaid` through this route without this telling it explicitly.
    func load() async {
        if let loadTask { return await loadTask.value }
        if state.value == nil { state = .loading }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await self.api.send(Endpoint<CirclesDTO>.circles)
                self.state.apply(.success(result.circles))
                if result.circles.isEmpty {
                    self.session?.noteServerSaid(.noGroup)
                }
            } catch let error as APIError {
                self.state.apply(.failure(error))
            } catch {
                self.state.apply(.failure(.unreadable))
            }
        }
        loadTask = task
        await task.value
        loadTask = nil
    }

    /// The one thing a group-scoped store's `load()` calls: ensure the list has been fetched at
    /// least once, then hand back the active id. A failed fetch is not reported here — it
    /// surfaces through the caller's own `LoadState` exactly as `/groups/current` failing always
    /// did, so a group-scoped store gains no second error path by depending on this one.
    func resolveActiveID() async -> String? {
        if state.value == nil { await load() }
        return activeGroupID
    }

    /// Persists a switch. Reached by `E19-02`; this slice only wires the write side, since
    /// there is no UI yet to call it from.
    func select(_ id: String) {
        flags.activeCircleID = id
    }

    /// Called by `SessionStore.endSession()`. A cached circle list belongs to whoever was signed
    /// in when it was fetched — `AppEnvironment` is the app's one long-lived composition root
    /// (`docs/13` §2), so without this a sign-out followed by a different sign-in would show the
    /// first user's circles until something happened to trigger a refetch.
    func reset() {
        loadTask?.cancel()
        loadTask = nil
        state = .idle
    }
}
