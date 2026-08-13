import SwiftUI

/// Today's round. **Switches on `round.phase` and nothing else** (`docs/13` §4).
///
/// ```
/// RoundScreen               (switches on round.state)
/// ├─ SubmitScreen           open, no submission
/// ├─ SealedScreen           open, submitted
/// ├─ VoidedScreen           voided
/// ├─ RevealScreen           revealed
/// └─ ResultsScreen          scored            ← E12-01
/// ```
///
/// Three rules meet in this file:
///
/// 1. **The client never decides a phase** (`CLAUDE.md` §2.2). The countdown reaching zero
///    refetches; what renders next is whatever the server then said. No branch here moves the
///    round along by itself, and `RoundStore` has no method that could.
/// 2. **The countdown comes from `ServerClock`** (§2.2), through one `CountdownTimer` owned here
///    and handed to whichever screen is up. One timer, not one per phase: a screen whose round
///    changed phase re-points it rather than starting a second.
/// 3. **A deep link is applied only after the round loads** (`docs/05` §5) — `RoundStore.load()`
///    calls `Router.consume(session:roundIsLoaded:)`, which is the half of that rule the round
///    owns.
struct RoundScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase

    /// Built on first appearance, because they need the environment and `@State` cannot read one
    /// at initialisation — the same shape `OnboardingFlow` uses.
    @State private var store: RoundStore?
    @State private var submit: SubmitStore?
    @State private var seal: SealAnimation?
    @State private var timer: CountdownTimer?
    @State private var player = PreviewPlayer()

    /// The search sheet (`docs/08` §3). The one modal in the app, and deliberately **not** a
    /// `Route`: it is presented from this screen and its confirm step is pushed inside it, so it
    /// never enters the app's own navigation path.
    @State private var isSearching = false
    /// The track being confirmed — the sheet's second page.
    @State private var confirming: TrackDTO?
    /// Whether the song on screen replaced an earlier one **this session** (`docs/08` §4).
    @State private var didReplace = false
    /// Bumped when the countdown elapses and when the app returns to the foreground. One
    /// `.task(id:)` does the loading, so the work is structured and cancels with the screen
    /// (`docs/13` §6) rather than being an unstructured `Task` per event.
    @State private var loadToken = 0

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.paper)
            .toolbar(.hidden, for: .navigationBar)
            // One task, so construction cannot race the load: two `.task` modifiers have no
            // guaranteed order, and a load that ran first would find no store and never re-run.
            .task(id: loadToken) {
                prepare()
                await store?.load()
            }
            .onChange(of: scenePhase) { _, phase in
                // `docs/13` §5 rule 5: the anchor is stale after any background period, and
                // `docs/08` §10: on foreground, refetch. `RootView` invalidates the clock; this is
                // the refetch that re-anchors it.
                if phase == .active { loadToken += 1 }
            }
    }

    @ViewBuilder private var content: some View {
        if let store, let timer, let submit, let seal {
            loaded(store: store, timer: timer, submit: submit, seal: seal)
        } else {
            // One runloop, before `prepare()` has run. `docs/08` §10 gives loading a skeleton and
            // no spinner; there is not yet enough known to draw even the skeleton's phase.
            Color.clear
        }
    }

    private func loaded(
        store: RoundStore,
        timer: CountdownTimer,
        submit: SubmitStore,
        seal: SealAnimation
    ) -> some View {
        @Bindable var router = env.router

        return VStack(alignment: .leading, spacing: Layout.blockGap) {
            RoundHeader(groupName: headerName(store), path: $router.path)
            if let error = store.state.error {
                OfflineBanner(error: error)
            }
            phase(store: store, timer: timer, submit: submit, seal: seal)
            Spacer(minLength: Space.none)
        }
        .padding(.horizontal, Layout.screenInset)
        .padding(.top, Layout.blockGap)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Every tick: has the thing being counted to passed? The **store** answers, from the
        // server's clock, and the answer is a refetch. The view neither knows nor decides what
        // comes next (`CLAUDE.md` §2.2).
        .onChange(of: timer.display) {
            if store.deadlineHasPassed() { loadToken += 1 }
        }
        .sheet(isPresented: $isSearching) {
            searchSheet(store: store, submit: submit, seal: seal)
        }
        // The pre-prompt for notifications, after the first successful seal (`docs/05` §4).
        .sheet(isPresented: pushPromptBinding) {
            PushPermissionSheet(registrar: env.push)
        }
    }

    // MARK: - The phases

    @ViewBuilder private func phase(
        store: RoundStore,
        timer: CountdownTimer,
        submit: SubmitStore,
        seal: SealAnimation
    ) -> some View {
        if let context = store.state.value {
            switch context.round.phase {
            case let .open(mySubmission):
                if let mySubmission {
                    SealedScreen(
                        context: context,
                        submission: mySubmission,
                        timer: timer,
                        didReplace: didReplace,
                        replace: { startSearching(replacing: true, seal: seal) }
                    )
                    // `docs/05` §4: the ask lands after the first seal and never at launch. The
                    // registrar decides whether there is anything to ask.
                    .task { await env.push.promptAfterFirstSeal() }
                } else {
                    SubmitScreen(
                        context: context,
                        timer: timer,
                        deadline: context.deadline(now: env.clock.now),
                        isBeforeOpen: context.isBeforeOpen(now: env.clock.now),
                        drop: { startSearching(replacing: false, seal: seal) }
                    )
                }

            case let .voided(mySubmission):
                VoidedScreen(
                    context: context,
                    submission: mySubmission,
                    timer: timer,
                    deadline: context.deadline(now: env.clock.now)
                )

            case let .revealed(_, payload):
                RevealHost(
                    roundID: context.round.id,
                    payload: payload,
                    answersAt: context.round.scoresAt,
                    groupInitial: context.groupInitial,
                    me: store.me,
                    timer: timer
                )

            case .scored:
                // `E12-01` lands `ResultsScreen` here. Until then the round is over and this says
                // only what it can stand behind: `docs/04` §4's `scored` payload carries the base
                // keys and nothing else, and a results view built from guesses about the rest
                // would be worse than a quiet screen.
                Color.clear
            }
        } else if store.state.isLoading {
            RoundSkeleton()
        }
    }

    // MARK: - The sheet

    private func searchSheet(store: RoundStore, submit: SubmitStore, seal: SealAnimation) -> some View {
        NavigationStack {
            SearchSheet(
                store: submit,
                player: player,
                choose: { confirming = $0 },
                close: { isSearching = false }
            )
            .navigationDestination(item: $confirming) { track in
                ConfirmScreen(
                    track: track,
                    store: submit,
                    player: player,
                    animation: seal,
                    groupInitial: store.state.value?.groupInitial ?? "",
                    revealTime: store.state.value?.revealTime ?? "",
                    sealed: { submission in
                        // The server sealed it; the round adopts what the server said and the
                        // sheet closes onto an already-sealed card (`docs/08` §3.2). The animation
                        // is not replayed underneath, because `SealedCard` draws the landed state
                        // and never animates.
                        store.adopt(submission)
                        isSearching = false
                        confirming = nil
                    },
                    back: { confirming = nil },
                    close: {
                        isSearching = false
                        confirming = nil
                    }
                )
                .toolbar(.hidden, for: .navigationBar)
            }
        }
        .presentationCornerRadius(Radius.sheet)
        .presentationDragIndicator(.visible)
    }

    private func startSearching(replacing: Bool, seal: SealAnimation) {
        // A replacement re-runs the seal, so the confirm layout must start unsealed — `docs/08`
        // §4: *"After replacing, the seal animation runs again."*
        seal.reset()
        didReplace = replacing
        confirming = nil
        isSearching = true
    }

    /// The pre-prompt's presentation, owned by the registrar so the timing rule lives in one place.
    private var pushPromptBinding: Binding<Bool> {
        Binding(
            get: { env.push.isPrompting },
            set: { if !$0 { env.push.skip() } }
        )
    }

    // MARK: - Chrome

    /// The group's name, or nothing on the phases that draw their own title (`docs/08` §6).
    private func headerName(_ store: RoundStore) -> String? {
        guard let context = store.state.value else { return nil }
        return switch context.round.phase {
        case .open, .voided: context.group.name
        case .revealed, .scored: nil
        }
    }

    private func prepare() {
        guard store == nil else { return }
        store = RoundStore(api: env.api, session: env.session, clock: env.clock, router: env.router)
        submit = SubmitStore(api: env.api)
        seal = SealAnimation(haptics: env.haptics)
        timer = CountdownTimer(clock: env.clock)
    }
}

