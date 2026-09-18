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
/// One past night, addressed by id — the dark hours' route into last night's answers.
private struct PastResultsRoute: Hashable, Identifiable {
    let id: String
}

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
    /// The how-to sheet (`docs/08` §2, §8). Reachable from every phase through the same
    /// `[?]` in `RoundHeader`, and — like Search — a sheet rather than a fourth `Route`.
    @State private var isShowingHowTo = false
    /// The switcher (`E19-02`). Reachable from every phase through the group's own name in
    /// `RoundHeader`, and — like Search and How to play — a sheet rather than a fourth `Route`.
    @State private var isShowingSwitcher = false
    /// The creation-and-invitation flow starts from the switcher but is its own sheet: a form
    /// needs keyboard room and must not distort the switcher's measured detent.
    @State private var isStartingGroup = false
    /// What the switcher asked for on its way out (`E38-04`).
    ///
    /// Held rather than acted on, because presenting a second sheet in the same update that
    /// dismisses the first is a dismissal racing a presentation — UIKit runs them back to back
    /// and the new sheet arrives while the old one is still sliding away, which is the stutter
    /// on **Start a group**. `onDismiss` is the moment the switcher is genuinely gone.
    @State private var switcherExit: SwitcherExit?
    /// The join-by-code sheet (`E38-02`), reached from the switcher's footer or from a
    /// `/j/<CODE>` link that arrived while the caller already had a circle. It carries the code
    /// so both doors open the same sheet.
    @State private var joinPrompt: JoinPrompt?
    /// Bumped when the countdown elapses and when the app returns to the foreground. One
    /// `.task(id:)` does the loading, so the work is structured and cancels with the screen
    /// (`docs/13` §6) rather than being an unstructured `Task` per event.
    @State private var loadToken = 0
    /// The last thing the clock actually told this screen about where the open round sits in
    /// its own day. See `openState(_:)` for what it is for and why it is not a phase decision.
    @State private var heldOpenState = HeldOpenState()
    /// Last night's answers, pushed from the dark hours (`docs/18-CUES.md` §7). A push, not a
    /// sheet: it is a screen you read and come back from, which is how The Record already
    /// presents exactly the same destination.
    @State private var pastResults: PastResultsRoute?

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Ignores the keyboard's own safe area, on the bottom edge only. `content` itself
            // still shrinks and shifts for the keyboard exactly as it always has — every
            // phase's own avoidance (`SongSearch`'s careful non-pinned layout, above all) is
            // untouched, because this reaches only the color painted *behind* `content`, never
            // `content`'s own frame. Without it, the fill was one keyboard-avoidance timing edge
            // case away from stopping short of the keyboard and letting the plain system window
            // colour show through the keyboard's translucent top corners instead of `paper` — a
            // pale sliver at both corners the moment the keyboard came up, on every keyboard-up
            // screen this background sits behind.
            //
            // **Both regions, not just `.keyboard`.** `.background(Palette.paper)` took the
            // `ShapeStyle` overload, whose `ignoresSafeAreaEdges` defaults to `.all` — which is
            // why a bare colour bled under the home indicator without anyone writing that down.
            // Wrapping it in a modifier makes it a *view*, so the `background(alignment:content:)`
            // overload applies instead and that bleed is gone: naming only `.keyboard` here left a
            // white band of bare window across the bottom safe area on every phase. `.ignoresSafeArea()`
            // with its defaults is `[.container, .keyboard]` on every edge, which is both intents at once.
            .background(Palette.paper.ignoresSafeArea())
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
            // `E19-03`: a notification tapped while this screen is already up — no background
            // period, so `scenePhase` never changes — needs its own reload. Cold and warm
            // launch are covered by `.task(id:)`'s first run and the `scenePhase` case above;
            // this is the one they miss. Firing only on `nil → non-nil` means a link already
            // consumed (cleared back to `nil`) cannot re-trigger itself.
            .onChange(of: env.router.pending) { _, pending in
                if pending != nil { loadToken += 1 }
            }
            // `E21-01`: leaving the active circle changes `activeGroupID` out from under this
            // screen — `GroupStore.leave()` refreshes `CircleStore` and pops back to here, but
            // nothing else tells this screen its round is now for a circle the caller left.
            // `switchCircle(to:store:)` already invalidates explicitly for its own tap; this is
            // the same reasoning, reached a different way and only when the id actually moved —
            // `nil` guards the very first run, where there is nothing yet to compare against.
            .onChange(of: env.circles.activeGroupID) { old, new in
                guard old != nil, new != old else { return }
                // `E38-04`: and **only** when nothing is already loading. `switchCircle` clears
                // to `.loading` before it bumps the token, and this fires afterwards on the
                // same tap — `activeGroupID` is recomputed on the body evaluation that
                // `invalidate()` itself triggers, so the id has genuinely moved by the time
                // this runs. Left unguarded it spent a second, redundant round trip on every
                // switch and cancelled the first one mid-flight. The case this exists for —
                // leaving the active circle — happens against a `.loaded` round, so it is
                // unaffected.
                guard store?.state.isLoading == false else { return }
                // **And the same guard again, for the switch that no longer clears to
                // `.loading`** (`E44-02`). `switchCircle` now serves a remembered round for a
                // circle already seen this session, which leaves the store `.loaded` rather than
                // `.loading` — so the `isLoading` test above stops catching its own tap and this
                // fires a second, redundant load that cancels the first one mid-flight. That is
                // the `E38-04` bug exactly, reached through the door `E44-02` opened.
                //
                // Asking whether the round on screen is *already the circle that was switched to*
                // catches both spellings and needs no new flag. The case this whole `onChange`
                // exists for — `E21-01`, leaving the active circle — is unaffected: there the
                // round on screen belongs to the circle just left, which is by definition not
                // `new`.
                guard store?.state.value?.group.id != new else { return }
                store?.invalidate(switchingTo: new)
                loadToken += 1
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
        //
        // The cue banner below is a sibling of `phase(…)`, not a child of its padding, so it
        // carries its own `Layout.screenInset` — on **every** phase, including the two that
        // bleed. `RoundInsetTests` scans the phase screens' own files, not this one, so the
        // banner's inset is not part of the flag's accounting.
        return VStack(alignment: .leading, spacing: Space.none) {
            // The cue (`docs/18-CUES.md` §7): one placement above whichever phase screen is up.
            // Only over a loaded round — never the skeleton or error — and only when there is a
            // cue: `CueBanner` renders `EmptyView` for `nil`, and the padding here is applied to
            // the banner's line rather than to that empty view, so an uncued night adds no gap.
            //
            // **Which is now Sealed and Voided and nothing else.** The three phases that read as
            // a column — the drop screen, the flight, the answers — draw the cue inside it, each
            // for the same reason: a cue above the scroll is a header on the work, and the cue is
            // a brief you read once before it. Those two do not scroll, so there is no "before"
            // to move it to; above the phase is where it already is. `Phase.drawsItsOwnCue` is the
            // one place the exception is decided.
            if let cue = store.state.value?.round.cue,
               store.state.value?.round.phase.drawsItsOwnCue == false {
                CueBanner(cue: cue)
                    .padding(.horizontal, Layout.screenInset)
                    .padding(.bottom, Layout.itemGap)
            }
            phase(store: store, timer: timer, submit: submit, seal: seal)
                .padding(.horizontal, phaseInset(store))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .safeAreaInset(edge: .top, spacing: Space.none) {
            VStack(alignment: .leading, spacing: Layout.blockGap) {
                RoundHeader(
                    groupName: headerName(store),
                    // `nil` on the two phases that scroll, which draw it themselves as the eyebrow
                    // over their own headline — `Phase.scrollsItsOwnDate` argues why. `nil` here
                    // collapses the whole second row *and* the rule above it through the existing
                    // `hasStanding`, which is the loading header's path and needs nothing new.
                    dateHeadline: pinsDateHeadline(store) ? store.state.value?.dateHeadline : nil,
                    shortDateHeadline: pinsDateHeadline(store)
                        ? store.state.value?.shortDateHeadline
                        : nil,
                    path: $router.path,
                    showHowTo: { isShowingHowTo = true },
                    openSwitcher: openSwitcher,
                    otherCircleNeedsAction: circleSwitcher(store).otherNeedsAction
                ) {
                    badge(store: store, timer: timer)
                }
                // A banner belongs over a stale screen: it qualifies data that is still
                // useful enough to show. A first-load failure has no data beneath it and is
                // rendered by `phase(…)` as a full error state with its own retry action.
                if store.state.value != nil, let error = store.state.error {
                    OfflineBanner(error: error)
                }
            }
            .padding(.horizontal, Layout.screenInset)
            .padding(.top, Layout.chromeTop)
            // **Less below the name row when the rule is what closes the block** (owner,
            // 2026-09-07). A gap here is too much above a hairline: the name row is a 44pt touch
            // target around a 20pt line, so it already contributes a dozen points of slack under
            // the text, and a full `itemGap` more put the rule nearer the date beneath it than
            // the name it belongs to. `Space.xs` leaves the rule where the row visually ends,
            // and the clearance under it is the scrolling phases' own (`RevealScreen.flight`,
            // `ResultsScreen`).
            //
            // `Space.sm` rather than `Layout.itemGap` on the pinned phases, where the next thing
            // is a block rather than a rule. Four of those points are the last of what the drop
            // screen's column needed to fit between this chrome and its keyboard — see
            // `SubmitScreen`'s `blockSpacing` for what overflowing that band costs, and why the
            // gaps paid for it rather than a line of copy.
            .padding(.bottom, pinsDateHeadline(store) ? Space.sm : Space.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.paper)
            // **The bottom of the chrome, where a list passes under it** (owner, 2026-09-06).
            //
            // Edge to edge, outside the horizontal inset, because it is the edge of a block and
            // not a divider inside one — the same rule, in the same `edge` rather than `hairline`,
            // that `GuessSheet` draws at its own join across the bottom of this very screen. That
            // sheet's note is the argument in full: `docs/07` §2 rules out a shadow, so a hairline
            // is what stops `paper` showing through a seam that is meant to be an edge. A fade was
            // the alternative and is wrong here twice over: a gradient to `paper` washes grey
            // across the white cards it crosses and does nothing in the gaps between them — the
            // mistake the name pool's own fade already documents — and the `.mask()` that avoids
            // the tint dissolves the borders off a bordered, rounded card instead. One screen
            // should not answer the same question two different ways at its two edges.
            //
            // **Only when the header is a single row**, which is the same test as the date being
            // withheld. With the date pinned, `RoundHeader` draws its own rule between its two
            // rows and the block is already legibly a block; a second line a few points below it
            // is noise, and on those phases nothing scrolls under the chrome anyway. Withholding
            // the date collapses that internal rule along with the row (`hasStanding`), which is
            // what left the name row on Reveal and Results floating over a moving list with
            // nothing marking where the chrome stopped. This puts the mark back where it went.
            .overlay(alignment: .bottom) {
                if !pinsDateHeadline(store) {
                    // `Rule`, not a hand-rolled rectangle: one device pixel, and hidden from
                    // VoiceOver for free — a mark, not a stop.
                    Rule(color: Palette.edge)
                }
            }
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
        .sheet(isPresented: $isShowingSwitcher, onDismiss: presentSwitcherExit) {
            CircleSwitcherSheet(
                rows: circleSwitcher(store).rows,
                activeID: store.state.value?.group.id,
                select: { switchCircle(to: $0, store: store) },
                startGroup: { leaveSwitcher(for: .startGroup) },
                joinWithCode: { leaveSwitcher(for: .joinWithCode) },
                acceptInvitation: { switchCircle(to: $0, store: store) },
                close: { isShowingSwitcher = false }
            )
        }
        .sheet(isPresented: $isStartingGroup) {
            StartGroupSheet()
        }
        .sheet(item: $joinPrompt) { prompt in
            JoinCircleSheet(
                prefilledCode: prompt.code,
                joined: { id in
                    joinPrompt = nil
                    switchCircle(to: id, store: store)
                },
                close: { joinPrompt = nil }
            )
        }
        // `E38-02`. A `/j/<CODE>` link consumed by `Router` for a `.ready` session leaves its
        // code here; this is the half that opens the sheet. Cleared immediately so returning to
        // the screen later does not re-present a code the caller already dealt with — the same
        // contract `JoinOrCreateScreen` has with `clearPendingInviteCode()`.
        .onChange(of: env.router.pendingInviteCode, initial: true) { _, code in
            guard let code, !code.isEmpty else { return }
            env.router.clearPendingInviteCode()
            isShowingSwitcher = false
            switcherExit = nil
            joinPrompt = JoinPrompt(code: code)
        }
        // The dark hours' link into the night that just ended. The same destination The Record
        // pushes from a date header, given the id the server sent — so a night reached from
        // here and the same night reached from the archive are one screen, not two.
        .navigationDestination(item: $pastResults) { route in
            PastResultsScreen(roundID: route.id, player: player)
        }
    }

    /// The switcher's two footer actions and the sheet they hand over to. See `switcherExit`.
    private func leaveSwitcher(for exit: SwitcherExit) {
        switcherExit = exit
        isShowingSwitcher = false
    }

    private func presentSwitcherExit() {
        guard let exit = switcherExit else { return }
        switcherExit = nil
        switch exit {
        case .startGroup: isStartingGroup = true
        case .joinWithCode: joinPrompt = JoinPrompt(code: "")
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
                        replace: { startSearching(seal: seal) },
                        // The one shared player (`docs/06` §4: one at a time) — the same instance
                        // Submit's search sheet and the reveal flight already play through, so
                        // holding a peek here stops whatever either of those had going.
                        player: player
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
                        cue: context.round.cue,
                        previousCue: context.round.previousCue,
                        // The dark hours' one action. `nil` unless the server sent an id, which
                        // it does only in this window and only for a night that scored — so the
                        // screen never offers a route to results that do not exist, and the
                        // decision is the server's rather than a state check made here.
                        showLastNightsResults: context.round.previousRoundID.map { id in
                            { pastResults = PastResultsRoute(id: id) }
                        },
                        choose: { track in
                            seal.reset()
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
                    dateHeadline: context.dateHeadline,
                    cue: context.round.cue,
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
        } else if let error = store.state.error {
            VStack(alignment: .leading, spacing: Layout.blockGap) {
                Text(LocalizedStringKey(error.copyKey))
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.inkDim)

                PrimaryButton("error.retry", fill: .neutral) {
                    loadToken += 1
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Whether the pinned chrome carries the date, or the phase screen does.
    ///
    /// The skeleton and the error state have no phase yet and keep it: they are what is on screen
    /// while the round is still arriving, so the header is the only thing that could say which
    /// night this is.
    private func pinsDateHeadline(_ store: RoundStore) -> Bool {
        guard let phase = store.state.value?.round.phase else { return true }
        return !phase.scrollsItsOwnDate
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
                        adoptSeal(submission, into: store)
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
                adoptSeal(submission, into: store)
                confirmingDirect = nil
            },
            back: { confirmingDirect = nil },
            close: { confirmingDirect = nil }
        )
        .presentationCornerRadius(Radius.sheet)
        .presentationDragIndicator(.visible)
    }

    private func startSearching(seal: SealAnimation) {
        // A replacement re-runs the seal, so the confirm layout must start unsealed — `docs/08`
        // §4: *"After replacing, the seal animation runs again."*
        seal.reset()
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
    /// **before** the refetch rather than after — see `RoundStore.invalidate(switchingTo:)` —
    /// and reloads. A circle seen earlier this session is put back on screen from that store's
    /// memo instead of being cleared at all (`E44-02`), and the reload then refreshes it in
    /// place; the ordering is unchanged either way, because what must not happen is the
    /// *previous* circle's round surviving the switch.
    /// Every group-scoped store resolves its own `groupID` fresh at the top of its own call, so
    /// nothing here needs rebuilding: `store.load()` picking up the new circle is the entire
    /// re-scope.
    ///
    /// The circle already on screen is a no-op past closing the sheet (review): `invalidate()`
    /// exists to remove a *different* circle's round from view while the new one loads, and
    /// running that for the circle already showing would flash the skeleton and spend a round
    /// trip to redraw the exact thing already on screen.
    ///
    /// Clears any pending deep link too (`E19-03` review): a person's own tap here is an
    /// explicit choice, and it is the last word — a link still "owed" its navigation from an
    /// in-flight load for a *different* circle must not be left to reassert itself and quietly
    /// switch back the moment that load lands.
    private func switchCircle(to id: String, store: RoundStore) {
        isShowingSwitcher = false
        guard id != store.state.value?.group.id else { return }
        env.circles.select(id)
        env.router.clearPending()
        store.invalidate(switchingTo: id)
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

    /// **Adopt what the server sealed, then go back for the round it sealed it into.**
    ///
    /// The adopt is the instant half and `RoundStore.adopt(_:)` documents why it exists: the
    /// sheet has to dismiss onto an already-sealed card rather than onto a submit screen that
    /// corrects itself a round trip later. What it cannot do is tell the truth about *time*.
    /// `RoundDTO.adopting(mySubmission:)` copies every field it is not replacing, `reveals_at`
    /// among them, so the round the screen holds afterwards carries the reveal instant the app
    /// last **fetched** — which is only still correct if sealing did not move it.
    ///
    /// On a real group it does not, and this refetch is one idempotent GET returning the value
    /// already on screen. On the App Review demo group it does: `demo_arm()` sets `reveals_at`
    /// to twelve seconds out on the submit itself (`docs/APP-REVIEW-NOTES.md` §1), and the
    /// response the client adopts is a `SubmissionDTO`, which has no round in it and no way to
    /// carry the new instant. So the sealed screen counted to the group's 8:00 PM as if nothing
    /// had happened, `CountdownTimer.hasElapsed` was hours from flipping, and the refetch that
    /// would have revealed the round never fired — until the app was backgrounded and
    /// `scenePhase` bumped the token out of band. A reviewer's read of that is "the timer is
    /// wrong and the phase only changes if I leave the screen", and they would have been right.
    ///
    /// Bumping `loadToken` is deliberately the **same** mechanism the guess half already uses —
    /// `RevealStore`'s `onLockInSaved` → `refreshRound` above, which is why locking in a sheet
    /// picks up its twenty-second scoring arm and sealing did not. One way for the client to
    /// say *"the server may have moved something under me"*, not two.
    ///
    /// It is not a phase decision and cannot become one (`CLAUDE.md` §2.2): it asks, and renders
    /// whatever comes back.
    private func adoptSeal(_ submission: SubmissionDTO, into store: RoundStore) {
        store.adopt(submission)
        loadToken += 1
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
    /// The night, for the eyebrow over the flight's headline — `Phase.scrollsItsOwnDate`.
    let dateHeadline: String?
    /// Tonight's cue, drawn inside the scroll under the count — `RoundDTO.Phase.drawsItsOwnCue`.
    let cue: CueDTO?
    let groupInitial: String
    let me: String?
    let timer: CountdownTimer
    let player: PreviewPlayer
    let refreshRound: () -> Void

    @State private var store: RevealStore?
    @State private var unseal: UnsealAnimation?
    @State private var quickPassPresented = false

    var body: some View {
        Group {
            if let store, let unseal {
                RevealScreen(
                    store: store,
                    timer: timer,
                    dateHeadline: dateHeadline,
                    cue: cue,
                    groupInitial: groupInitial,
                    unseal: unseal,
                    player: player,
                    startQuickPass: { quickPassPresented = true }
                )
            } else {
                Color.clear
            }
        }
        // **The first `fullScreenCover` in the app**, and every other modal here is a `.sheet`
        // (`RootView.swift`, and five more on this screen). Justified rather than casual: a
        // sheet's grabber and inset corners keep the flight visible behind the one screen in the
        // app that is deliberately about a single card, and its detent chrome sits exactly where
        // the name grid needs to be (`E41-01`).
        .fullScreenCover(isPresented: $quickPassPresented) {
            if let store {
                QuickPassScreen(store: store, timer: timer, player: player, cue: cue) {
                    quickPassPresented = false
                }
            }
        }
        // **Where a reveal push lands** (`E41-02`). Nothing on the server changes for this: the
        // `reveal` and `guess_reminder` pushes already deep-link to the round root, which during
        // `revealed` is this view. All that was missing is the decision about what to open, and
        // `QuickPassPresentation` is that decision, kept as a pure function so its three clauses
        // are testable rather than buried in a condition here.
        //
        // Driven off the unseal's scheduling as well as the store, because *wait for the unseal*
        // is a state that changes after this view first appears — a plain `.task` would evaluate
        // once, decide no, and never look again.
        .onChange(of: presentationConditions) { _, conditions in
            offerQuickPassIfNeeded(conditions)
        }
        .onAppear { offerQuickPassIfNeeded(presentationConditions) }
        // **The answers instant is a moving value, not a constructor argument.**
        //
        // It used to be written in exactly one place — `built.answersAt` in the task below —
        // which is inside the branch that *builds* the store. A refetch takes the other branch
        // and returns, and the task's own id is the card numbers, which do not change across a
        // refetch, so on the common path it does not even re-run. The countdown on the reveal
        // therefore counted to whatever `scores_at` was when the reveal first drew, for the whole
        // life of the screen.
        //
        // On a real group that is invisible: `scores_at` is fixed two hours out and the value it
        // was built with is still the right one. On the App Review demo group it is the whole
        // bug. `demo_arm()` moves `scores_at` to twenty seconds out when the guess sheet lands
        // complete (`docs/APP-REVIEW-NOTES.md` §1), `onLockInSaved` → `refreshRound` duly
        // refetches the round, and `RoundScreen` duly passes the new instant down — and it landed
        // nowhere, because nothing here was listening. The countdown went on reading the two-hour
        // window, `CountdownTimer.hasElapsed` never flipped, and the refetch that would have
        // brought the answers never fired. Only backgrounding the app moved it on, via
        // `scenePhase`'s own token bump, which is the same out-of-band rescue the seal half was
        // relying on before `adoptSeal(_:into:)`.
        //
        // `RevealStore.answersAt` is `@Observable` and `RevealScreen` hands it to `CountdownView`
        // as its `deadline`, whose own `.onChange(of: deadline)` re-points the ticker — so writing
        // it here is all that is needed for the countdown to pick the new instant up mid-screen.
        // It touches nothing about the in-progress sheet, which is the one thing `RevealHost`
        // exists to protect.
        .onChange(of: answersAt) { _, instant in store?.answersAt = instant }
        .task(id: payload.cards.map(\.cardNumber)) {
            guard store == nil else {
                // A refetch during the reveal: take the server's saved sheet, keep the taps.
                // `answersAt` comes with it — this branch runs when the *cards* changed, which
                // is a different round or a re-deal, and carrying the previous round's answers
                // instant into it would be the same staleness the `.onChange` above fixes for
                // the ordinary case.
                store?.adopt(payload.myGuesses)
                store?.adopt(reactions: payload.myReactions)
                store?.answersAt = answersAt
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
                // One card at a time, unlike the sheet above (`docs/19` §7). Same resolved
                // `groupID` value and the same `@Sendable` constraint, for the same reason.
                saveReaction: { cardNumber, kind in
                    guard let groupID else { throw APIError.offline }
                    return try await api.send(
                        .saveReaction(groupID, cardNumber: cardNumber, kind: kind)
                    )
                },
                haptics: env.haptics,
                onLockInSaved: refreshRound
            )
            built.adopt(payload.myGuesses)
            built.adopt(reactions: payload.myReactions)
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

    private var presentationConditions: QuickPassPresentation.Conditions {
        QuickPassPresentation.Conditions(
            canGuess: payload.canGuess,
            hasUnnamedCards: (store?.assignedCount ?? 0) < (store?.assignableCount ?? 0),
            isLocked: store?.isLocked ?? false,
            unsealHasRun: unseal?.hasFinishedScheduling ?? false,
            arrivedFromLink: env.router.arrivedFromRoundLink,
            alreadyOfferedThisRound: env.flags.hasOfferedQuickPass(roundID: roundID)
        )
    }

    private func offerQuickPassIfNeeded(_ conditions: QuickPassPresentation.Conditions) {
        guard !quickPassPresented, QuickPassPresentation.shouldPresent(conditions) else { return }
        // Recorded whichever clause let it through, so the *once otherwise* clause is true of an
        // arrival that came from a link too — a person handed the cover by a notification has
        // been offered it, and should not be handed it again by their next ordinary foreground.
        _ = env.flags.beginQuickPass(roundID: roundID)
        env.router.clearArrivedFromRoundLink()
        quickPassPresented = true
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

    /// Whether this phase's screen draws the round's **date** itself, as the eyebrow over its own
    /// headline, rather than being given `RoundHeader`'s pinned second row.
    ///
    /// The same two phases as `bleedsToScreenEdge`, and not by coincidence — it is the same fact
    /// about them, reached from the other side: these are the two that scroll, and a pinned row
    /// only earns its height from something that changes while somebody is reading. On `open` that
    /// is the badge — *"SEALS IN 01:29:25"* — and the date rides along beside it, one thought.
    /// On `revealed` and `scored` `badge(store:timer:)` is `EmptyView`: the reveal draws its own
    /// countdown in its scrolled header and the answers count to nothing at all. So the row was a
    /// pinned strip holding one short date, above the only two screens where pinned height is paid
    /// for out of the list.
    ///
    /// **And it was the same fact twice across the seam.** The line said *"Saturday, September 5"*
    /// two lines above a headline that says *"Tonight's drop"*. Inside the scroll they are one
    /// block — eyebrow, headline — which is what they always were.
    ///
    /// Kept a separate property from `bleedsToScreenEdge` rather than folded into it because the
    /// two say different things about a phase, and a fifth phase could easily want one without the
    /// other; `RoundHeader` needs no new "is the row empty" logic either way, since passing `nil`
    /// for the date is the loading header's existing path (`hasStanding`).
    var scrollsItsOwnDate: Bool {
        switch self {
        case .revealed, .scored: true
        case .open, .voided: false
        }
    }

    /// Whether this phase's screen renders the cue itself, rather than being given `RoundScreen`'s
    /// `CueBanner` above it.
    ///
    /// True for three phases, and the reason is the same one three times: the cue belongs to the
    /// column the screen is reading, not to a strip above it, so drawing it up there as well would
    /// be the same sentence twice.
    ///
    /// - `open` with nothing dropped — the drop screen, where the cue is the brief for the field
    ///   directly beneath it, as a `CueCard`. (This also covers the dark hours, which are that
    ///   phase; there `SubmitScreen` draws *last* night's cue, which the banner could not have
    ///   drawn anyway, since it reads the coming round's.)
    /// - `scored` — the answers, where the cards below the cue are the room's replies to it
    ///   (owner, 2026-09-03). `ResultsScreen` draws that card from the results payload's own
    ///   `cue`, which is the same round's.
    /// - `revealed` — the flight, where it keeps the `CueBanner` treatment but moves *inside* the
    ///   scroll, under the count (owner, 2026-09-06). Pinned, it was a two-line strip standing
    ///   permanently over a list it has nothing further to say to: the cue is the brief you read
    ///   once before the cards, and a brief is the last thing before the work, not a header on it.
    ///   Same placement argument `CueCard` already makes on the drop screen — last thing read
    ///   before the field — with the cards in the field's place. `RevealScreen` draws it.
    ///
    /// It sits here rather than as a predicate on `RoundScreen` for the reason its two siblings
    /// do: the mistake it guards against is invisible to every golden in the suite — a cue drawn
    /// twice, or not at all, is a fact about the *container*, and every snapshot renders a screen
    /// without one. `RoundChromeTests` asserts all three against the screens' own source, which is
    /// only possible for something the tests can actually read.
    ///
    /// `.open`'s answer is derivable from the phase alone because the phase carries the
    /// submission: there is nothing here that needed the store.
    var drawsItsOwnCue: Bool {
        switch self {
        case let .open(mySubmission): mySubmission == nil
        case .revealed, .scored: true
        case .voided: false
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
    /// most of its artwork in the cache the flight above it filled. Handed to `ResultsStore`,
    /// which is the one place the share entry is built (`ResultsStore.shareEntry`) — this host no
    /// longer builds one of its own.
    @Environment(\.artworkLoader) private var artworkLoader

    let context: RoundContext
    let loadToken: Int
    /// The app's one preview player (`docs/06` §4), shared with Submit and the reveal flight so
    /// starting a preview here stops whatever either of those had going.
    let player: PreviewPlayer

    @State private var store: ResultsStore?
    @State private var resolve: ResolveAnimation?

    private var roundID: String { context.round.id }

    var body: some View {
        Group {
            if let store {
                ResultsScreen(
                    state: store.viewState(resolve: resolve),
                    // The night, over the headline — the pinned row that used to carry it is
                    // withheld on this phase (`Phase.scrollsItsOwnDate`).
                    dateHeadline: context.dateHeadline,
                    // Withdrawn once the sequence has landed, so a scroll through settled
                    // answers is a plain scroll and not a gesture with a handler on it.
                    skipResolve: resolve?.isRunning == true ? { resolve?.skip() } : nil,
                    player: player
                )
            } else {
                // One runloop, before the store exists. `docs/08` §10 gives loading a skeleton
                // and no spinner; `RoundScreen` has already drawn one for the round itself.
                Color.clear
            }
        }
        .task(id: "\(roundID)#\(loadToken)") {
            let built = store ?? ResultsStore(
                api: env.api, roundID: roundID, circles: env.circles, artworkLoader: artworkLoader
            )
            store = built
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
            store?.discardShareRender()
        }
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
    /// The same date, abbreviated. The middle rung of `standing`'s ladder: when the full date and
    /// the badge cannot share a row, this usually can, and one short row beats two.
    let shortDateHeadline: String?
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
        shortDateHeadline: String? = nil,
        path: Binding<[Route]>,
        showHowTo: @escaping () -> Void,
        openSwitcher: @escaping () -> Void,
        otherCircleNeedsAction: Bool = false,
        @ViewBuilder badge: () -> Badge = { EmptyView() }
    ) {
        self.groupName = groupName
        self.dateHeadline = dateHeadline
        self.shortDateHeadline = shortDateHeadline
        self._path = path
        self.showHowTo = showHowTo
        self.openSwitcher = openSwitcher
        self.otherCircleNeedsAction = otherCircleNeedsAction
        self.badge = badge()
    }

    /// **Who on the first line; when and what-it-is-doing sharing the second.**
    ///
    /// The badge once sat in the top row between the name and the menu, which was wrong for the
    /// one phase whose badge is wide: *"Seals in 04:12:33"* is a dozen characters that
    /// `.fixedSize()` will not give up, so the group name — the only thing on that row that
    /// *can* yield — absorbed the whole cost. It then moved to a third row of its own, which
    /// was correct and expensive: three rows of chrome over a search screen whose keyboard is
    /// already up is a lot of header for two short facts.
    ///
    /// So it is two rows now. The name shares the first only with the menu — one glyph, fixed
    /// width, nothing to negotiate. The date and the badge share the second, which is the
    /// **full** column width because the menu is not on it: *when* the round is and *what it is
    /// doing* are one thought, and they read as one line, the date leading and the badge held
    /// out at the trailing edge.
    ///
    /// **They only share it while they both fit.** `ViewThatFits` measures the row's ideal width
    /// — the date, `Space.sm`, the badge, because `Spacer(minLength:)`'s ideal width *is* its
    /// minimum — and drops to the stacked pair the moment that exceeds the column. That is the
    /// narrow iPhone at a large type size, and it is the same reflow `CueBanner` and `FlightCard`
    /// already make; measuring rather than testing the type size means a long group date in a
    /// wider locale gets the same protection without anybody having to predict it.
    ///
    /// The gaps are the stacks' own rather than `.padding` on the badge, because three of the
    /// five phases pass no badge at all: `EmptyView` contributes no subview, so the row's
    /// spacing around it collapses to nothing and a badgeless phase gets a plain date line,
    /// whereas a padded empty view would reserve its padding and leave a gap either side.
    var body: some View {
        // `Space.none`, with the rule below carrying both of its own gaps. The stack's own
        // spacing cannot express what this block needs: the name row is a 44pt touch target
        // around a 20pt line, so a symmetric gap lands the rule a dozen points further from the
        // name than from the date and reads as a line over the date rather than under the name.
        VStack(alignment: .leading, spacing: Space.none) {
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
                    // The Record keeps its `Route` and its deep link — only this entry point
                    // moved, to the foot of the Group screen (`E28-06`, amendment A3): a
                    // list of songs is company for a leaderboard, not a peer of the three
                    // things this menu is actually for.
                    Button { path.append(.group) } label: {
                        Label("group.title", systemImage: "person.3")
                    }
                    Button { path.append(.insights) } label: {
                        // Not `eye` (`E28-06`) — nothing on this screen is watching anyone.
                        // Three linked points is what the screen is actually about.
                        Label("insights.title", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    Button { path.append(.settings) } label: {
                        Label("settings.title", systemImage: "gearshape")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(Font(Typography.uiFont(.bodyLStrong)))
                        .foregroundStyle(Palette.inkDim)
                        // A fixed frame, not a `min` one (`E32-02`). `Menu` renders its label
                        // through a UIKit platform node, and a label sized by a *minimum* is
                        // one SwiftUI is free to re-measure during the navigation pop; pinning
                        // the label to an explicit 44×44 box keeps it a stable, already-measured
                        // view, so the transition moves it with the rest of the header instead
                        // of re-laying it out mid-slide.
                        .frame(width: Layout.minimumTouchTarget, height: Layout.minimumTouchTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text("menu.title"))
            }

            // The rule between who you are looking at and what the round is doing. It is the
            // only hairline in the app's chrome and it earns its place by making the two-row
            // header two *things* — the circle and its menu above, tonight's facts below —
            // rather than four items in a stack. `hairline` and not `edgeStrong`: a divider
            // inside a block, not the edge of one.
            //
            // It is `accessibilityHidden` because it is a mark, not a stop, and it draws only
            // when something is under it: on the loading header, where `standing` is empty, a
            // rule would be a line under the circle's name and nothing else.
            if hasStanding {
                // Close under the name row, clear above the date — the same pair of gaps the
                // chrome's own rule uses on the phases that scroll, so the two rules sit the
                // same way whichever phase drew them (owner, 2026-09-07).
                Rule()
                    .padding(.top, Space.xs)
                    .padding(.bottom, Layout.itemGap)
            }

            standing
        }
    }

    /// Whether the second row has anything on it — the date, or a badge without one.
    ///
    /// `dateHeadline` is the whole test in practice: the only header with a badge and no date is
    /// the loading one, which has neither. Written as its own property so the rule above and
    /// `standing` below cannot disagree about what "empty" means.
    private var hasStanding: Bool { dateHeadline != nil }

    /// The date and the badge, side by side while the column can hold both.
    ///
    /// **Three rungs, tried in order: the full date beside the badge, the abbreviated date
    /// beside it, then the two stacked.** The middle rung is the one that earns its keep. One
    /// step above the default type size, *"Tuesday, September 1"* and *"SEALS IN 01:29:25"* are
    /// together wider than a 393pt column — so the first rung fails on an ordinary phone at an
    /// ordinary setting, and without a rung between, the header went straight back to the three
    /// rows this change was made to remove. *"Tue, Sep 1"* beside the badge is one row again,
    /// and it is still the whole date rather than a truncated anything.
    ///
    /// `Spacer(minLength:)` is what makes the measurement honest — its ideal width is
    /// `Space.sm`, so `ViewThatFits` weighs *date + gap + badge* against the column rather than
    /// seeing an infinitely compressible row and always taking the first candidate.
    ///
    /// **It does not flicker as the clock ticks.** The badge's precise form is `HH:MM:SS` in
    /// tabular figures, so its width is fixed for the whole evening; the coarse form that would
    /// change it (*"4 hours"*) only appears above `.accessibility2` (`docs/12` §1), by which
    /// point the row has long since stacked and there is nothing left to re-measure.
    ///
    /// The stacked rung keeps the **full** date: it has a whole row, so there is nothing to buy
    /// by shortening it.
    ///
    /// **The `else` is not a formality.** `ViewThatFits` is a real subview whether or not
    /// anything inside it draws, so wrapping the empty case in one would cost the outer stack's
    /// `Space.sm` on a header with nothing to put on this row — which is the header the loading
    /// state renders, on every cold launch and every foreground refetch, for as long as the
    /// round takes to arrive. Falling through to the bare `badge` instead keeps the old
    /// behaviour exactly: an `EmptyView` contributes no subview, so the spacing collapses and
    /// the loading header is the name row and nothing else. It also means a caller that ever
    /// passes a badge without a date still gets its badge drawn rather than silently dropped.
    @ViewBuilder private var standing: some View {
        if let dateHeadline {
            ViewThatFits(in: .horizontal) {
                row(dateHeadline)
                // Only offered when it is actually shorter. A locale whose abbreviation is the
                // same string as the long form would otherwise get a second identical candidate
                // — harmless, but it would sit in the ladder pretending to be a way out.
                if let shortDateHeadline, shortDateHeadline.count < dateHeadline.count {
                    row(shortDateHeadline)
                }
                VStack(alignment: .leading, spacing: Space.sm) {
                    date(dateHeadline)
                    badge
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            badge
        }
    }

    /// One rung: a date at the leading edge, the badge held out at the trailing one.
    private func row(_ headline: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            date(headline)
            Spacer(minLength: Space.sm)
            badge
        }
    }

    /// *When* the round is. `caption` rather than `bodyS` so it reads as apparatus beside the
    /// badge's mono caps rather than competing with them — the treatment lives in
    /// `RoundDateline`, which the two scrolling phases draw for themselves.
    ///
    /// Always spoken as the full date, whichever rung is drawn.
    private func date(_ headline: String) -> some View {
        RoundDateline(headline: headline, spoken: dateHeadline ?? headline)
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

/// Which sheet the switcher is handing over to once it has finished dismissing (`E38-04`).
private enum SwitcherExit {
    case startGroup
    case joinWithCode
}

/// The join-by-code sheet's presentation, carrying the code it opens with (`E38-02`).
///
/// `Identifiable` and presented with `.sheet(item:)` rather than a `Bool` plus a separate
/// `@State` for the code: the two doors into this sheet — the switcher's footer and a `/j/<CODE>`
/// link — differ only in what the field starts with, and a flag with a value beside it is two
/// things that can disagree about whether the sheet is up.
private struct JoinPrompt: Identifiable {
    let code: String
    /// The code is the identity: a second link, for a different circle, arriving while the sheet
    /// is up should re-present it with the new code rather than be swallowed as "already showing".
    var id: String { code }
}
