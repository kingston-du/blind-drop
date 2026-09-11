import SwiftUI

/// One card, one tap, next (`E41-01`).
///
/// The guessing on-ramp. People drop a song reliably and do not guess, and the reason is not
/// motivation: dropping is one decision in a ten-hour window, guessing is `N − 1` decisions in a
/// two-hour evening slot, and the cost grows with the circle while the drop's stays flat. The
/// call sheet is the right screen for somebody who sits down with it at 20:05 — a simultaneous
/// assignment puzzle you can reason across — and the wrong one for somebody walking home. This is
/// the same `N − 1` decisions arranged as a ninety-second posture.
///
/// **It is a second view over the same `RevealStore`,** not a store of its own. Every tap goes
/// through the sheet's existing debounced whole-sheet save (`RevealStore.place(_:on:)`), so the
/// two surfaces cannot disagree about what the caller said and closing this mid-run loses nothing
/// — which is the property that lets Skip be cheap and lets the cover be dismissed at any point.
///
/// Exactly one accent, and it is ultramarine (`CLAUDE.md` §2.5): the round is `revealed` and the
/// information is out. The one amber thing on the flight — *Yours* on the caller's own card — is
/// not here at all, because their own card is not in the run.
struct QuickPassScreen: View {
    let store: RevealStore
    let timer: CountdownTimer
    var player: PreviewPlayer?
    /// Tonight's cue, drawn once on the close button's row above every card and the recap alike
    /// (`E41-04`). `nil` on an uncued night, and `CueBanner` draws nothing. One string for the
    /// whole run: it does not change card to card, which is what lets `cueReserve(availableWidth:)`
    /// settle the layout once instead of per card.
    var cue: CueDTO? = nil
    /// Dismiss. Called when the run ends and when the caller closes out of it.
    let onFinish: () -> Void

    @State private var sequence: QuickPassSequence
    /// The name currently filled ultramarine, for the ~100ms before the card leaves. The whole of
    /// the feedback that a tap registered, which is why the advance itself needs no extra beat.
    @State private var confirming: String?
    /// Which way the next card arrives from. Set immediately before the cursor moves, so the
    /// transition below reads it in the same update.
    @State private var isMovingBack = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var typeSizeOverride: DynamicTypeSize?
    private var effectiveTypeSize: DynamicTypeSize { typeSizeOverride ?? dynamicTypeSize }

    /// A grid column's floor, scaled, so the pool drops from three columns to two to one as the
    /// text grows rather than overlapping at a fixed count.
    @ScaledMetric(relativeTo: .body) private var poolColumnMinimum = Layout.quickPassPoolColumn

    private let accent = PhaseAccent.revealed

    /// - Parameter sequence: where the run starts. Defaults to a fresh one built off the store,
    ///   which is every production call site.
    ///
    ///   The goldens pass one because some states are only *reachable*, never constructible: a
    ///   recap showing a blank card requires that the person walked the run and skipped one, and
    ///   a store alone cannot say that — a blank card in a store is a gap the cursor would resume
    ///   *onto*. Handing the screen a sequence that has already been walked is how the snapshot
    ///   pictures the state a finger produces, rather than a state that only the fixture can.
    init(
        store: RevealStore,
        timer: CountdownTimer,
        player: PreviewPlayer? = nil,
        cue: CueDTO? = nil,
        sequence: QuickPassSequence? = nil,
        onFinish: @escaping () -> Void
    ) {
        self.store = store
        self.timer = timer
        self.player = player
        self.cue = cue
        self.onFinish = onFinish
        _sequence = State(
            initialValue: sequence ?? QuickPassSequence(
                cardNumbers: store.cards.map(\.cardNumber),
                isGuessable: store.isGuessable,
                isAssigned: { store.assignments[$0] != nil }
            )
        )
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                content(availableHeight: viewport.size.height, availableWidth: viewport.size.width)
                    .frame(minHeight: viewport.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Palette.paper)
        // **The confirm beat is structured, and it is the only thing that advances a tap.**
        //
        // It was an unstructured `Task` in `choose`, which was wrong twice. It outlived the
        // cover: tap a name, close before the 100ms elapses, and the closure still fired
        // `announceArrival()` into the shared store's queue — inverting `docs/12` §2's *never
        // moved in silence* into an announcement about a card nobody is on. And it raced Skip,
        // which sits directly under the chips: a name and then Skip inside the same 100ms ran
        // `advance()` twice for one intent, stepping the cursor two cards and dropping the one
        // between them unseen, on the screen whose whole pitch is one card at a time.
        //
        // Driven off `confirming` as the id, so SwiftUI owns the lifetime the way `UnsealAnimation`
        // already has it own the unseal's: dismissal cancels it, and a second tap supersedes the
        // first instead of queueing behind it.
        .task(id: confirming) {
            guard confirming != nil else { return }
            try? await Task.sleep(for: Motion.QuickPass.chipConfirm)
            guard !Task.isCancelled else { return }
            confirming = nil
            advance()
        }
        .onAppear {
            // Nothing to name — a non-submitter who reached this by some route that should not
            // exist. Leave rather than draw an empty apparatus; the flight is where `docs/08` §6
            // says they are shown what they missed, in full.
            if sequence.isEmpty { onFinish() }
        }
    }

