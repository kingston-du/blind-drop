import SwiftUI

/// Everything `RevealScreen` draws, as a value (`docs/13` §2).
///
/// A struct rather than the `RoundDTO` itself, for two reasons. The screen needs a *name* for
/// each guess and the wire carries a `guessed_user_id`; resolving one to the other — including
/// the `Sam B.` / `Sam K.` disambiguation of `docs/08` §6 — is `E11-03`'s job, and doing it
/// here would put it in the view. And a value with no network in it is a value a snapshot can
/// be taken of, which is how the 6-card and 12-card layouts get held still.
///
/// `E11-02` adds the store that builds this from a `RevealPayload`.
struct RevealViewState: Equatable, Sendable {

    /// The round's cards, **in the order the server sent them**.
    ///
    /// Not sorted here, and that is deliberate. `card_no` *is* the shuffle (`E03-04`): the
    /// server assigns it once per round and every member sees the same one, which is what makes
    /// "No. 4" a thing two people in a group can say to each other. The order is already
    /// ascending when it arrives, and a client-side `sorted()` would be a second opinion about
    /// a fact the client does not own. `RevealScreenTests` asserts the rendering order matches
    /// the array, and the fixture asserts the array is ascending.
    let cards: [CardDTO]

    /// The caller's own card, or `nil` when they did not drop tonight.
    ///
    /// The card itself stays in `cards` — *"your own card is displayed (the numbering must not
    /// have a hole)"* (`docs/08` §6). What this number does is take the chip off it.
    let myCardNumber: Int?

    /// Whether the caller may guess at all (`docs/04` §4). `false` for a non-submitter and for
    /// someone who joined after the reveal; `E11-05` renders the reason.
    let canGuess: Bool

    /// The caller's current sheet: card number → the name shown on that card's chip. Resolved
    /// and disambiguated upstream, so the view renders a string and decides nothing.
    let guesses: [Int: String]

    /// When the answers land. The reveal screen counts to `scores_at`, not to `reveals_at` —
    /// the reveal has already happened by the time anybody is looking at this.
    let answersAt: Date

    init(
        cards: [CardDTO],
        myCardNumber: Int?,
        canGuess: Bool,
        guesses: [Int: String] = [:],
        answersAt: Date
    ) {
        self.cards = cards
        self.myCardNumber = myCardNumber
        self.canGuess = canGuess
        self.guesses = guesses
        self.answersAt = answersAt
    }

    /// What card number `number` says about the caller's guess.
    ///
    /// The order of these branches is the whole rule, so it is written once here rather than
    /// four times in a `ForEach`:
    ///
    /// 1. **Own card first.** It is `.mine` whether or not the caller can guess, because it is
    ///    theirs either way and *"your card is still your secret"* (`docs/08` §6).
    /// 2. **Then the blocked case.** A non-submitter gets `.unavailable`, which draws no chip at
    ///    all — there is nothing to enable, so a disabled-looking chip would be a lie about a
    ///    control that is never coming.
    /// 3. **Then the sheet.**
    func assignment(for number: Int) -> FlightCard.Assignment {
        if number == myCardNumber { return .mine }
        guard canGuess else { return .unavailable }
        if let name = guesses[number] { return .guessed(name: name) }
        return .unguessed
    }

    /// `docs/08` §6's *"8 songs"*. The count of cards, which is `S` — and it is safe to print
    /// here and nowhere earlier: the round is `revealed`, so the submitter count stopped being
    /// a secret at the moment the cards did (`docs/14` §3).
    var songCount: Int { cards.count }
}

/// `docs/08` §6 — the reveal, as far as `E11-01` builds it: the status line and the flight of
/// cards. The guess interaction is `E11-02`, the name pool `E11-03`, the unseal `E11-04`, and
/// the non-submitter treatment `E11-05`.
///
/// Accent **ultramarine**, decided once here and handed down (`CLAUDE.md` §2.5). The one amber
/// on this screen is the *"Yours"* label `FlightCard` draws for `.mine`, which is the exception
/// `docs/08` §6 names and the reason it is named: the caller's own song is the one thing on a
/// revealed screen that is still sealed.
struct RevealScreen: View {
    let store: RevealStore
    let timer: CountdownTimer
    /// The night, drawn as the eyebrow over the headline. `nil` in the goldens that are about the
    /// flight rather than about the chrome, and on any caller that has no round context to hand.
    ///
    /// It lives here rather than in `RoundHeader`'s pinned row because on this phase that row held
    /// nothing else — the badge beside it is `EmptyView`, this screen counting to the answers in
    /// its own header instead. `RoundDTO.Phase.scrollsItsOwnDate` carries the full argument.
    var dateHeadline: String? = nil
    /// Tonight's cue, under the count. `nil` on an uncued night, and `CueBanner` draws nothing.
    var cue: CueDTO? = nil
    var groupInitial = ""
    var unseal: UnsealAnimation? = nil
    var player: PreviewPlayer? = nil

