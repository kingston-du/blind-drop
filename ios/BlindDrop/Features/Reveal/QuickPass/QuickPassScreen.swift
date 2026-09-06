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
    /// Dismiss. Called when the run ends and when the caller closes out of it.
    let onFinish: () -> Void

    @State private var sequence: QuickPassSequence
    /// The name currently filled ultramarine, for the ~100ms before the card leaves. The whole of
    /// the feedback that a tap registered, which is why the advance itself needs no extra beat.
    @State private var confirming: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var typeSizeOverride: DynamicTypeSize?
    private var effectiveTypeSize: DynamicTypeSize { typeSizeOverride ?? dynamicTypeSize }

    /// A grid column's floor, scaled, so the pool drops from three columns to two to one as the
    /// text grows rather than overlapping at a fixed count.
    @ScaledMetric(relativeTo: .body) private var poolColumnMinimum = Layout.quickPassPoolColumn

    private let accent = PhaseAccent.revealed

    init(
        store: RevealStore,
        timer: CountdownTimer,
        player: PreviewPlayer? = nil,
        onFinish: @escaping () -> Void
    ) {
        self.store = store
        self.timer = timer
        self.player = player
        self.onFinish = onFinish
        _sequence = State(
            initialValue: QuickPassSequence(
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
        .onChange(of: sequence.isComplete) { _, complete in
            if complete { onFinish() }
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
        if let number = sequence.current, let card = card(number) {
            VStack(alignment: .leading, spacing: Space.none) {
                chrome
                numeral(number)
                artwork(card, availableHeight: availableHeight, availableWidth: availableWidth)
                lower(card, number: number)
            }
            .padding(.horizontal, Layout.screenInset)
            .padding(.bottom, Layout.blockGap)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The whole card, including its number and its name pool, is replaced as one thing.
            // Keyed on the card number so SwiftUI treats an advance as an arrival rather than as
            // a title changing in place.
            .id(number)
            .transition(advanceTransition)
        }
    }

    // MARK: - Chrome

    /// A close button, and deliberately nothing else.
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
    private var chrome: some View {
        HStack(alignment: .center) {
            CloseButton(action: onFinish)
                .padding(.leading, -Space.xs)
            Spacer(minLength: Space.md)
        }
        .frame(minHeight: Layout.minimumTouchTarget)
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
        let columns = max(1, Int((columnWidth + Space.sm) / (poolColumnMinimum + Space.sm)))
        let rows = max(1, Int(ceil(Double(store.pool.count) / Double(columns))))
        let poolHeight = CGFloat(rows) * Layout.chipHeightLarge + CGFloat(rows - 1) * Space.sm
        let side = min(
            min(
                max(
                    availableHeight - Layout.quickPassFixedChrome - poolHeight,
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

    private func lower(_ card: CardDTO, number: Int) -> some View {
        VStack(alignment: .leading, spacing: Space.none) {
            track(card)
            pool(on: number)
            skip
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
    private func pool(on number: Int) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: poolColumnMinimum), spacing: Space.sm)],
            alignment: .leading,
            spacing: Space.sm
        ) {
            ForEach(store.pool) { member in
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
    private var skip: some View {
        SecondaryButton("quickpass.skip") { advance() }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, Layout.itemGap)
    }

    // MARK: - Advancing

    private func choose(_ member: MemberDTO, on number: Int) {
        guard confirming == nil else { return }
        store.place(member.userID, on: number)
        confirming = member.userID
        Task {
            try? await Task.sleep(for: Motion.QuickPass.chipConfirm)
            confirming = nil
            advance()
        }
    }

    private func advance() {
        withAnimation(Motion.QuickPass.advance(reducedMotion: reduceMotion)) {
            sequence.advance()
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

    private var advanceTransition: AnyTransition {
        // Reduced motion keeps the arrival and drops the travel (`docs/12` §4).
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    private func card(_ number: Int) -> CardDTO? {
        store.cards.first { $0.cardNumber == number }
    }
}