    /// The screen without its scroll container.
    ///
    /// `ImageRenderer` asked for a `ScrollView` answers with whatever rectangle it was offered and
    /// clips the rest, so a golden taken of one is a picture of a fixed frame rather than of the
    /// layout. Same split, and the same reason, as `RevealScreen.snapshotContent(typeSize:)`.
    func snapshotContent(
        typeSize: DynamicTypeSize = .large,
        availableHeight: CGFloat,
        availableWidth: CGFloat
    ) -> some View {
        var copy = self
        copy.typeSizeOverride = typeSize
        return copy.content(availableHeight: availableHeight, availableWidth: availableWidth)
    }

    @ViewBuilder
    private func content(availableHeight: CGFloat, availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Space.none) {
            header
            if sequence.isComplete {
                recap
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            } else if let number = sequence.current, let card = card(number) {
                VStack(alignment: .leading, spacing: Space.none) {
                    numeral(number)
                    artwork(card, availableHeight: availableHeight, availableWidth: availableWidth)
                    lower(card, number: number, availableWidth: availableWidth)
                }
                // The whole card, including its number and its name pool, is replaced as one
                // thing. Keyed on the card number so SwiftUI treats an advance as an arrival
                // rather than as a title changing in place. `header` sits outside this stack on
                // purpose (see its own doc comment) so neither the close button nor the cue ride
                // this transition — they are the one thing on the run that does not change card
                // to card.
                .id(number)
                .transition(advanceTransition)
                // **And the gesture, because a glyph is not the only way anybody will try.** Swipe
                // right is the most learned gesture on the platform and it means exactly one
                // thing; `CloseButton`'s own doc comment carries the other half of the rule —
                // *"no gesture is the only way to do anything"* (`docs/12` §5) — which is why the
                // chevron exists and this is the shortcut rather than the mechanism.
                //
                // **Right only.** A left swipe would have to mean Skip, and an accidental one
                // would then drop a card silently on a screen where that is the worst thing that
                // can happen. Skip is a control you press on purpose.
                .gesture(backSwipe)
            }
        }
        .padding(.horizontal, Layout.screenInset)
        .padding(.bottom, Layout.blockGap)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Chrome

