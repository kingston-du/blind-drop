import SwiftUI

/// Joining a circle when you are already in one (`E38-02`).
///
/// The app has had a code field since `E09-03`, and it has always been unreachable to anybody
/// who already had a circle: `JoinOrCreateScreen` lives inside onboarding, behind
/// `session == .noGroup`, and `Router` discarded a `/j/<CODE>` link outright for a `.ready`
/// session on the argument that the server would answer `ALREADY_IN_GROUP`. That argument was
/// sound when a person could hold exactly one circle and has not been since ADR-011 — the code
/// almost certainly names a circle the caller is **not** in, and `POST /groups/join` would have
/// accepted it the whole time. This sheet is the missing door.
///
/// It deliberately does not reuse `OnboardingStore`. That store's job is moving a person with no
/// group through the root routing state — it calls `session.loadIdentity()` on success, which is
/// how a `.noGroup` session becomes `.ready`. Here the session is already `.ready` and the thing
/// that has to change is which circle is active, which is `CircleStore`'s business.
///
/// **It never joins by itself.** A link arriving here prefills the field and stops, for
/// `docs/05` §5's reason: *a deep link is a navigation hint, not an authorization*, and a
/// forwarded message must not put somebody in a circle they did not choose.
@Observable @MainActor
final class JoinCircleStore {
    private let api: APIClient
    private let circles: CircleStore

    /// The field's contents, always in the shape a code can be. **Normalised by the binding
    /// the field is given**, at the call site — not here, and not afterwards.
    ///
    /// This took three tries and the two that failed are worth writing down, because
    /// `OnboardingStore.code` shipped the first of them and nobody noticed.
    ///
    /// 1. **A `didSet` that re-assigns `code`.** Invisible. SwiftUI pushes a model value back
    ///    into `UITextField` only when it sees the value change *after* an edit, and a write
    ///    inside the binding's own setter is part of that same edit. The field cheerfully
    ///    displayed `aaa222o` — lowercase, seven characters, two of them outside `docs/03` §2's
    ///    alphabet — while the store held `AAA222`.
    /// 2. **An `.onChange(of: code)` that assigns a corrected value back.** Visible, and racy:
    ///    every keystroke is an edit, a corrected write and a re-sync, and keystrokes arriving
    ///    during that round trip append to the buffer the correction is about to replace.
    ///    Typing `aaa222o` quickly left `A2`.
    /// 3. **A `Binding` whose setter calls `setCode(_:)`.** One write per edit and no
    ///    correction to race: the field proposes, this stores what a code can be, and the field
    ///    reads that back. `private(set)` is what stops anyone reintroducing the second write by
    ///    binding `$store.code` directly.
    ///
    /// `.textInputAutocapitalization(.characters)` hid (1) for typing and never hid it for
    /// **paste**, which is the case `InviteCode.normalise` exists for — pasting a whole invite
    /// link is how an invite usually arrives.
    private(set) var code: String = "" {
        didSet { if code != oldValue { failure = nil } }
    }

    /// The one way the field's contents change, and the only place normalisation happens.
    func setCode(_ raw: String) {
        code = InviteCode.normalise(raw)
    }

    private(set) var isJoining = false
    private(set) var failure: String?

    init(api: APIClient, circles: CircleStore, code: String = "") {
        self.api = api
        self.circles = circles
        setCode(code)
    }

    var canJoin: Bool { InviteCode.isComplete(code) && !isJoining }

    /// `POST /groups/join`, then the circle list, then the id of the circle to switch to.
    ///
    /// Not retried, ever — `Endpoint.joinGroup`'s own policy: joining is rate-limited at ten an
    /// hour because it is the invite-code brute-force surface (`docs/04` §8), and an automatic
    /// second attempt spends somebody's quota for them.
    ///
    /// Every failure is answered in words rather than as a generic one. `ALREADY_IN_GROUP` in
    /// particular is not an error the caller can do anything about and is not a dead end: it
    /// means the code named a circle they already hold, so it is stated plainly and the sheet
    /// stays open with the code still there to correct.
    func join() async -> String? {
        guard canJoin else { return nil }
        isJoining = true
        failure = nil
        defer { isJoining = false }

        do {
            let group = try await api.send(.joinGroup(inviteCode: code))
            await circles.load()
            return group.id
        } catch APIError.notFound {
            failure = "onboarding.group.code.error"
        } catch let error as APIError {
            failure = error.copyKey
        } catch {
            failure = APIError.unreadable.copyKey
        }
        return nil
    }
}

