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
    /// The track being confirmed **inside the replacement sheet** — its second page.
    @State private var confirming: TrackDTO?
    /// The track being confirmed from the screen itself, on the round's first drop. A second
    /// piece of state rather than a shared one: the two are presented by different containers,
    /// and one value driving both would try to push inside the sheet and present over the screen
    /// at the same moment.
    @State private var confirmingDirect: TrackDTO?
    /// Whether the song on screen replaced an earlier one **this session** (`docs/08` §4).
    @State private var didReplace = false
    /// The how-to sheet (`docs/08` §2, §8). Reachable from every phase through the same
    /// `[?]` in `RoundHeader`, and — like Search — a sheet rather than a fourth `Route`.
    @State private var isShowingHowTo = false
    /// The switcher (`E19-02`). Reachable from every phase through the group's own name in
    /// `RoundHeader`, and — like Search and How to play — a sheet rather than a fourth `Route`.
    @State private var isShowingSwitcher = false
    /// Bumped when the countdown elapses and when the app returns to the foreground. One
    /// `.task(id:)` does the loading, so the work is structured and cancels with the screen
    /// (`docs/13` §6) rather than being an unstructured `Task` per event.
    @State private var loadToken = 0
    /// The last thing the clock actually told this screen about where the open round sits in
    /// its own day. See `openState(_:)` for what it is for and why it is not a phase decision.
    @State private var heldOpenState = HeldOpenState()

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

        // **The screen inset belongs to the chrome and to each phase, not to the column.**
        //
        // It used to sit on this `VStack`, which was wrong for the two phases that scroll:
        // `RevealScreen` applies its own inset *inside* its scroll view — it has to, because the
        // guess sheet is pinned edge to edge beneath it and draws a hairline at the join — so
        // the reveal shipped indented forty points instead of twenty. That is a bug no golden in
        // the suite could catch, because every golden renders a screen's content without its
        // container.
        //
        // So: the header and the offline banner inset themselves, and `phase(…)` is inset only
        // for the phases whose screens do not (`Phase.bleedsToScreenEdge`). `Layout.screenInset`
        // is applied exactly once on any path from here to a pixel, and `RoundInsetTests` keeps
        // it that way by cross-checking the flag against which screens write the token.
        return phase(store: store, timer: timer, submit: submit, seal: seal)
            .padding(.horizontal, phaseInset(store))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .safeAreaInset(edge: .top, spacing: Space.none) {
                VStack(alignment: .leading, spacing: Layout.blockGap) {
                    RoundHeader(
                        groupName: headerName(store),
                        dateHeadline: store.state.value?.dateHeadline,
                        path: $router.path,
                        showHowTo: { isShowingHowTo = true },
                        openSwitcher: openSwitcher,
                        otherCircleNeedsAction: circleSwitcher(store).otherNeedsAction
                    ) {
                        badge(store: store, timer: timer)
                    }
                    if let error = store.state.error {
                        OfflineBanner(error: error)
                    }
                }
                .padding(.horizontal, Layout.screenInset)
                .padding(.top, Layout.chromeTop)
                .padding(.bottom, Layout.itemGap)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.paper)
            }
        .task(id: phaseDeadlineID(store)) { await refreshAtPhaseDeadline(store) }
        // Open, sealed, reveal and voided already render this timer. Its concrete deadline is
        // the reliable transition signal; results is covered by the task above because it has
        // no visible countdown to observe.
        //
        // Reliable **because** `CountdownTimer.hasElapsed` is a stored property the ticker
        // writes on every tick, not a computed one read on demand (`E26-04`). A computed
        // `hasElapsed` only depends, in Observation terms, on `deadline` and the clock's anchor
        // — neither of which changes while the app just sits here — so nothing ever told this
        // `onChange` to look again while time passed with the screen foregrounded and idle. The
        // countdown a few lines below still ticked correctly the whole time, because *its*
        // property (`display`) genuinely is written every tick; `hasElapsed` was not. Leaving
        // and returning "fixed" it only because that path re-anchors the clock, which used to be
        // the only write in this whole chain. Now the same write `display` gets is what
        // `hasElapsed` gets too, so this fires on the same tick the visible number does.
        .onChange(of: timer.hasElapsed) { _, elapsed in
            if elapsed == true { loadToken += 1 }
        }
        // The hold, written down. Every evaluation of this body reads the clock through
        // `liveOpenState(_:)`; the moment that reading is an answer rather than `.unknown` it
        // is kept, and `openState(_:)` falls back to it while the clock has no anchor. `initial`
        // because the first evaluation after a load is already an answer and there is nothing
        // to wait for.
        .onChange(of: liveOpenState(store), initial: true) { _, live in
            if live.value != .unknown { heldOpenState = live }
        }
        .sheet(isPresented: $isSearching) {
            searchSheet(store: store, submit: submit, seal: seal)
        }
        // The confirm step, reached from the screen itself. The replacement flow reaches its own
        // copy inside the sheet, because a sheet cannot push onto the screen behind it.
        .sheet(item: $confirmingDirect) { track in
            confirmScreen(track: track, store: store, submit: submit, seal: seal)
        }
        // The pre-prompt for notifications, after the first successful seal (`docs/05` §4).
        .sheet(isPresented: pushPromptBinding) {
            PushPermissionSheet(registrar: env.push)
        }
        // The group's own schedule, not the copy deck's placeholder hours.
        .sheet(isPresented: $isShowingHowTo) {
            HowToSheet(
                revealHour: store.state.value?.group.revealHour ?? RevealHour.default,
                close: { isShowingHowTo = false }
            )
        }
        // `E19-02`. `rows` is already ordered — needs-action circles first — so this view only
        // ever renders `CircleSwitcher`'s answer, never re-derives it.
        .sheet(isPresented: $isShowingSwitcher) {
            CircleSwitcherSheet(
                rows: circleSwitcher(store).rows,
                activeID: store.state.value?.group.id,
                select: { switchCircle(to: $0, store: store) },
                close: { isShowingSwitcher = false }
            )
        }
    }

    // MARK: - Where in the day the round sits

    /// **The hold, and why it is not the client deciding a phase.**
    ///
    /// `RootView` invalidates the clock on every `scenePhase == .active` (`docs/13` §5 rule 5:
    /// an uptime anchor does not advance while the device sleeps, so after any background period
    /// it is a lie of exactly the length of the nap). For the length of the refetch that follows
    /// — a round trip, on cellular, at eight in the evening — `env.clock.now` is `nil` and
    /// `RoundContext.openState(now:)` correctly answers `.unknown`.
    ///
    /// A screen still has to draw something in that window. The three options are: guess, blank,
    /// or hold. Guessing is what shipped and it is the bug — `.unknown` treated as *"open"* put
    /// the search screen and its keyboard over a round that was closed, for the length of every
    /// app open. Blanking to the skeleton would flash grey bars over a screen the app was told
    /// was correct four hundred milliseconds ago, on every app open, for no new information.
    /// So: **hold**. Render the last answer the clock actually gave, until it gives another.
    ///
    /// This is the argument `CountdownTimer.refresh()` already makes for the number inside the
    /// badge (`docs/13` §5a), applied to the screen around it. It is worth being explicit about
    /// what it is not, because `CLAUDE.md` §2.2 is the first thing a reviewer will reach for:
    ///
    /// - **It does not decide a phase.** `round.phase` is the server's word, decoded and never
    ///   assigned on this side, and the hold cannot reach it. What is held is which side of
    ///   `opens_at` the app was last told it is on — a fact *within* the `open` phase, about
    ///   what to draw, not about what the round now is. A round moves from `open` to `revealed`
    ///   because the server said so and for no other reason, and nothing here shortens or
    ///   extends the blind window by a millisecond.
    /// - **It does not act.** `deadlineHasPassed()` — the one place a clock reading turns into a
    ///   request — deliberately ignores the hold and reads `ServerClock` directly. A refetch
    ///   fires off a time the app currently has, or it does not fire.
    /// - **It is scoped to the round it was read from.** A hold taken on one round is discarded
    ///   the moment a different `round_id` is on screen, which is the same scoping
    ///   `CountdownTimer.start(until:form:)` applies when it clears to `.unknown` for a deadline
    ///   it has never shown a value for. Yesterday's answer is not this round's answer.
    ///
    /// **On a cold launch there is nothing held, and no flash either.** The two cannot both be
    /// true unless a `RoundContext` can never exist alongside an unanchored clock, and it cannot:
    /// `APIClient.send` calls `clock.sync(serverNow:)` on the envelope *before* it returns the
    /// payload, so by the time `RoundStore.load()` reaches `state.apply(.success(…))` the clock
    /// is anchored. Every path that produces a context goes through it — `load()` and `adopt(_:)`,
    /// and `adopt` only ever rebuilds a context that already existed. Before the first successful
    /// response there is no context and `phase(…)` draws the skeleton, which is the honest thing
    /// to draw when the app knows neither the phase nor the hour. `RoundStoreTests` asserts both
    /// halves.
    private func openState(_ context: RoundContext) -> RoundContext.OpenState {
        let live = context.openState(now: env.clock.now)
        guard live == .unknown else { return live }
        guard heldOpenState.roundID == context.round.id else { return .unknown }
        return heldOpenState.value
    }

    /// What the phase on screen is counting to, with the hold applied.
    ///
    /// `nil` only for an `open` round on a clock that has never been anchored — the cold-launch
    /// case the note above rules out. The other four rows of `RoundContext`'s table do not
    /// consult the clock at all, so a voided round knows what it is counting to whatever the
    /// clock is doing.
    private func deadline(_ context: RoundContext) -> Date? {
        context.deadline(openState: openState(context))
    }

    /// The reading as the clock has it *this instant*, before any hold is applied — the value
    /// the `.onChange` in `loaded(…)` watches. Carrying the round's id means the hold is stored
    /// with the thing that makes it valid rather than beside it.
    private func liveOpenState(_ store: RoundStore) -> HeldOpenState {
        guard let context = store.state.value else { return HeldOpenState() }
        return HeldOpenState(
            roundID: context.round.id,
            value: context.openState(now: env.clock.now)
        )
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
                } else if let deadline = deadline(context) {
                    // **The search screen is the screen** — there is no lobby in front of it.
                    // Choosing a song pushes the confirm step, which is the same destination the
                    // replacement sheet pushes, so the seal happens in exactly one place.
                    //
                    // Both arguments are resolved *here*, against the hold, and handed down
                    // already settled. `SubmitScreen` raises the keyboard on appear, and the one
                    // thing it must never be handed is a maybe: this branch existing at all is
                    // the guarantee that `isBeforeOpen` is an answer the clock gave rather than
                    // one the screen assumed.
                    SubmitScreen(
                        context: context,
                        store: submit,
                        player: player,
                        timer: timer,
                        deadline: deadline,
                        isBeforeOpen: openState(context) == .beforeOpen,
                        choose: { track in
                            seal.reset()
                            didReplace = false
                            confirmingDirect = track
                        }
                    )
                } else {
                    // `.unknown` with nothing held: a context on an unanchored clock, which the
                    // note on `openState(_:)` shows cannot happen. It is drawn rather than
                    // asserted because the skeleton is already what this screen shows when it
                    // does not know what to draw, and because the alternative — falling back to
                    // one side of `opens_at` — is the bug this task removed.
                    RoundSkeleton()
                }

            case let .voided(mySubmission):
                // Never `nil` on this phase — tomorrow's opening is a day added to `opens_at` on
                // the group's calendar and the clock has no say in it. Unwrapped rather than
                // special-cased so there is one expression for "what is this screen counting to".
                if let deadline = deadline(context) {
                    VoidedScreen(
                        context: context,
                        submission: mySubmission,
                        timer: timer,
                        deadline: deadline
                    )
                }

            // The two that scroll bleed to the edge and inset themselves: a scroll indicator
            // belongs at the screen's edge, and the reveal's guess sheet is pinned across the
            // full width with a hairline at the join (`docs/08` §6).
            case let .revealed(_, payload):
                RevealHost(
                    roundID: context.round.id,
                    payload: payload,
                    answersAt: context.round.scoresAt,
                    groupInitial: context.groupInitial,
                    me: store.me,
                    timer: timer,
                    player: player,
                    refreshRound: { loadToken += 1 }
                )

            case .scored:
                // The `scored` payload carries the base keys and nothing else (`docs/04` §4);
                // the answers are their own route, which is what `ResultsHost` goes and gets.
                // `loadToken` reaches it so a foreground refresh — or a countdown elapsing —
                // retries the answers too. Results do not change once they land, but a first
                // load that failed offline has to have a second chance that is not a relaunch.
                ResultsHost(context: context, loadToken: loadToken, player: player)
            }
        } else if store.state.isLoading {
            RoundSkeleton()
        }
    }

    /// The inset for the phase currently on screen, or the ordinary one while there is no phase
    /// yet — the skeleton is a column like any other.
    private func phaseInset(_ store: RoundStore) -> CGFloat {
        guard let phase = store.state.value?.round.phase else { return Layout.screenInset }
        return phase.bleedsToScreenEdge ? Space.none : Layout.screenInset
    }

    private func phaseDeadlineID(_ store: RoundStore) -> String? {
        guard let context = store.state.value,
              case .scored = context.round.phase,
              let deadline = deadline(context)
        else { return nil }
        return "\(context.round.id)#\(deadline.timeIntervalSinceReferenceDate)"
    }

    private func refreshAtPhaseDeadline(_ store: RoundStore) async {
        guard let context = store.state.value,
              case .scored = context.round.phase,
              let deadline = deadline(context)
        else { return }
        while !Task.isCancelled {
            guard let now = env.clock.now else {
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            let remaining = deadline.timeIntervalSince(now)
            if remaining <= 0 {
                loadToken += 1
                return
            }
            try? await Task.sleep(for: .seconds(min(remaining, 60)))
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

    /// The confirm step as its own sheet, for the first drop of the round.
    private func confirmScreen(
        track: TrackDTO,
        store: RoundStore,
        submit: SubmitStore,
        seal: SealAnimation
    ) -> some View {
        ConfirmScreen(
            track: track,
            store: submit,
            player: player,
            animation: seal,
            groupInitial: store.state.value?.groupInitial ?? "",
            revealTime: store.state.value?.revealTime ?? "",
            sealed: { submission in
                store.adopt(submission)
                confirmingDirect = nil
            },
            back: { confirmingDirect = nil },
            close: { confirmingDirect = nil }
        )
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

    /// The group's name on every phase; reveal/results add their own phase title below it.
    private func headerName(_ store: RoundStore) -> String? {
        guard let context = store.state.value else { return nil }
        return context.group.name
    }

    /// The switcher's own read of the caller's circles, against whichever one is on screen
    /// (`E19-02`). `env.circles` is already loaded by the time a `RoundContext` exists —
    /// `RoundStore.load()` cannot resolve a `groupID` without it — so this never triggers a
    /// fetch of its own.
    private func circleSwitcher(_ store: RoundStore) -> CircleSwitcher {
        CircleSwitcher(circles: env.circles.circles, activeID: store.state.value?.group.id)
    }

    /// Opens the switcher and refreshes `env.circles` behind it (`E19-02`).
    ///
    /// `resolveActiveID()`'s own "already loaded" gate exists so three stores resolving the
    /// active circle on one launch share a request — right for that, and wrong for the row
    /// states this sheet is about to show, which would otherwise never update again for the rest
    /// of the session. `CircleStore.load()` has no such gate, so this always asks.
    private func openSwitcher() {
        isShowingSwitcher = true
        Task { await env.circles.load() }
    }

    /// A row was picked in the switcher (`E19-02`). Persists the choice, clears the round
    /// **before** the refetch rather than after — see `RoundStore.invalidate()` — and reloads.
    /// Every group-scoped store resolves its own `groupID` fresh at the top of its own call, so
    /// nothing here needs rebuilding: `store.load()` picking up the new circle is the entire
    /// re-scope.
    ///
    /// The circle already on screen is a no-op past closing the sheet (review): `invalidate()`
    /// exists to remove a *different* circle's round from view while the new one loads, and
    /// running that for the circle already showing would flash the skeleton and spend a round
    /// trip to redraw the exact thing already on screen.
    private func switchCircle(to id: String, store: RoundStore) {
        isShowingSwitcher = false
        guard id != store.state.value?.group.id else { return }
        env.circles.select(id)
        store.invalidate()
        loadToken += 1
    }

    /// The status badge in the corner: what the round is doing, and when it stops doing it.
    ///
    /// Only the two amber phases carry one. The reveal and the results draw their own headers
    /// with their own countdowns, and a second clock in the corner would be the same number
    /// twice — the header would be arguing with the screen underneath it.
    ///
    /// The dark hours have no badge — the countdown they own is the big one in the middle of
    /// `SubmitScreen.closed`, and a second copy of it in the corner would be the header arguing
    /// with the screen for a different reason. That is why the test here is `== .open` rather
    /// than `!= .beforeOpen`: `.unknown` draws nothing. Held, that case does not arise; unheld,
    /// drawing nothing for a moment is the one option that cannot be wrong, and it is also what
    /// keeps `CountdownView` from being re-pointed at a deadline the app is unsure of — a
    /// changed `deadline` clears the timer to `--:--:--` (`docs/13` §5a), which is precisely the
    /// blink the hold exists to prevent.
    @ViewBuilder private func badge(store: RoundStore, timer: CountdownTimer) -> some View {
        if let context = store.state.value {
            switch context.round.phase {
            case let .open(mySubmission):
                if mySubmission != nil {
                    StatusBadge("sealed.badge", accent: .sealed)
                } else if openState(context) == .open, let deadline = deadline(context) {
                    CountdownView(
                        timer: timer,
                        deadline: deadline,
                        accent: .sealed,
                        announces: .reveal,
                        prominence: .badge,
                        format: "submit.badge"
                    )
                }
            case .voided, .revealed, .scored:
                EmptyView()
            }
        }
    }

    private func prepare() {
        guard store == nil else { return }
        store = RoundStore(
            api: env.api,
            session: env.session,
            clock: env.clock,
            router: env.router,
            circles: env.circles
        )
        submit = SubmitStore(api: env.api, circles: env.circles)
        seal = SealAnimation(haptics: env.haptics)
        timer = CountdownTimer(clock: env.clock)
    }
}

/// One reading of `RoundContext.openState(now:)`, kept together with the round it was read from.
///
/// A pair rather than two `@State`s because the id is what makes the value mean anything: a
/// `.beforeOpen` remembered from yesterday's round is not an answer about today's, and storing
/// the two side by side leaves it to whoever writes the next line to remember to check. It is
/// also the value `.onChange(of:)` watches, which is why it is `Equatable` — the observation and
/// the storage are the same shape on purpose, so there is no conversion step where the id could
/// be dropped.
private struct HeldOpenState: Equatable {
    /// `nil` before any round has loaded, which no `round_id` matches.
    var roundID: String?
    var value: RoundContext.OpenState = .unknown
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
    let player: PreviewPlayer
    let refreshRound: () -> Void

    @State private var store: RevealStore?
    @State private var unseal: UnsealAnimation?

    var body: some View {
        Group {
            if let store, let unseal {
                RevealScreen(
                    store: store,
                    timer: timer,
                    groupInitial: groupInitial,
                    unseal: unseal,
                    player: player
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
            let api = env.api
            // Captured as a value, not a reference to `CircleStore` itself: `saveGuesses` is
            // `@Sendable`, and `CircleStore` is `@MainActor`-isolated. Resolving here is free —
            // `RoundStore` would not have this reveal payload unless the circle list had
            // already loaded — so this reads the cache rather than making a second request.
            let groupID = await env.circles.resolveActiveID()
            let built = RevealStore(
                cards: payload.cards,
                pool: payload.namePool,
                myCardNumber: payload.myCardNumber,
                canGuess: payload.canGuess,
                cannotGuessReason: payload.cannotGuessReason,
                me: me,
                saveGuesses: { assignments in
                    guard let groupID else { throw APIError.offline }
                    return try await api.send(.saveGuesses(groupID, assignments))
                },
                haptics: env.haptics,
                onLockInSaved: refreshRound
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

extension RoundDTO.Phase {
    /// Whether this phase's screen draws to the **screen's** edges and applies `screenInset`
    /// itself, rather than being placed inside one by `RoundScreen`.
    ///
    /// The two that do are the two that scroll, and each has a reason that is about the edge
    /// rather than about taste: a scroll indicator belongs at the screen's edge where a thumb
    /// expects it, and the reveal's guess sheet is pinned across the full width with a hairline
    /// at the join (`docs/08` §6) — a sheet inset by twenty points would show `paper` through a
    /// seam that is supposed to be an edge.
    ///
    /// A property rather than four `.padding` calls at the call sites, because the failure it
    /// prevents is silent: a screen that insets itself *and* is inset by its container is
    /// indented forty points, and every golden in the suite renders a screen's content without
    /// its container, so no picture in the repository would show it. `RoundInsetTests` asserts
    /// this flag against the screens' own source for exactly that reason.
    var bleedsToScreenEdge: Bool {
        switch self {
        case .revealed, .scored: true
        case .open, .voided: false
        }
    }
}

/// The results, and the second route they live behind.
///
/// Its own view for the same reason `RevealHost` is: `ResultsStore` and `ResolveAnimation` are
/// `@State` here, so the countdown ticking underneath — or a foreground refetch of the round —
/// re-evaluates `RoundScreen`'s body without rebuilding either. Rebuilding the animation would
/// replay a sequence `docs/09` §4 says runs once per round, which the persisted flag would then
/// have to catch; keeping it is simply the correct thing to do.
private struct ResultsHost: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.blindDropForcesReducedMotion) private var forceReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || forceReduceMotion }
    /// The same loader every card on the screen already reads from, so the share render finds
    /// most of its artwork in the cache the flight above it filled.
    @Environment(\.artworkLoader) private var artworkLoader

    let context: RoundContext
    let loadToken: Int
    /// The app's one preview player (`docs/06` §4), shared with Submit and the reveal flight so
    /// starting a preview here stops whatever either of those had going.
    let player: PreviewPlayer

    @State private var store: ResultsStore?
    @State private var resolve: ResolveAnimation?
    /// One renderer for the whole visit, so every temporary file it writes is one thing to
    /// delete (`docs/10` §5) and switching thumbnails does not re-render what is already on disk.
    @State private var renderer: ShareRenderer?

    private var roundID: String { context.round.id }

    var body: some View {
        Group {
            if let store {
                ResultsScreen(
                    state: store.viewState(resolve: resolve),
                    // Withdrawn once the sequence has landed, so a scroll through settled
                    // answers is a plain scroll and not a gesture with a handler on it.
                    skipResolve: resolve?.isRunning == true ? { resolve?.skip() } : nil,
                    share: shareEntry(store),
                    player: player
                )
            } else {
                // One runloop, before the store exists. `docs/08` §10 gives loading a skeleton
                // and no spinner; `RoundScreen` has already drawn one for the round itself.
                Color.clear
            }
        }
        .task(id: "\(roundID)#\(loadToken)") {
            let built = store ?? ResultsStore(api: env.api, roundID: roundID, circles: env.circles)
            store = built
            // Made here rather than lazily in `body`: `@State` is not a thing a view mutates
            // while it is being evaluated, and the renderer has to be the *same* one across
            // every evaluation or the files it wrote stop being anybody's to delete.
            if renderer == nil { renderer = ShareRenderer(loader: artworkLoader) }
            await built.load()
            // Armed only once the cards are known: the sequence is defined by them, and one
            // built over an empty list would spend the round's single run on nothing.
            guard resolve == nil, !built.cards.isEmpty else { return }
            let animation = ResolveAnimation(
                roundID: roundID,
                cardNumbers: built.cards.map(\.cardNumber),
                flags: env.flags
            )
            resolve = animation
            // Awaited inside the same `.task`, so the sequence's sleeps belong to the screen's
            // lifetime: leaving the results cancels them instead of leaving timers running
            // behind a screen nobody is looking at.
            await animation.run(reducedMotion: reduceMotion)
        }
        .onDisappear {
            // Leaving the results takes the temporary files with it, whether or not a share
            // sheet ever opened (`docs/10` §5).
            renderer?.discard()
        }
    }

    /// The share card's ingredients, once the answers have landed.
    ///
    /// `nil` until then, which is also what makes the button appear with the content rather than
    /// ahead of it — there is no moment where **Share tonight** offers a card of nothing.
    private func shareEntry(_ store: ResultsStore) -> ShareEntry? {
        guard let results = store.state.value,
              let date = context.calendar.shareDate(localDate: results.localDate)
        else { return nil }

        guard let renderer else { return nil }
        return ShareEntry(
            content: ShareCardContent(
                results: results,
                groupName: context.group.name,
                date: date
            ),
            renderer: renderer
        )
    }
}

/// The group's name and the menu (`docs/08` §2, §6).
///
/// The menu is the only way to The Record, Group, and Settings, and it is on **every** phase —
/// `docs/08` §8: *"reachable from the header menu in every phase."* There is no tab bar and there
/// will not be one (`docs/13` §9).
struct RoundHeader<Badge: View>: View {
    let groupName: String?
    let dateHeadline: String?
    @Binding var path: [Route]
    /// Opens **How to play** (`docs/08` §2, §8). On every phase, next to the menu — the same
    /// place the `[?]` sits everywhere else it appears.
    let showHowTo: () -> Void
    /// Opens the switcher (`E19-02`). The group's name is the control; kept always reachable
    /// (rather than only once there is a second circle) because `E20` hangs "Start a group" off
    /// the same sheet, and a control that appears and disappears as circles come and go is a
    /// worse habit to teach than one extra tap the one-circle case does not strictly need.
    let openSwitcher: () -> Void
    /// Whether some circle **other than** the one on screen wants the caller's attention — the
    /// small mark beside the name. Never about *this* circle: the badge in the corner already
    /// says what it is doing.
    var otherCircleNeedsAction: Bool = false
    /// What the round is doing, in the corner. Empty on the phases that draw their own.
    @ViewBuilder let badge: Badge

    init(
        groupName: String?,
        dateHeadline: String? = nil,
        path: Binding<[Route]>,
        showHowTo: @escaping () -> Void,
        openSwitcher: @escaping () -> Void,
        otherCircleNeedsAction: Bool = false,
        @ViewBuilder badge: () -> Badge = { EmptyView() }
    ) {
        self.groupName = groupName
        self.dateHeadline = dateHeadline
        self._path = path
        self.showHowTo = showHowTo
        self.openSwitcher = openSwitcher
        self.otherCircleNeedsAction = otherCircleNeedsAction
        self.badge = badge()
    }

    /// **Who on the first line, when and what-it-is-doing on the second.**
    ///
    /// The badge used to sit in the top row between the name and the menu, which was wrong for
    /// the one phase whose badge is wide: *"Seals in 04:12:33"* is a dozen characters that
    /// `.fixedSize()` will not give up, so the group name — the only thing on the row that *can*
    /// yield — absorbed the whole cost. The name truncated, and the date under it wrapped onto a
    /// second line to squeeze past the pill. A header that damages the group's identity in order
    /// to report the clock has its priorities backwards.
    ///
    /// So the name gets the top row to itself, sharing it only with the menu — one glyph, fixed
    /// width, nothing to negotiate. The date and the badge pair up on the row beneath, which is
    /// the **full** column width because the menu is not on it: *when* the round is and *what it
    /// is doing* are one thought, and at the default size they sit side by side with room over.
    ///
    /// Three rows, each holding one thing: **who**, **when**, **what it is doing**. The name
    /// shares its row only with the menu — one glyph, fixed width, nothing to negotiate — and the
    /// date and the badge each get the full column width, so neither has to wrap to make room for
    /// the other. One reading order straight down the leading edge, and nothing on it competes
    /// for the same pixels.
    ///
    /// The height this costs is real, and it is paid for rather than ignored: this is the search
    /// screen with the keyboard already up, and a header that grows pushes the column into the
    /// status bar. `submit.blind` was shortened to two rendered lines in the same change that
    /// added this row. If either grows again, this is the pair to weigh — they are spending the
    /// same points.
    ///
    /// The gaps are the stacks' own rather than `.padding` on the badge, because three of the
    /// five phases pass no badge at all: `EmptyView` contributes no subview, so `VStack` spacing
    /// around it collapses to nothing, whereas a padded empty view would reserve its padding and
    /// leave a gap under the date on every badgeless phase.
    var body: some View {
        VStack(alignment: .leading, spacing: Layout.itemGap) {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(alignment: .center, spacing: Space.sm) {
                    if let groupName {
                        Button(action: openSwitcher) {
                            HStack(spacing: Space.xxs) {
                                Text(verbatim: groupName)
                                    .typeStyle(.bodyLStrong)
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Image(systemName: "chevron.down")
                                    .font(Font(Typography.uiFont(.label)))
                                    .foregroundStyle(Palette.inkDim)
                                // Small enough to ignore (`E19-02`) — the mark is that another
                                // circle wants attention, never that this one does.
                                Circle()
                                    .fill(Palette.inkDim)
                                    .frame(width: Space.xs, height: Space.xs)
                                    .opacity(otherCircleNeedsAction ? 1 : 0)
                            }
                            .minimumTouchTarget()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            Copy.A11y.switcherOpener(
                                groupName: groupName,
                                otherNeedsAction: otherCircleNeedsAction
                            )
                        )
                        .accessibilityHint(Copy.A11y.switcherOpenerHint)
                        .accessibilityAddTraits(.isButton)
                    }
                    Spacer(minLength: Space.sm)
                    HelpButton(action: showHowTo)
                    Menu {
                        Button("record.title") { path.append(.record) }
                        Button("group.title") { path.append(.group) }
                        Button("settings.title") { path.append(.settings) }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(Font(Typography.uiFont(.bodyLStrong)))
                            .foregroundStyle(Palette.inkDim)
                            .minimumTouchTarget()
                    }
                    .accessibilityLabel(Text("menu.title"))
                }
                if let dateHeadline {
                    Text(verbatim: dateHeadline)
                        .typeStyle(.caption)
                        .foregroundStyle(Palette.inkDim)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("round.dateHeadline")
                }
            }

            badge
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