    /// The close button and, when there is one, tonight's cue (`E41-04`).
    ///
    /// **Stationary above both branches of `content(…)`,** not drawn inside either. It used to sit
    /// inside the card's own `VStack`, sliding off and back on every advance along with the
    /// numeral and the artwork — wrong for the one element on this screen that does not change
    /// card to card. A cue is the round's own standing condition, not something that arrives with
    /// card `04` and leaves with it; hoisting it here, once, above the `if`, is what stops it
    /// riding `advanceTransition` for no reason.
    ///
    /// **There is no countdown here.** One was drawn and taken out after looking at it: eight
    /// ultramarine monospaced digits in the top corner is a second focal point on a screen with
    /// one job, and the eye goes to the ticking thing before it goes to the numeral. A clock over
    /// a single card is also the per-card stopwatch this screen must never become — the run has
    /// no pace to keep, only a next card.
    ///
    /// The deadline is not lost. It is in the flight's own header, which is what this cover sits
    /// on top of, and `E41-02` puts it on the recap — the one screen in the run where *how long
    /// is left* is a thing somebody is actually deciding against.
    ///
    /// **The cue shares this row, filling what the close button does not use.** The row is already
    /// a full `Layout.minimumTouchTarget` with one 44pt glyph in it and an empty `Spacer` after —
    /// paid-for height the artwork's reserve has already been charged for. A `prominent`
    /// `CueBanner` takes that width, so a one-line cue costs the artwork nothing at all and the
    /// catalog's longest — 45 characters — costs it one extra line.
    ///
    /// It reached here the long way, and both wrong turns are worth keeping. It was first a
    /// `bodyS` capsule on this row, which is the same *position* and a different *thing*: fitting
    /// the cue into a gap meant the app's most incidental type — *"the line under a control"*
    /// (`Typography`) — and no label, so it read as a caption for a control that was not there,
    /// in a shape that hugged its own text and therefore aligned with nothing. Then it was
    /// `standard` on a full-width row of its own, which was legible and cost the artwork 64pt on
    /// every cued night — 340pt down to 276pt, and an SE pinned to
    /// `Layout.Artwork.quickPassRange`'s floor.
    ///
    /// What was wrong the first time was the type and the label, not the row. So the row comes
    /// back with the type raised instead of lowered (`displayS`, the size `CueCard` already sets
    /// the cue in) and the label dropped on purpose rather than to save space — `CueBanner`'s
    /// `prominent` note argues that part. Filling the remaining width rather than hugging gives
    /// it the column's trailing edge, which is the alignment the capsule never had.
    ///
    /// `.top` alignment, so a cue that wraps grows downward and leaves the close button where it
    /// has been on all eight sheets in the app. Only that wrap costs the artwork anything, and
    /// `cueReserve(availableWidth:)` works out whether it happens from the string itself — see its
    /// note for why deriving beats both measuring it and assuming the worst.
    ///
    /// **`@ViewBuilder`, not a `VStack` of its own** — its two rows flatten into `content(…)`'s
    /// outer `VStack` exactly as `chrome` used to sit there as a single child, rather than
    /// nesting a second container around them. An extra layer here rendered a byte for byte
    /// difference on an *uncued* golden (`QuickPass-recap`, 15ProMax at `accessibility5`, one
    /// device pixel taller) with no cue anywhere in the tree to explain it — the nesting itself
    /// was the whole cause, and the fix is not to add it.
    @ViewBuilder
    private var header: some View {
        HStack(alignment: .top, spacing: Space.md) {
            CloseButton(action: onFinish)
                .padding(.leading, -Space.xs)
            if let cue, !isStacked {
                CueBanner(cue: cue, density: .prominent)
            } else {
                Spacer(minLength: Space.md)
            }
        }
        .frame(minHeight: Layout.minimumTouchTarget, alignment: .top)
        // Above `.accessibility1` a `displayS` line beside a scaled touch target has no width
        // left to wrap into, so the strip takes the full column beneath the button instead — the
        // same boundary the recap already reflows its countdown at. The artwork is on
        // `Artwork.quickPassRange`'s floor at these sizes and the page scrolls regardless, so the
        // row it costs is not competing with anything.
        if let cue, isStacked {
            CueBanner(cue: cue, density: .prominent)
                .padding(.top, Space.sm)
        }
    }