struct JoinCircleSheet: View {
    /// Prefilled by a `/j/<CODE>` link. Empty when the sheet was opened by hand from the
    /// switcher, which is the commoner case: a code arrives in a message far more often than as
    /// a link somebody remembers to tap.
    let prefilledCode: String
    /// The circle just joined. The caller switches to it exactly as it switches to a picked
    /// switcher row, so there is one path into "the active circle changed" and not two.
    let joined: (String) -> Void
    let close: () -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var store: JoinCircleStore?
    @FocusState private var isCodeFocused: Bool
    /// Where VoiceOver lands when the field arrives already filled (`docs/05` §5 — *"prefills
    /// the join field and focuses the button"*).
    @AccessibilityFocusState private var isJoinFocused: Bool

    init(
        prefilledCode: String = "",
        joined: @escaping (String) -> Void,
        close: @escaping () -> Void
    ) {
        self.prefilledCode = prefilledCode
        self.joined = joined
        self.close = close
    }

    var body: some View {
        Group {
            if let store {
                content(store)
            } else {
                // One runloop, before `.task` has built the store. Nothing to draw yet, and a
                // spinner for a frame is worse than a frame of paper.
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.paper)
        .presentationBackground(Palette.paper)
        .presentationDetents([.medium])
        .presentationCornerRadius(Radius.sheet)
        .presentationDragIndicator(.visible)
        .task {
            store = store ?? JoinCircleStore(api: env.api, circles: env.circles, code: prefilledCode)
            takeFocus()
        }
        // The way down, which this sheet never had: a drag has no other hook, and without it the
        // keyboard was left standing over the round screen behind. See `resigningFocus(_:)`.
        .resigningFocus($isCodeFocused)
    }

    private func content(_ store: JoinCircleStore) -> some View {
        VStack(alignment: .leading, spacing: Layout.blockGap) {
            HStack(spacing: Space.sm) {
                Text("join.title")
                    .typeStyle(.displayM)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.sm)
                CloseButton(action: dismiss)
            }

            VStack(alignment: .leading, spacing: Space.sm) {
                SectionLabel("onboarding.group.code.label")
                InsetField(
                    "onboarding.group.code.placeholder",
                    text: Binding(get: { store.code }, set: { store.setCode($0) }),
                    style: .monoM,
                    alignment: .leading,
                    isFocused: isCodeFocused
                )
                .focused($isCodeFocused)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textContentType(.oneTimeCode)
                .submitLabel(.join)
                .onSubmit { attempt(store) }
                .accessibilityLabel(Text("onboarding.group.code.placeholder"))
                // The code alphabet has no lowercase and no `I`, `L`, `O`, `0` or `1`
                // (`docs/03` §2), so a spelled-out value is the only one a person can check
                // against the message they were sent.
                .accessibilityValue(Text(verbatim: JoinOrCreateScreen.spelled(store.code)))
                // A complete code needs no more keyboard.
                .onChange(of: store.code) { _, code in
                    if InviteCode.isComplete(code) { isCodeFocused = false }
                }

                if let failure = store.failure {
                    Text(LocalizedStringKey(failure))
                        .typeStyle(.bodyM)
                        .foregroundStyle(Palette.alert)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                } else {
                    Text("join.help")
                        .typeStyle(.bodyM)
                        .foregroundStyle(Palette.inkDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: Space.none)

            PrimaryButton("group.join.action", fill: .neutral, isEnabled: store.canJoin) {
                attempt(store)
            }
            .accessibilityFocused($isJoinFocused)
        }
        .padding(.horizontal, Layout.screenInset)
        .padding(.top, Layout.blockGap)
        .padding(.bottom, Layout.itemGap)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        // The keyboard is up the whole time this sheet is open, so the column has to be able to
        // get out from under it rather than being squeezed.
        .scrollDismissesKeyboard(.interactively)
    }

    /// Prefilled → the button, empty → the field. Somebody who arrived by link has nothing to
    /// type, so raising a keyboard over a finished code would be six characters of work the app
    /// has already done, presented as work.
    private func takeFocus() {
        if InviteCode.isComplete(store?.code ?? "") {
            isJoinFocused = true
        } else {
            isCodeFocused = true
        }
    }

    /// Closing by the button. Resigns **before** asking to be dismissed, so the keyboard goes
    /// down with the sheet rather than a beat behind it — `resigningFocus(_:)` on the body is the
    /// backstop for the drag, which cannot be intercepted this way.
    private func dismiss() {
        isCodeFocused = false
        close()
    }

    private func attempt(_ store: JoinCircleStore) {
        guard store.canJoin else { return }
        isCodeFocused = false
        Task {
            if let id = await store.join() {
                joined(id)
            }
        }
    }
}