    private var state: RevealViewState { store.viewState }

    /// Ties each card to its rotor entry. The entries are declared on the `ScrollView` and the
    /// cards are built further down the tree, so the namespace is what pairs the two — it is how
    /// VoiceOver jumps to No. 11 on a twelve-card reveal, and how the scroll view knows to bring
    /// it into view when it does.
    @Namespace private var songs
    @State private var callSheetDetent: CallSheetDetent = .peek
    @State private var callSheet = CallSheetMetrics()
    @State private var scrollTarget: Int?
    /// Each card's frame in the `"reveal-flight"` coordinate space, last reported by
    /// `RevealCardFrames`. Held so `occludedByOpenSheet` changing — which is not itself a card
    /// frame changing — can still recompute visibility against it. See the `onChange` in `flight`.
    @State private var cardFrames: [Int: CGRect] = [:]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.blindDropForcesReducedMotion) private var forceReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || forceReduceMotion }
    /// Set only by `snapshotContent(typeSize:)`. See `effectiveTypeSize`.
    ///
    /// Not `fileprivate` — unlike `GuessSheet`'s equivalent field, `RevealScreen` has no explicit
    /// `init` of its own, so every call site (`RoundScreen.swift`, in a different file) relies on
    /// the compiler-synthesized memberwise one. That synthesized init takes the narrowest access
    /// level among the stored properties it covers; a `fileprivate` one here would have dragged
    /// the whole initializer down to `fileprivate` and made `RevealScreen(...)` uncallable from
    /// outside this file.
    var typeSizeOverride: DynamicTypeSize?
    /// Opens the quick pass (`E41-01`). Owned by `RevealHost`, which is what can present a cover.
    var startQuickPass: (() -> Void)?

    private let accent = PhaseAccent.revealed

    /// The type size `header` reflows against.
    ///
    /// `@Environment` is only populated on a view SwiftUI itself instantiated. `body` gets there
    /// the ordinary way — SwiftUI binds the environment before calling it — but the snapshot
    /// path does not: it reads `snapshotContent` directly off a `RevealScreen` *value*, which
    /// evaluates `header` (and the `isStacked` branch it picks) as a plain Swift property access,
    /// before `SnapshotRenderer` ever attaches `.dynamicTypeSize(_:)` to the result. `dynamicTypeSize`
    /// there is whatever the property's default happens to be — `.large` — so a golden labelled
    /// `accessibility5` quietly rendered the `large` row, badge and all, squeezing the title into
    /// the fragment of the row `Spacer(minLength:)` left it. `GuessSheet.effectiveTypeSize`
    /// documents the same trap; `snapshotContent(typeSize:)` is the fix here.
    private var effectiveTypeSize: DynamicTypeSize { typeSizeOverride ?? dynamicTypeSize }

    /// `FlightCard`, `ResultsScreen` and `StandingsView` all draw the same line at
    /// `.accessibility1`, and this row belongs on the same side of it.
    private var isStacked: Bool { effectiveTypeSize >= .accessibility1 }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                flight
                    // The flight keeps a constant landing strip. The open sheet overlays it
                    // rather than resizing it, so a twelve-card list never relays out mid-drag.
                    .safeAreaInset(edge: .bottom, spacing: Space.none) {
                        Color.clear.frame(height: callSheet.peek)
                    }
                GuessSheet(
                    store: store,
                    availableHeight: proxy.size.height,
                    bottomInset: proxy.safeAreaInsets.bottom,
                    detent: $callSheetDetent,
                    onMetrics: { callSheet = $0 },
                    lockIn: { callSheetDetent = .peek },
                    startQuickPass: startQuickPass
                )
            }
            // The panel is a bottom surface, not a safe-area-sized card. Extending this stack
            // through the home-indicator region removes the paper seam beneath both detents.
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .background(Palette.paper)
        // `docs/12` §2: *"Assigning a guess posts an `.announcement`"*. Posted here rather than
        // from the store so the store stays free of UIKit — and cleared immediately, because an
        // announcement that stays set would fire again on the next unrelated redraw.
        .onChange(of: store.announcement) {
            guard let announcement = store.announcement else { return }
            AccessibilityNotification.Announcement(announcement).post()
            store.consumeAnnouncement()
        }
        // **The flight follows the focus, not just the tap.** Assigning a name advances the store
        // to the next unassigned card (`docs/08` §6), and until this existed the screen did not
        // go with it: the ring moved to a card that was often below the open sheet, so every
        // second name meant scrolling to find out where the interaction had gone. Driving the
        // scroll from `focusedCard` rather than from the card tap covers both directions into
        // `assign(_:to:)`, which is the same reason the store puts them through one function.
        .onChange(of: store.focusedCard) { _, card in scrollTarget = card }
        .task {
            // Both of this screen's notes, warmed before either can fire.
            store.prepareHaptics()
            await unseal?.run(reducedMotion: reduceMotion)
        }
        .onDisappear {
            player?.stop()
            store.cancelPendingSave()
        }
    }

    /// How much of the flight an **open** sheet stands in front of.
    ///
    /// Zero at peek, where the reserved inset already accounts for everything on screen.
    private var occludedByOpenSheet: CGFloat {
        callSheetDetent == .open ? callSheet.occluded : Space.none
    }

    /// Recomputes which cards are actually on screen and tells `unseal` — the one call site
    /// both the frame-preference change and the sheet-occlusion change route through, so the two
    /// triggers can never disagree about how the bounds are built.
    private func updateVisibleCards(viewportSize: CGSize) {
        let bounds = CGRect(
            origin: .zero,
            size: CGSize(
                width: viewportSize.width,
                height: max(0, viewportSize.height - occludedByOpenSheet)
            )
        )
        unseal?.updateVisibleCards(Set(cardFrames.compactMap { number, frame in
            frame.intersects(bounds) && frame.width > 0 && frame.height > 0 ? number : nil
        }))
    }

    private var flight: some View {
        GeometryReader { viewport in
            ScrollViewReader { reader in
                ScrollView {
                    // The screen inset belongs to the scroll container, not to the column inside it
                    // (`docs/07` §4). Keeping it here is also what lets `content` be snapshot directly.
                    content
                        .padding(.horizontal, Layout.screenInset)
                        // **Clearance under the chrome's rule** (owner, 2026-09-07). The header
                        // draws a hairline across the bottom of the pinned block on exactly the
                        // phases that scroll, and the first thing under it is the dateline — a
                        // small caption whose own line box is nearly all cap height, so with no
                        // top margin it sat against the rule instead of beginning below it. The
                        // gap belongs to the scroll container rather than to `content`, for the
                        // same reason the inset does: it is about where the column starts
                        // relative to the chrome, not about the column's internal rhythm, and a
                        // golden of `content` should not carry it.
                        .padding(.top, Layout.itemGap)
                        // **What the open sheet covers has to stay reachable.** The flight
                        // reserves the *peek* height and nothing more, which is what keeps twelve
                        // cards from being re-laid-out on every frame of a drag (`E17-06`) — but
                        // on its own it also means the flight can only scroll as far as a
                        // collapsed sheet needs, and the last card or two sit permanently behind
                        // an open one. On the eight-card fixture No. 8 was not merely awkward to
                        // reach: it could not be brought into view at all.
                        //
                        // Trailing space on the scrolled column, which lengthens the scrollable
                        // extent without touching any card's geometry — the guarantee above
                        // survives. Not `contentMargins(.bottom, …, for: .scrollContent)`, which
                        // reads like the right tool and is not: it *replaces* the margin the
                        // bottom safe-area inset already contributes rather than adding to it, so
                        // it hands back with one hand what the inset gave with the other and
                        // No. 8 stays exactly where it was. And keyed off the settled detent
                        // rather than the live drag, so it changes once per transition instead of
                        // sixty times a second.
                        .padding(.bottom, occludedByOpenSheet)
                }
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(Motion.CallSheet.spring) {
                        // The top anchor keeps the focused card above the open sheet without
                        // changing the flight's layout while the sheet animates over it.
                        reader.scrollTo(target, anchor: .top)
                    }
                }
            }
            .coordinateSpace(name: "reveal-flight")
            .onPreferenceChange(RevealCardFrames.self) { frames in
                cardFrames = frames
                updateVisibleCards(viewportSize: viewport.size)
            }
            // **The sheet opening is also a bounds change, not only a scroll.** The preference
            // above fires when a card's *frame* changes, which is scroll-driven — tap the peek
            // header open with no card focused, and nothing scrolls, so nothing would have
            // recomputed which cards the now-open sheet covers. `unseal.updateVisibleCards` would
            // have kept running against the bounds from before the sheet opened, and a card
            // scheduled to unseal in that window could release while genuinely hidden behind it.
            // Recomputing here, off the settled detent, closes the other half of what the padding
            // above already does for scrolling.
            .onChange(of: occludedByOpenSheet) { _, _ in
                updateVisibleCards(viewportSize: viewport.size)
            }
            // `docs/12` §2: *"reveal cards form a custom rotor 'Songs' so a VoiceOver user can
            // jump between numbers directly"*.
            .accessibilityRotor("a11y.rotor.songs") {
                ForEach(state.cards) { card in
                    AccessibilityRotorEntry(
                        Text(verbatim: Copy.format("a11y.rotor.song", card.cardNumber)),
                        id: card.cardNumber,
                        in: songs
                    )
                }
            }
        }
    }

    /// The screen without its scroll container.
    ///
    /// Separated for the snapshots, and the reason is not convenience. A `ScrollView` is greedy:
    /// asked for its ideal height it answers with whatever it was offered, so a golden taken of
    /// one is a picture of a fixed rectangle with the rest of the flight clipped off the bottom.
    /// Rendering the content directly gives an image as tall as twelve cards actually are, which
    /// is the only form in which *"nothing truncates and nothing overlaps"* (`docs/12` §1) is a
    /// thing a diff can show.
    private var content: some View {
        flightContent(includeRotorEntries: true)
    }

    /// The same flight content without namespace-backed rotor entries.
    ///
    /// Snapshot tests render this outside `body`; reading an `@Namespace` there is invalid and
    /// produces identifiers that can never match. The production path above keeps the rotor,
    /// while this path isolates the purely visual layout the goldens are meant to verify.
    ///
    /// Takes the type size directly, for the same reason `GuessSheet.content(layout:typeSize:)`
    /// does: reading it here off `@Environment` instead would see `effectiveTypeSize`'s default
    /// rather than whatever `SnapshotRenderer` asked for — see `effectiveTypeSize`.
    func snapshotContent(typeSize: DynamicTypeSize = .large) -> some View {
        var copy = self
        copy.typeSizeOverride = typeSize
        return copy.flightContent(includeRotorEntries: false)
    }

    private func flightContent(includeRotorEntries: Bool) -> some View {
        // A plain `VStack`, not a `LazyVStack`. A group runs to **twelve members** (`docs/02`),
        // so the whole flight is twelve cards at the absolute most — laziness would save nothing
        // and costs two real things: a lazy stack builds no off-screen row, which is exactly the
        // row the "Songs" rotor has to be able to jump to, and it mis-reports its height to
        // `ImageRenderer`, which clipped the first line off every golden until this changed.
        VStack(alignment: .leading, spacing: Space.sm) {
            header
            if store.isLocked { lockedPanel }
            cards(includeRotorEntries: includeRotorEntries)
        }
        .padding(.bottom, Layout.blockGap)
        // **The panel arrives on the same spring the sheet is already riding** (owner, approved).
        //
        // `lockIn()` is called from `GuessSheet.trailingStatus` outside any animation, so the
        // panel used to be inserted in a single frame — shoving the whole flight down by its
        // height while the sheet underneath sprang to peek from the same tap. One tap, two
        // motions, one of them a cut: the screen's one confirming moment was also the one place
        // it stuttered.
        //
        // Not a new set piece, and not a new row in `docs/09` §1's table: `Motion.CallSheet.spring`
        // is the spring the sheet already uses, so the two halves of the same gesture now move
        // together, and the table's last row — *everything else, iOS default spring* — is what
        // permits it. The same reasoning `Motion.QuickPass.advance` is written down under.
        //
        // Keyed on the value rather than wrapped around the call, so **every** path that flips
        // `isLocked` is covered — `changeAGuess()` removing the panel, and `failSave(_:)` doing
        // it from underneath a save that came back refused.
        //
        // `.opacity` alone, with no travel: the cards moving down is the layout animating on that
        // spring, which is the motion that says *room was made*. That also means there is no
        // reduced-motion branch to write — a crossfade is already what `docs/12` §4 asks a
        // reduced-motion animation to reduce to.
        .animation(Motion.CallSheet.spring, value: store.isLocked)
    }

    /// The night, *"Tonight's drop"*, the size of the flight, how long there is to place it, and
    /// the cue it was all played against.
    ///
    /// The countdown sits in a badge on the title's line rather than under it: it is the only
    /// thing in the header that changes while somebody is reading, and putting it in the corner
    /// means nothing in the column moves when it does.
    ///
    /// **The date and the cue arrived here from the pinned chrome** (owner, 2026-09-06). Both used
    /// to stand above the scroll view for the whole evening: the date on `RoundHeader`'s second
    /// row, the cue as a `CueBanner` between that row and this flight. Together they were most of
    /// a phone's worth of header over the one screen in the app that is a *list* — and neither had
    /// anything to say after the first read. The date is now the eyebrow over the headline, which
    /// is where it always belonged: *"Saturday, September 5"* two lines above *"Tonight's drop"*
    /// was the same fact stated twice across a seam. The cue is the last thing before the cards,
    /// the same position `CueCard` holds on the drop screen — brief, then the work.
    private var header: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            // The eyebrow rides at `Space.xs`, not the stack's `Space.sm`: the date and the
            // headline are one block — *when* this is, then *what* it is — and a full gap between
            // them would read as two facts that happen to be adjacent, which is exactly what the
            // pinned row it replaced looked like. Not `Space.xxs` either, which `CueBanner` can
            // afford between two small lines and a wrapped caption under a `displayL` cannot: at
            // `accessibility5` the date takes two lines of its own and the pair closes up.
            VStack(alignment: .leading, spacing: Space.xs) {
                if let dateHeadline {
                    RoundDateline(headline: dateHeadline)
                }
                // **The badge takes its own row at accessibility sizes.** Sharing one with the
                // title is right at ordinary sizes and catastrophic above `.accessibility1`: the
                // countdown is eight monospaced digits with no line to break on, so it claims the
                // row's whole width and leaves the title whatever is left — which at
                // `accessibility5` was four points, one wrapped letter of *"Tonight's drop"*, the
                // descender of a **p** floating under the date. The `Spacer`'s `minLength` cannot
                // prevent that; only not competing for the row can. Same `.accessibility1`
                // boundary as `FlightCard` and the standings.
                if isStacked {
                    title
                } else {
                    HStack(alignment: .center, spacing: Space.md) {
                        title
                        Spacer(minLength: Space.sm)
                        countdown
                    }
                }
            }
            // Outside the tight block, so it keeps the full gap from the title it was pushed off
            // the row by — and so the eyebrow's spacing does not follow it down here.
            if isStacked { countdown }
            songCount
            // **Last thing before the cards.** `CueBanner` renders nothing on an uncued night, so
            // the `if` is about the gap rather than the view: `Space.xs` on top of the stack's own
            // `Space.sm` sets the cue slightly apart from the count without making it a section,
            // and an uncued header should not pay for it.
            if let cue {
                CueBanner(cue: cue).padding(.top, Space.xs)
            }
        }
        // One element, so the title and the status line are one stop rather than three. The
        // countdown keeps its own `.updatesFrequently` announcement by staying a child of it, and
        // the cue keeps the single combined stop `CueBanner` gives itself.
        .accessibilityElement(children: .contain)
        .padding(.bottom, Space.sm)
    }

    private var title: some View {
        Text(verbatim: Copy.string("reveal.title"))
            .typeStyle(.displayL)
            .foregroundStyle(Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var songCount: some View {
        Text(verbatim: Copy.format("reveal.subtitle", state.songCount))
            .typeStyle(.bodyM)
            .foregroundStyle(Palette.inkDim)
    }

    private var countdown: some View {
        CountdownView(
            timer: timer,
            deadline: state.answersAt,
            accent: accent,
            // It counts to the answers, and it says so (`docs/11` — `a11y.countdown.answers`).
            announces: .answers,
            prominence: .badge
        )
    }

    /// *"Locked in."* — the one piece of state on this screen that is not a card.
    ///
    /// A wash panel rather than a line of text, because it is a change to what the whole screen
    /// is now for: the flight below it has stopped being a form and become a list to re-read
    /// while the clock runs out. The countdown is not repeated here; it is in the header, and
    /// two of the same number on one screen is two things to keep in sync.
    private var lockedPanel: some View {
        Text("reveal.locked.title")
            .typeStyle(.bodyLStrong)
            .foregroundStyle(Palette.ultramarineDeep)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(
                radius: Radius.panel,
                fill: accent.wash,
                border: accent.washEdge,
                inset: Layout.rowInset
            )
            .padding(.bottom, Space.sm)
            // See `flightContent(includeRotorEntries:)`: the crossfade, with the flight sliding
            // down around it on the spring the sheet is riding.
            .transition(.opacity)
    }

    /// The flight. A vertical stack, **never a grid** (`docs/07` §5).
    @ViewBuilder private func cards(includeRotorEntries: Bool) -> some View {
        ForEach(state.cards) { card in
            let cardView = FlightCard(
                number: card.cardNumber,
                track: card.track,
                accent: accent,
                assignment: state.assignment(for: card.cardNumber),
                // No preview URL means no control at all. When one exists, the shared player
                // keeps the reveal and submit flows to one sound at a time and never autoplays.
                preview: preview(for: card.track),
                // A card the caller cannot act on is not a button. `.mine` and `.unavailable`
                // both land here, from opposite directions: one is theirs already, the other is
                // never going to be theirs to fill in.
                // `scrollTarget` is not set here: `tapCard` moves `focusedCard`, and the
                // `onChange` above is the one place the flight is scrolled from.
                chooseGuess: store.isGuessable(card.cardNumber)
                    ? {
                        callSheetDetent = .open
                        store.tapCard(card.cardNumber)
                    }
                    : nil,
                clearGuess: store.isLocked || state.guesses[card.cardNumber] == nil
                    ? nil
                    : { store.clearGuess(on: card.cardNumber) },
                // Read-only (`docs/19` §8.2). The flight reflects what the caller marked in the
                // quick pass; it is not a second place to mark, and the caller's own card carries
                // nothing here because nothing in this phase can mark it.
                myReaction: store.reaction(on: card.cardNumber),
                unseal: unseal.map {
                    UnsealPresentation(
                        phase: $0.phase(for: card.cardNumber),
                        groupInitial: groupInitial,
                        reducedMotion: reduceMotion
                    )
                }
            )
            .id(card.cardNumber)
            .overlay(focusRing(on: card.cardNumber))
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: RevealCardFrames.self,
                        value: [card.cardNumber: proxy.frame(in: .named("reveal-flight"))]
                    )
                }
            }

            if includeRotorEntries {
                cardView.accessibilityRotorEntry(id: card.cardNumber, in: songs)
            } else {
                cardView
            }
        }
    }

    private func preview(for track: TrackDTO) -> TrackRow.Preview? {
        guard track.previewURL != nil, let player else { return nil }
        return TrackRow.Preview(isPlaying: player.playing == track.trackKey) {
            player.toggle(track)
        }
    }

    /// The focused card's `ultramarine` ring (`docs/08` §6).
    ///
    /// An overlay on the screen's side rather than a parameter on `FlightCard`, because focus is
    /// a fact about *this screen's* interaction and not about a card — `E12`'s results reuse the
    /// same card with no focus concept at all. Drawn on `Radius.card` so it sits exactly on the
    /// border it replaces.
    @ViewBuilder private func focusRing(on number: Int) -> some View {
        if store.focusedCard == number {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(accent.fill, lineWidth: Stroke.mark)
        }
    }
}

private struct RevealCardFrames: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
