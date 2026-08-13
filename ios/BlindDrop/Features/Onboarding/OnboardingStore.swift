import Foundation

/// Steps 1.2 through 1.5 of `docs/08` §1, as one machine.
///
/// One store for the whole flow rather than one per screen, because the flow is one decision
/// with three screens in it: which step you are on is a function of what the **server** last
/// said about you, plus one local fact — whether you have seen the invite code yet.
///
/// That local fact is the only reason this type exists rather than the screens routing off
/// `SessionState` directly. Creating a group makes the caller a member of it, so the honest
/// answer to `GET /me` becomes `has_group: true` the moment `POST /groups` returns — and
/// routing on that would take the creator **past** the invite code screen to today's round,
/// with the code they need to invite anybody nowhere on screen. So the session is not re-read
/// until the creator taps through (`finish()`), which is `docs/08` §1.4 → §1.5 in the order the
/// spec writes it.
///
/// The joiner has no such step and gets none invented for them: `docs/08` §1.5 is *"straight
/// onto today's round. No confirmation, no welcome."*
@Observable @MainActor
final class OnboardingStore {

    /// Which group screen is up. The **name** step is not in here: it is `SessionState`'s
    /// `.noProfile`, which is a thing the server said, and duplicating it locally would be a
    /// second opinion about identity (`docs/13` §4).
    enum GroupStep: Equatable, Sendable {
        /// 1.3 — join first, most users arrive via a link.
        case joinOrCreate
        /// 1.4 — the create form.
        case create
        /// 1.4's second half — the code, the share sheet, and the way out.
        case invite(GroupDTO)
    }

    private(set) var step: GroupStep = .joinOrCreate

    // MARK: - 1.2, the name

    /// The field's contents, raw. Cleaned on the way to the server and on the way to validation,
    /// never mutated under the cursor — a field that rewrites what you typed while you type is
    /// unusable, and the cleaning is visible in `cleanedName` instead.
    var name = "" {
        didSet { if name != oldValue { nameFailure = nil } }
    }

    /// The name as it will be stored (`docs/14` §7). What the help line's promise is measured
    /// against: this is what people will be guessing with.
    var cleanedName: String { DisplayName.clean(name) }

    /// Whether **Continue** is live. `docs/08` §1.2: disabled until valid.
    var canContinue: Bool { DisplayName.problem(with: name) == nil && !isSaving }

    /// The line under the field, in `alert` (`docs/08` §1.2 — inline, never a modal).
    ///
    /// Two sources, in order. A length problem is shown as soon as it is true, because it is
    /// the explanation for a button that just went grey; the *empty* problem is deliberately
    /// **not** shown at rest — an error message on a field nobody has typed in yet is nagging,
    /// and the disabled button already says it. A server refusal outranks both: it is the more
    /// recent fact.
    var nameError: String? {
        if let nameFailure { return nameFailure }
        return DisplayName.problem(with: name) == .tooLong
            ? DisplayName.Problem.tooLong.copyKey
            : nil
    }

    private(set) var isSaving = false
    private var nameFailure: String?

    // MARK: - 1.3, joining

    /// The code field. Normalised on every keystroke, so the field always holds something a
    /// code could be (`docs/14` §7).
    var code = "" {
        didSet {
            let normalised = InviteCode.normalise(code)
            if normalised != code { code = normalised }
            if code != oldValue { joinFailure = nil }
        }
    }

    var canJoin: Bool { InviteCode.isComplete(code) && !isJoining }

    /// `NOT_FOUND` renders `onboarding.group.code.error` — a code that does not exist is not a
    /// generic failure, and *"That doesn't exist"* would leave the user wondering what did not.
    private(set) var joinFailure: String?
    private(set) var isJoining = false

    // MARK: - 1.4, creating

    var groupName = "" {
        didSet { if groupName != oldValue { createFailure = nil } }
    }

    /// Defaulting to the device's timezone (`docs/08` §1.4). It is a default and not a
    /// decision: the group plays on **its** clock forever after, so the picker is right there.
    var timezone: String = TimeZone.current.identifier

