import Foundation

/// The circle's own screen: its roster, and — for its admin — the two things about it that can
/// change (`E21-01`, `docs/04` §3).
///
/// `rename` and `setRevealHour` both go through `PATCH /groups/{group_id}`, admin-enforced
/// **server-side** (`NOT_ADMIN`) — a member never sees these controls, but the enforcement does
/// not depend on that; a stale or tampered client gets the same refusal the server would give
/// anyone. `leave` goes through `POST /groups/{group_id}/leave`, and refreshes `CircleStore` on
/// success so the switcher and every other group-scoped store stop offering the circle just left.
@Observable @MainActor
final class GroupStore {
    private(set) var state: LoadState<GroupDTO> = .idle

    /// In flight, one at a time — `rename`, `setRevealHour` and `leave` never overlap because
    /// the screen that drives them shows exactly one busy row at once.
    private(set) var isSaving = false
    private(set) var isLeaving = false
    /// The `docs/11` key of the last failure from any of the three mutations, cleared at the
    /// start of the next attempt.
    private(set) var errorKey: String?
    /// Set after a successful `setRevealHour`, so the screen can state precisely when the new
    /// hour takes effect (`docs/03` §4) rather than leaving the question open until tonight.
    private(set) var revealHourEffectiveFrom: String?

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

    /// Admin only, server-enforced. Trimmed the same way `PATCH /groups/{id}` trims it; an
    /// all-whitespace name never leaves this method, matching `INVALID_INPUT`'s own rule so a
    /// member never sees the server reject a name the client just accepted.
    func rename(to name: String) async -> Bool {
        guard let groupID = group?.id else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !isSaving else { return false }
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

    /// Admin only, server-enforced. `docs/03` §4: a changed hour never re-times a round already
    /// on the books, so the response's `effective_from` is the honest answer to "when" and this
    /// method keeps it for the screen to state.
    func setRevealHour(_ hour: Int) async -> Bool {
        guard let groupID = group?.id else { return false }
        guard !isSaving else { return false }
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

    /// Everyone. `POST /groups/{id}/leave` is a 204; on success this refreshes `CircleStore` so
    /// the caller's own roster of circles stops naming the one just left before the screen
    /// navigates away — a stale switcher row for a circle you just left is the same class of
    /// bug `RoundStore.invalidate()` exists to close for a switch (`E19-02`).
    ///
    /// The last-admin case (`docs/04` §3, `tasks/E21-circle-settings.md`'s open question) comes
    /// back as `LAST_ADMIN_MUST_TRANSFER` — today unreachable from this app's own UI (there is no
    /// promote or remove yet, `E21-02`), but the server enforces it regardless of what any client
    /// does, so this path exists and is plain about it rather than silently succeeding client-side.
    func leave() async -> Bool {
        guard let groupID = group?.id else { return false }
        guard !isLeaving else { return false }
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
