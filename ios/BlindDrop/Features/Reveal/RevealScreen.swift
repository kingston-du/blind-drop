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
    var groupInitial = ""
    var unseal: UnsealAnimation? = nil
    var player: PreviewPlayer? = nil

    private var state: RevealViewState { store.viewState }

    /// Ties each card to its rotor entry. The entries are declared on the `ScrollView` and the
    /// cards are built further down the tree, so the namespace is what pairs the two — it is how
    /// VoiceOver jumps to No. 11 on a twelve-card reveal, and how the scroll view knows to bring
    /// it into view when it does.
    @Namespace private var songs
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let accent = PhaseAccent.revealed

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: Space.none) {
                flight
                // Pinned, so the names stay reachable however far down the flight the reader is
                // (`docs/08` §6). The two scroll independently.
                GuessSheet(store: store, availableHeight: proxy.size.height)
            }
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
        .task { await unseal?.run(reducedMotion: reduceMotion) }
        .onDisappear {
            player?.stop()
            store.cancelPendingSave()
        }
    }

    private var flight: some View {
        GeometryReader { viewport in
            ScrollView {
                // The screen inset belongs to the scroll container, not to the column inside it
                // (`docs/07` §4). Keeping it here is also what lets `content` be snapshot directly.
                content
                    .padding(.horizontal, Layout.screenInset)
            }
            .coordinateSpace(name: "reveal-flight")
            .onPreferenceChange(RevealCardFrames.self) { frames in
                let bounds = CGRect(origin: .zero, size: viewport.size)
                unseal?.updateVisibleCards(Set(frames.compactMap { number, frame in
                    frame.intersects(bounds) && frame.width > 0 && frame.height > 0 ? number : nil
                }))
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
    var snapshotContent: some View {
        flightContent(includeRotorEntries: false)
    }

    private func flightContent(includeRotorEntries: Bool) -> some View {
        // A plain `VStack`, not a `LazyVStack`. A group runs to **twelve members** (`docs/02`),
        // so the whole flight is twelve cards at the absolute most — laziness would save nothing
        // and costs two real things: a lazy stack builds no off-screen row, which is exactly the
        // row the "Songs" rotor has to be able to jump to, and it mis-reports its height to
        // `ImageRenderer`, which clipped the first line off every golden until this changed.
        VStack(alignment: .leading, spacing: Space.lg) {
            header
            cards(includeRotorEntries: includeRotorEntries)
        }
        .padding(.bottom, Layout.blockGap)
    }

    /// *"Tonight's drop / 8 songs · 01:42:19"* (`docs/08` §6).
    private var header: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(verbatim: Copy.string("reveal.title"))
                .typeStyle(.displayM)
                .foregroundStyle(Palette.ink)

            statusLine
        }
        // One element, so the title and the status line are one stop rather than three. The
        // countdown keeps its own `.updatesFrequently` announcement by staying a child of it.
        .accessibilityElement(children: .contain)
        .padding(.bottom, Space.sm)
    }

    /// `bodyM inkDim` and a `monoM` countdown, separated by a middot.
    ///
    /// A `ViewThatFits` rather than a fixed row: at `.accessibility5` on a 375pt screen *"12
    /// songs"* and a countdown do not share a line, and the middot between them is a separator
    /// that has stopped separating anything. The stacked branch drops it.
    private var statusLine: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.sm) {
                songCount
                Text(verbatim: "·").typeStyle(.bodyM).foregroundStyle(Palette.inkFaint)
                countdown
            }
            VStack(alignment: .leading, spacing: Space.xxs) {
                songCount
                countdown
            }
        }
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
            prominence: .inline
        )
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
                chooseGuess: store.isGuessable(card.cardNumber)
                    ? { store.tapCard(card.cardNumber) }
                    : nil,
                clearGuess: store.isLocked || state.guesses[card.cardNumber] == nil
                    ? nil
                    : { store.clearGuess(on: card.cardNumber) },
                unseal: unseal.map {
                    UnsealPresentation(
                        phase: $0.phase(for: card.cardNumber),
                        groupInitial: groupInitial,
                        reducedMotion: reduceMotion
                    )
                }
            )
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
                .stroke(accent.fill, lineWidth: Stroke.mark)
        }
    }
}

private struct RevealCardFrames: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