    /// *"04 / 08"* — the flight position, in the display face (`docs/07` §3).
    ///
    /// The card's own number and the size of the flight, which is the game's identity for a song
    /// and the thing two people in a circle actually say to each other. Deliberately **not** a
    /// count of what is left to do: that is the number that turns an invitation into a chore, and
    /// `CLAUDE.md` §2.7 rules out the whole family it belongs to.
    ///
    /// The caller's own card is passed over silently, so this can read `03` and then `05`. The
    /// hole is the price of not spending a tap on a card nobody can name — and the flight behind
    /// still shows it in place, marked *Yours*.
    private func numeral(_ number: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Text(verbatim: String(format: "%02d", number))
                // `displayXL` already carries `Typography.displayMaximumScale`, which is the same
                // 1.6× ceiling `FlightCard`'s numeral rides for the same reason (`docs/12` §1):
                // uncapped at `accessibility5` a 56pt display figure is around 130pt and eats the
                // screen it is labelling.
                .typeStyle(.displayXL)
                .foregroundStyle(accent.mark)
            Text(verbatim: Copy.format("quickpass.of", sequence.flightSize))
                .typeStyle(.displayS)
                .foregroundStyle(Palette.inkFaint)
        }
        // No `.monospacedDigit()`. `Typography` already sets tabular figures on every display
        // style through the font descriptor, and the modifier replaces the resolved Bricolage
        // face — its axes and its 1.6× ceiling with it — with a system one. `FlightCard`'s
        // numeral carries the same warning for the same reason.
        .padding(.top, Space.lg)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Copy.format("a11y.quickpass.position", number, sequence.flightSize)
        )
    }

    // MARK: - The song

    /// The artwork, and it is the largest in the app.
    ///
    /// Its side is whatever the column has not already claimed, clamped into
    /// `Layout.Artwork.quickPassRange` and never wider than the column: five names leave room for
    /// the top of the range, eleven leave the bottom, and neither layout breaks.
    ///
    /// **Computed, not measured.** The first version read the lower block's height off a
    /// preference, which is the tidier-looking answer and the wrong one: a preference arrives
    /// *after* the first layout, so the artwork drew at its maximum and then jumped down to its
    /// real size on the frame after — on every card, eleven times a run. The pool's height is
    /// derivable instead. The column count falls out of the width and the scaled column floor,
    /// the row count falls out of the pool, and the arithmetic settles in one pass with nothing
    /// to observe.
    private func artwork(
        _ card: CardDTO,
        availableHeight: CGFloat,
        availableWidth: CGFloat
    ) -> some View {
        let columnWidth = max(availableWidth - Layout.screenInset * 2, 1)
        // The card's own candidates, not the whole pool — this screen shows four names, so the
        // block under the artwork is four names tall. The count is the same on every card of a
        // round (`RevealStore.shortlist(for:)`), so the artwork settles once and does not
        // resize as the run advances.
        let poolCount = store.shortlist(for: card.cardNumber).count
        let columns = poolColumns(count: poolCount, width: columnWidth)
        let rows = max(1, Int(ceil(Double(poolCount) / Double(columns))))
        let poolHeight = CGFloat(rows) * Layout.chipHeightLarge + CGFloat(rows - 1) * Space.sm
        let cueReserve = cueReserve(availableWidth: availableWidth)
        let side = min(
            min(
                max(
                    availableHeight - Layout.quickPassFixedChrome - cueReserve - poolHeight,
                    Layout.Artwork.quickPassRange.lowerBound
                ),
                Layout.Artwork.quickPassRange.upperBound
            ),
            columnWidth
        )
        return ArtworkView(card.track, size: Layout.Artwork.quickPass, fillsWidth: true)
            .frame(width: side, height: side)
            // **Centred, alone on this screen.** Everything else in the column shares one leading
            // edge, which is `docs/07` §4's layout law and is why the numeral, the title and the
            // pool all start at the same x. The artwork is the one element whose width is decided
            // by the *height* left over, so it is the one element that cannot be relied on to
            // reach the column's trailing edge — and a 320pt square left-aligned in a 382pt
            // column reads as a picture that failed to load the rest of itself. Centring makes
            // the slack symmetrical, which reads as a margin instead of as a mistake.
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, Space.xl)
            .accessibilityHidden(true)
    }

    /// What the cue's strip takes from the artwork — **nought on most nights.**
    ///
    /// The strip shares the close button's row, and that row was already charged to
    /// `Layout.quickPassFixedChrome`, so a cue that fits on one line beside the button is free and
    /// the square is exactly the size it is on an uncued night. Only the overhang costs anything:
    /// a cue long enough to wrap is a taller row, and the difference is what comes off the
    /// artwork.
    ///
    /// **Derived from the string, not measured off the view.** The alternative — read the strip's
    /// height back through a preference — is the mistake `quickPassFixedChrome`'s own note records:
    /// a preference arrives after the first layout, so the artwork draws large and jumps smaller a
    /// frame later. It is also unnecessary here in a way it is not for the pool, because the cue is
    /// **one string for the whole run**. It does not change from card `01` to card `02`, so there
    /// is exactly one answer per round and the type system already holds everything needed to work
    /// it out: the resolved face at the current content size, the width the strip is given, and
    /// `Typography.lineHeight`. `boundingRect` turns those into a line count in the same pass that
    /// lays the card out, with nothing to observe and nothing to settle.
    private func cueReserve(availableWidth: CGFloat) -> CGFloat {
        guard let cue else { return 0 }
        let column = max(availableWidth - Layout.screenInset * 2, 1)
        let category = UIContentSizeCategory(effectiveTypeSize)
        // Stacked, the strip has the whole column; beside the button it has what the 44pt target
        // and the row's own spacing leave. `Space.md * 2` is the strip's horizontal inset.
        let textWidth = isStacked
            ? column - Space.md * 2
            : column - Layout.minimumTouchTarget - Space.xs - Space.md * 3
        let font = Typography.uiFont(.bodyLStrong, for: category)
        let measured = (cue.text as NSString).boundingRect(
            with: CGSize(width: max(textWidth, 1), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        ).height
        let lines = max(1, Int((measured / font.lineHeight).rounded()))
        // `.frame(minHeight:)` in `CueBanner.strip` floors the inline strip at the touch target's
        // height so it and the close button share a centre — so the reserve has to floor it too,
        // or a one-line cue would look like it owed the artwork 8pt it does not.
        let strip = max(
            CGFloat(lines) * Typography.lineHeight(.bodyLStrong, for: category) + Space.sm * 2,
            Layout.minimumTouchTarget
        )
        // Stacked it is a whole extra row, gap included. Inline it costs only what it adds to a
        // row the reserve has already paid for — nothing at all, on a cue that does not wrap.
        return isStacked ? strip + Space.sm : max(0, strip - Layout.minimumTouchTarget)
    }

    private func lower(_ card: CardDTO, number: Int, availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Space.none) {
            track(card)
            pool(on: number, availableWidth: availableWidth)
            navigation
        }
    }

    private func track(_ card: CardDTO) -> some View {
        HStack(alignment: .top, spacing: Layout.itemGap) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(verbatim: card.track.title)
                    .typeStyle(.bodyLStrong)
                    .foregroundStyle(Palette.ink)
                Text(verbatim: card.track.artist)
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.inkDim)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.sm)
            if card.track.previewURL != nil, let player {
                PreviewControl(
                    isPlaying: player.playing == card.track.trackKey,
                    accent: accent
                ) {
                    player.toggle(card.track)
                }
            }
        }
        .padding(.top, Space.lg)
        .accessibilityElement(children: .combine)
    }

    // MARK: - The pool

    /// Names at tap scale.
    ///
    /// An adaptive grid rather than the call sheet's scrolling row: this pool is not apparatus
    /// under something else, it is the screen's one action, and a set of even targets is faster to
    /// hit than a ragged line you have to aim along. Three columns at ordinary sizes, two then one
    /// as the text grows — the column floor scales, so the count falls out of the type rather than
    /// out of a device check.
    ///
    /// A spent name stays struck through and stays tappable. The API permits naming one person
    /// twice (`docs/04` §4 rule 6) and the quick pass must not be stricter than the sheet it feeds.
    ///
    /// **The card's four, not the pool.** The same names the call sheet narrows to when this card
    /// is focused, so a player who starts here and finishes there is answering one question about
    /// one card rather than two differently-shaped ones.
    /// How many columns the pool draws in — **one derivation, two readers.** The grid lays the
    /// chips out and `artwork(_:availableHeight:availableWidth:)` reserves the height they will
    /// need, and the two agreeing is what stops the artwork resizing on the frame after the
    /// pool lands. An `.adaptive` grid could not be asked what it decided.
    ///
    /// **Four is a square.** The width fits three chips, so four used to draw as a row of three
    /// with a single name stranded underneath — which reads as a fourth option that arrived late
    /// rather than as one of four. Two columns of two is the same four names as a shape.
    private func poolColumns(count: Int, width: CGFloat) -> Int {
        let natural = max(1, Int((width + Space.sm) / (poolColumnMinimum + Space.sm)))
        if count == 4 { return min(2, natural) }
        return max(1, min(natural, count))
    }

    private func pool(on number: Int, availableWidth: CGFloat) -> some View {
        let members = store.shortlist(for: number)
        return LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(minimum: poolColumnMinimum), spacing: Space.sm),
                count: poolColumns(
                    count: members.count,
                    width: max(availableWidth - Layout.screenInset * 2, 1)
                )
            ),
            alignment: .leading,
            spacing: Space.sm
        ) {
            ForEach(members) { member in
                NameChip(
                    member: member,
                    displayName: store.displayNames[member.userID],
                    state: confirming == member.userID ? .selected : store.chipState(for: member),
                    action: { choose(member, on: number) },
                    allowsWrapping: true,
                    size: .large
                )
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, Layout.blockGap)
    }

    /// Skip, and it is a word.
    ///
    /// `docs/07` §5 names **Skip** as one of `SecondaryButton`'s three jobs, and that is the whole
    /// argument: a bordered pill beside a grid of bordered pills reads as one more name, however
    /// its border is dashed. Text-only removes the ambiguity outright — the only thing on the
    /// screen that is not a name does not look like one.
    ///
    /// It is not hidden and it is not apologised for. Once `E39` lands, an unfilled card is filled
    /// at chance rather than scored wrong, so a skip is an honest *I don't know* and must never be
    /// drawn as a failure. Centred on its own row, at the full 44pt target `SecondaryButton`
    /// already carries.
    /// The run's two navigation actions, sharing one row in the thumb's reach.
    ///
    /// **Back is a glyph, and it is here rather than in the chrome.** `CloseButton` is top-leading
    /// on all eight sheets in the app, so the corner a back control conventionally takes is spoken
    /// for, and putting one opposite it would read as *back* on the right. This row already
    /// exists, it is where the finger already is — a name chip is directly above it — and it puts
    /// the two ways of leaving a card next to each other, with Skip keeping the centre because
    /// moving on is the ordinary act and going back is the correction.
    ///
    /// Overlaid rather than laid out beside Skip, so Skip does not shift half a chevron sideways
    /// between card one and card two. Absent, not disabled, on the first card: a permanently dead
    /// control is furniture, and `01` in the numeral already says there is nothing behind it.
    private var navigation: some View {
        ZStack {
            // Refused while a name is confirming, for the same reason a second chip tap is: the
            // 100ms fill is a tap already in flight, and letting Skip land inside it advances
            // twice.
            SecondaryButton("quickpass.skip") {
                guard confirming == nil else { return }
                advance()
            }
            if sequence.canGoBack {
                HStack {
                    Button(action: goBack) {
                        Image(systemName: "chevron.backward")
                            .font(Font(Typography.uiFont(.bodyL, for: UIContentSizeCategory(effectiveTypeSize))))
                            .foregroundStyle(Palette.inkDim)
                            .minimumTouchTarget()
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("a11y.quickpass.back")
                    Spacer(minLength: Space.none)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Layout.itemGap)
    }

    // MARK: - Advancing

    private func choose(_ member: MemberDTO, on number: Int) {
        guard confirming == nil else { return }
        store.place(member.userID, on: number)
        // Setting this both draws the chip filled and starts the confirm beat above. The advance
        // is that task's, never this function's — one place decides the cursor moves.
        confirming = member.userID
    }

    private func advance() {
        isMovingBack = false
        withAnimation(Motion.QuickPass.advance(reducedMotion: reduceMotion)) {
            sequence.advance()
        }
        announceArrival()
    }

    /// No haptic, and Skip has none either.
    ///
    /// The one in this flow fires from `RevealStore.assign` when a name lands, and that is the
    /// rule worth keeping: the taptic marks a **commitment** — something now written on the sheet
    /// — not a change of screen. Back and Skip move the cursor and commit nothing, and a device
    /// that buzzes for navigation is a device that has stopped meaning anything by it.
    private func goBack() {
        guard confirming == nil, sequence.canGoBack else { return }
        isMovingBack = true
        withAnimation(Motion.QuickPass.advance(reducedMotion: reduceMotion)) {
            sequence.back()
        }
        announceArrival()
    }

    /// A VoiceOver user is never moved to a different card in silence (`docs/12` §2).
    private func announceArrival() {
        guard let number = sequence.current, let card = card(number) else { return }
        store.announce(
            Copy.A11y.card(
                number: number,
                title: card.track.title,
                artist: card.track.artist,
                guess: store.assignments[number].flatMap { store.displayNames[$0] }
                    .map { .assigned(name: $0) } ?? .none
            )
        )
    }

    /// Swipe right for the card behind this one.
    ///
    /// Horizontal-dominant by a clear margin, so it cannot be triggered while somebody is
    /// scrolling the page — which they are, at accessibility sizes, where the pool alone is
    /// taller than an SE.
    private var backSwipe: some Gesture {
        // `.global` for the same reason the call sheet's drag takes it (`E32-01`): a gesture read
        // in a local space is read against a view the animation is currently moving, so the
        // translation it reports chases its own transition.
        DragGesture(minimumDistance: Layout.quickPassBackSwipe, coordinateSpace: .global)
            .onEnded { value in
                guard confirming == nil, sequence.canGoBack else { return }
                guard value.translation.width > Layout.quickPassBackSwipe,
                      abs(value.translation.width) > abs(value.translation.height) * 1.5
                else { return }
                goBack()
            }
    }

    /// Forward or back, the transition takes the direction from the cursor's own.
    ///
    /// A card that always arrived from the trailing edge would make going back feel like going on
    /// — the one thing the motion has to say here is *which way*.
    private var advanceTransition: AnyTransition {
        // Reduced motion keeps the arrival and drops the travel (`docs/12` §4).
        guard !reduceMotion else { return .opacity }
        let arriving: Edge = isMovingBack ? .leading : .trailing
        let leaving: Edge = isMovingBack ? .trailing : .leading
        return .asymmetric(
            insertion: .move(edge: arriving).combined(with: .opacity),
            removal: .move(edge: leaving).combined(with: .opacity)
        )
    }

    private func card(_ number: Int) -> CardDTO? {
        store.cards.first { $0.cardNumber == number }
    }

    // MARK: - The recap (`E41-02`)

    /// *Here is what you said* — and the one screen in the run where the deadline belongs.
    ///
    /// The beat that makes the run finishable without ever touching the call sheet. A person who
    /// came in from a push, named five cards and locked in has done the whole night's guessing
    /// inside one cover, which is the difference between a shortcut and a detour.
    ///
    /// The countdown lives here rather than over every card. On a single card it is a per-card
    /// stopwatch and it takes the eye before the numeral does; here it is the thing somebody is
    /// actually deciding against — whether to lock in now or go back and change one.
    private var recap: some View {
        VStack(alignment: .leading, spacing: Space.none) {
            HStack(alignment: .firstTextBaseline) {
                Text("reveal.callsheet")
                    .typeStyle(.displayM)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !isStacked {
                    Spacer(minLength: Space.md)
                    countdown
                }
            }
            .padding(.top, Space.lg)
            if isStacked {
                countdown.padding(.top, Space.sm)
            }
            VStack(alignment: .leading, spacing: Space.none) {
                ForEach(store.cards) { card in
                    recapRow(card)
                    if card.cardNumber != store.cards.last?.cardNumber {
                        Rule()
                    }
                }
            }
            .padding(.top, Layout.blockGap)
            PrimaryButton("reveal.action", accent: accent, isEnabled: store.assignedCount > 0) {
                store.lockIn()
                onFinish()
            }
            .padding(.top, Layout.blockGap)
        }
    }

    private var countdown: some View {
        CountdownView(
            timer: timer,
            deadline: store.answersAt,
            accent: accent,
            announces: .answers,
            prominence: .inline
        )
    }

    /// One line of the sheet: the card's number, its artwork, its title, and what is written
    /// against it.
    ///
    /// **The title and the name do not share a row above `.accessibility1`.** An uncapped label
    /// beside another uncapped label starves one of them to nothing at large type — the title
    /// wraps to a letter a line while the name takes the row, or the reverse. They stack instead,
    /// which is the same reflow `FlightCard` and the reveal header already make at the same
    /// boundary.
    @ViewBuilder
    private func recapRow(_ card: CardDTO) -> some View {
        let isMine = card.cardNumber == store.myCardNumber
        let row = Group {
            if isStacked {
                // **The text gets the whole column above `.accessibility1`.** Sharing a line with
                // a numeral and a thumbnail leaves it about two hundred points, and at
                // `accessibility5` that is narrower than the word *Sickness* — so the title broke
                // mid-word, *"Motion / Sicknes / s"*. Nothing truncated, which is the letter of
                // `docs/12` §1, and a title snapped across a syllable is plainly not its spirit.
                // The identifying pair moves to its own line and the text takes the full width
                // underneath, where it can break between words like a sentence.
                VStack(alignment: .leading, spacing: Space.sm) {
                    HStack(alignment: .center, spacing: Layout.itemGap) {
                        recapNumeral(card)
                        ArtworkView(card.track, size: Layout.Artwork.recordRow)
                    }
                    Text(verbatim: card.track.title)
                        .typeStyle(.bodyM)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    recapVerdict(card, isMine: isMine)
                }
            } else {
                HStack(alignment: .center, spacing: Layout.itemGap) {
                    recapNumeral(card)
                    ArtworkView(card.track, size: Layout.Artwork.recordRow)
                    Text(verbatim: card.track.title)
                        .typeStyle(.bodyM)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: Space.sm)
                    recapVerdict(card, isMine: isMine)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Layout.rowInset)
        .contentShape(Rectangle())

        if store.isGuessable(card.cardNumber) {
            Button { jump(to: card.cardNumber) } label: { row }
                .buttonStyle(.plain)
                .accessibilityHint("a11y.quickpass.row.hint")
        } else {
            // The caller's own card is on the sheet because the sheet is the flight, and it is
            // not a control because there is nothing to change on it.
            row.accessibilityElement(children: .combine)
        }
    }

    /// **Ultramarine on every row, the caller's own included.** *Yours* beside it is amber, and
    /// that is the flight's already-argued exception to `CLAUDE.md` §2.5 — `docs/08` §6: *"the ONE
    /// place amber appears here, because your card is still your secret"*. The recap is the call
    /// sheet reached the other way round, so it inherits that exception at exactly the width it
    /// was granted and no wider. An amber numeral was drawn here first and taken out:
    /// `FlightCard` colours its number amber when a card is **sealed**, never because it is
    /// yours, so a second amber element would have been this screen widening a carve-out on its
    /// own authority.
    private func recapNumeral(_ card: CardDTO) -> some View {
        Text(verbatim: String(format: "%02d", card.cardNumber))
            .typeStyle(.numberM)
            .foregroundStyle(accent.mark)
    }

    /// What is written against a card: a name, *Yours*, or the em dash of a card left blank.
    ///
    /// The dash is `inkQuiet` — not `alert`, not amber. Once `E39` lands an unfilled card is
    /// filled at chance rather than scored wrong, so a blank is an honest *I don't know* and the
    /// recap must never draw it as a failure. Choosing the neutral treatment now means nothing
    /// here has to change when that arrives.
    @ViewBuilder
    private func recapVerdict(_ card: CardDTO, isMine: Bool) -> some View {
        if isMine {
            Text("reveal.card.mine")
                .typeStyle(.bodyM)
                .foregroundStyle(Palette.amberText)
        } else if let name = store.assignments[card.cardNumber].flatMap({ store.displayNames[$0] }) {
            Text(verbatim: name)
                .typeStyle(.bodyLStrong)
                .foregroundStyle(accent.mark)
        } else {
            Text("quickpass.recap.blank")
                .typeStyle(.bodyM)
                .foregroundStyle(Palette.inkQuiet)
        }
    }

    private func jump(to cardNumber: Int) {
        // **Backwards, because it is.** The recap sits at the far right of the run, and a row
        // tapped there is a correction to a card behind it — so the card arrives from the
        // leading edge as the recap leaves by the trailing one, and the two travel together.
        // Set `false`, the card slid in from the right while the recap slid out to the right:
        // they crossed through each other, and the motion said *forward* for the one move in
        // this screen that is unambiguously a step back. `advanceTransition`'s own note is that
        // which way is the single thing this transition exists to say.
        //
        // Answering it — `advance()` on an excursion — returns to the recap and is forward
        // again, which is that function's `isMovingBack = false` and is already right.
        isMovingBack = true
        withAnimation(Motion.QuickPass.advance(reducedMotion: reduceMotion)) {
            sequence.jump(to: cardNumber)
        }
        announceArrival()
    }

    private var isStacked: Bool { effectiveTypeSize >= .accessibility1 }
}
