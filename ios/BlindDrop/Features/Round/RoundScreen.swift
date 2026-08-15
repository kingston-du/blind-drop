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
        return VStack(alignment: .leading, spacing: Layout.blockGap) {
            VStack(alignment: .leading, spacing: Layout.blockGap) {
                RoundHeader(
                    groupName: headerName(store),
                    dateHeadline: store.state.value?.dateHeadline,
                    path: $router.path,
                    showHowTo: { isShowingHowTo = true }
                ) {
                    badge(store: store, timer: timer)
                }
                if let error = store.state.error {
                    OfflineBanner(error: error)
                }
            }
            .padding(.horizontal, Layout.screenInset)

            phase(store: store, timer: timer, submit: submit, seal: seal)
                .padding(.horizontal, phaseInset(store))
            Spacer(minLength: Space.none)
        }
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
                    // **The search screen is the screen** — there is no lobby in front of it.
                    // Choosing a song pushes the confirm step, which is the same destination the
                    // replacement sheet pushes, so the seal happens in exactly one place.
                    SubmitScreen(
                        context: context,
                        store: submit,
                        player: player,
                        timer: timer,
                        deadline: context.deadline(now: env.clock.now),
                        isBeforeOpen: context.isBeforeOpen(now: env.clock.now),
                        choose: { track in
                            seal.reset()
                            didReplace = false
                            confirmingDirect = track
                        }
                    )
                }

            case let .voided(mySubmission):
                VoidedScreen(
                    context: context,
                    submission: mySubmission,
                    timer: timer,
                    deadline: context.deadline(now: env.clock.now)
                )

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
                    player: player
                )

            case .scored:
                // The `scored` payload carries the base keys and nothing else (`docs/04` §4);
                // the answers are their own route, which is what `ResultsHost` goes and gets.
                // `loadToken` reaches it so a foreground refresh — or a countdown elapsing —
                // retries the answers too. Results do not change once they land, but a first
                // load that failed offline has to have a second chance that is not a relaunch.
                ResultsHost(context: context, loadToken: loadToken)
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

    /// The group's name, or nothing on the phases that draw their own title (`docs/08` §6).
    private func headerName(_ store: RoundStore) -> String? {
        guard let context = store.state.value else { return nil }
        return switch context.round.phase {
        case .open, .voided: context.group.name
        case .revealed, .scored: nil
        }
    }

    /// The status badge in the corner: what the round is doing, and when it stops doing it.
    ///
    /// Only the two amber phases carry one. The reveal and the results draw their own headers
    /// with their own countdowns, and a second clock in the corner would be the same number
    /// twice — the header would be arguing with the screen underneath it.
    @ViewBuilder private func badge(store: RoundStore, timer: CountdownTimer) -> some View {
        if let context = store.state.value {
            switch context.round.phase {
            case let .open(mySubmission):
                if mySubmission != nil {
                    StatusBadge("sealed.badge", accent: .sealed)
                } else if !context.isBeforeOpen(now: env.clock.now) {
                    CountdownView(
                        timer: timer,
                        deadline: context.deadline(now: env.clock.now),
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
    let player: PreviewPlayer

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
            let built = RevealStore(
                cards: payload.cards,
                pool: payload.namePool,
                myCardNumber: payload.myCardNumber,
                canGuess: payload.canGuess,
                cannotGuessReason: payload.cannotGuessReason,
                me: me,
                saveGuesses: { assignments in
                    try await api.send(.saveGuesses(assignments))
                }
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
                    share: shareEntry(store)
                )
            } else {
                // One runloop, before the store exists. `docs/08` §10 gives loading a skeleton
                // and no spinner; `RoundScreen` has already drawn one for the round itself.
                Color.clear
            }
        }
        .task(id: "\(roundID)#\(loadToken)") {
            let built = store ?? ResultsStore(api: env.api, roundID: roundID)
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
    /// What the round is doing, in the corner. Empty on the phases that draw their own.
    @ViewBuilder let badge: Badge

    init(
        groupName: String?,
        dateHeadline: String? = nil,
        path: Binding<[Route]>,
        showHowTo: @escaping () -> Void,
        @ViewBuilder badge: () -> Badge = { EmptyView() }
    ) {
        self.groupName = groupName
        self.dateHeadline = dateHeadline
        self._path = path
        self.showHowTo = showHowTo
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
                        Text(verbatim: groupName)
                            .typeStyle(.bodyLStrong)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .truncationMode(.tail)
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