/// The reveal, with a store that survives a refetch.
///
/// It exists for one reason: `RevealStore` holds the caller's **in-progress** sheet — the focused
/// card, the selected chip, the assignments — and rebuilding it on every body evaluation would
/// throw that away once a second as the countdown ticks. `@State` here keeps it; `adopt(_:)` folds
/// a fresh payload's saved guesses in without touching the interaction, which is exactly what that
/// method was written for (`E11-02`).
private struct RevealHost: View {
    @Environment(AppEnvironment.self) private var env

    let roundID: String
    let payload: RevealPayload
    let answersAt: Date
    let groupInitial: String
    let me: String?
    let timer: CountdownTimer

    @State private var store: RevealStore?
    @State private var unseal: UnsealAnimation?

    var body: some View {
        Group {
            if let store, let unseal {
                RevealScreen(
                    store: store,
                    timer: timer,
                    groupInitial: groupInitial,
                    unseal: unseal
                )
            } else {
                Color.clear
            }
        }
        .task(id: payload.cards.map(\.cardNumber)) {
            guard store == nil else {
                // A refetch during the reveal: take the server's saved sheet, keep the taps.
                store?.adopt(payload.myGuesses)
                return
            }
            let built = RevealStore(
                cards: payload.cards,
                pool: payload.namePool,
                myCardNumber: payload.myCardNumber,
                canGuess: payload.canGuess,
                cannotGuessReason: payload.cannotGuessReason,
                me: me
            )
            built.adopt(payload.myGuesses)
            built.answersAt = answersAt
            unseal = UnsealAnimation(
                roundID: roundID,
                cardNumbers: payload.cards.map(\.cardNumber),
                flags: env.flags,
                haptics: env.haptics
            )
            store = built
        }
    }
}