    var revealHour: Int = RevealHour.default

    /// Trimmed, because a group called `"  "` is not a group. Length is the server's business
    /// beyond that; this is only what makes **Create group** live.
    var canCreate: Bool {
        !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isCreating
    }

    private(set) var createFailure: String?
    private(set) var isCreating = false

    // MARK: - Wiring

    private let api: APIClient
    private let session: SessionStore

    init(api: APIClient, session: SessionStore) {
        self.api = api
        self.session = session
    }

    /// A code from a `blinddrop://join/<CODE>` or `https://blinddrop.app/j/<CODE>` link
    /// (`docs/05` §5). Prefills the field and nothing else — **the link does not join.** It is a
    /// navigation hint, not an authorization, and a link that joined on open would let a
    /// forwarded message put somebody in a group they never chose.
    ///
    /// Refuses to overwrite a code the user is already typing, so a link arriving mid-entry
    /// does not eat their work.
    func prefill(code prefilled: String) {
        guard code.isEmpty else { return }
        code = prefilled
        step = .joinOrCreate
    }

    // MARK: - 1.2 → 1.3

    /// `PUT /me`, then re-read the session so the **server** decides what comes next
    /// (`docs/13` §4). A client that routed itself to 1.3 would be guessing that the profile
    /// saved.
    func saveName() async {
        guard canContinue else { return }
        isSaving = true
        nameFailure = nil
        defer { isSaving = false }

        do {
            _ = try await api.send(.setDisplayName(cleanedName))
            await session.loadIdentity()
        } catch let error {
            // The server cleans and length-checks the same string this client just cleaned, so
            // an `INVALID_INPUT` here means the two disagree — which is a bug worth showing the
            // user the specific line for rather than a shrug.
            nameFailure = error == .invalidInput(field: "display_name")
                ? DisplayName.Problem.empty.copyKey
                : error.copyKey
        }
    }

    // MARK: - 1.3 → 1.5

    /// `POST /groups/join`. On success the session is re-read and the caller lands **straight**
    /// on today's round (`docs/08` §1.5).
    ///
    /// Not retried, ever, and that is `Endpoint.joinGroup`'s policy rather than this method's:
    /// joining is rate-limited at ten an hour because it is the invite-code brute-force surface
    /// (`docs/04` §8), and an automatic second attempt spends somebody's quota for them.
    func join() async {
        guard canJoin else { return }
        isJoining = true
        joinFailure = nil
        defer { isJoining = false }

        do {
            _ = try await api.send(.joinGroup(inviteCode: code))
            await session.loadIdentity()
        } catch APIError.notFound {
            joinFailure = "onboarding.group.code.error"
        } catch APIError.alreadyInGroup {
            // ADR-005 — one group per user. The user cannot act on being told this: they are in
            // a group, which is where they were trying to get. Re-read the session and let them
            // through (`docs/04` §3).
            await session.loadIdentity()
        } catch let error {
            joinFailure = error.copyKey
        }
    }

    // MARK: - 1.3 → 1.4

    func startCreating() {
        createFailure = nil
        step = .create
    }

    func cancelCreating() {
        createFailure = nil
        step = .joinOrCreate
    }

    /// `POST /groups`. On success the invite code, **not** the round — see the type's note on
    /// why the session is deliberately not re-read here.
    func create() async {
        guard canCreate else { return }
        isCreating = true
        createFailure = nil
        defer { isCreating = false }

        do {
            let group = try await api.send(.createGroup(
                name: groupName.trimmingCharacters(in: .whitespacesAndNewlines),
                timezone: timezone,
                revealHour: revealHour
            ))
            step = .invite(group)
        } catch APIError.alreadyInGroup {
            await session.loadIdentity()
        } catch let error {
            createFailure = error.copyKey
        }
    }

    // MARK: - 1.4 → 1.5

    /// **Go to today's round.** The one place the creator's session is re-read, which is what
    /// makes the invite screen a step rather than a flicker.
    func finish() async {
        await session.loadIdentity()
    }
}