/// The group's name and the menu (`docs/08` §2, §6).
///
/// The menu is the only way to The Record and to Group settings, and it is on **every** phase —
/// `docs/08` §8: *"reachable from the header menu in every phase."* There is no tab bar and there
/// will not be one (`docs/13` §9).
struct RoundHeader: View {
    let groupName: String?
    @Binding var path: [Route]

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            if let groupName {
                Text(verbatim: groupName)
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.inkDim)
            }
            Spacer(minLength: Space.none)
            Menu {
                Button("record.title") { path.append(.record) }
                Button("settings.title") { path.append(.groupSettings) }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(Font(Typography.uiFont(.bodyLStrong)))
                    .foregroundStyle(Palette.inkDim)
                    .minimumTouchTarget()
            }
            .accessibilityLabel(Text("menu.title"))
        }
    }
}

/// The offline banner (`docs/08` §10): shown **with** the data, never instead of it.
///
/// `error.offline.stale` — *"Showing what we had. This may be out of date."* — is the honest line
/// for a failed refresh over a screen that still has yesterday's answer on it. Anything else the
/// server said gets its own words from the copy deck.
struct OfflineBanner: View {
    let error: APIError

    var body: some View {
        Text(LocalizedStringKey(error == .offline ? "error.offline.stale" : error.copyKey))
            .typeStyle(.caption)
            .foregroundStyle(Palette.inkDim)
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Palette.paperSunk)
            )
    }
}

/// The first-launch skeleton (`docs/08` §10): the shape of the layout in `paperSunk`. **No
/// spinner, no logo animation** — and under 1.2s or it is a bug.
struct RoundSkeleton: View {
    /// The three blocks every phase screen has: a headline, a subject, an action. Their widths are
    /// fractions of the column so the skeleton is the *shape* of a screen rather than a specific
    /// one — it is on screen for a moment and it must not promise a phase the server has not named.
    private let blocks: [CGFloat] = [0.6, 0.9, 1]

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.blockGap) {
            ForEach(blocks, id: \.self) { fraction in
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Palette.paperSunk)
                    .frame(maxWidth: .infinity)
                    .frame(height: Layout.buttonHeight)
                    .scaleEffect(x: fraction, anchor: .leading)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The notification pre-prompt (`docs/05` §4, `docs/11` `push.permission.*`).
///
/// It states exactly what will arrive and that there is nothing else, **before** spending the
/// system's one-shot dialog. That order is the whole point: a person who says no to the system
/// prompt cannot be asked again by anybody, ever, so the app asks a question it can afford to
/// hear "not now" to first.
struct PushPermissionSheet: View {
    let registrar: PushRegistrar

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.itemGap) {
            Text("push.permission.title")
                .typeStyle(.displayM)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("push.permission.body")
                .typeStyle(.bodyL)
                .foregroundStyle(Palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)

            PrimaryButton("push.permission.allow", fill: .neutral) {
                Task { await registrar.allow() }
            }
            .padding(.top, Layout.blockGap - Layout.itemGap)

            SecondaryButton("push.permission.skip") { registrar.skip() }
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(Layout.screenInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.paper)
        .presentationDetents([.medium])
        .presentationCornerRadius(Radius.sheet)
    }
}
