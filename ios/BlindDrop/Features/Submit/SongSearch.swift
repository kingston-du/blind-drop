import SwiftUI

/// Finding a song: the field, and what came back.
///
/// One view, two hosts. It is the whole of `SubmitScreen` when nothing has been dropped yet,
/// and it is what `SearchSheet` presents when somebody comes back to change their mind. Both
/// need identical behaviour — the 250ms debounce, no spinner — and the way to guarantee
/// identical behaviour is to have one of it.
///
/// **The paste-a-link fallback is gone from both** (`E37-01`). It was a second full-width field
/// and a line of mono caps standing under the first field on a screen whose whole job is one
/// field, and it read as a second equal choice rather than as an escape hatch. `SubmitStore`
/// keeps `pasted`/`resolve()` — the link parser is still unit-tested and still correct — but no
/// screen offers it. If it comes back it comes back as something the failure surfaces it, not
/// as furniture standing there on every successful search.
///
/// **The field starts in the middle of the screen and rises as results arrive.** Before the
/// first keystroke there is nothing under it worth reserving space for, and a field pinned to
/// the top of an empty screen reads as a toolbar rather than as the one thing to do. Once rows
/// exist they take the space, because at that point the list is the screen.
///
/// **`E26-03`: the browsing flag reaches `header` too.** At `.accessibility5` `SubmitScreen`'s
/// full headline-and-subhead pair, stacked under the round's own chrome and above a field that
/// has grown to fit its own scaled text, was tall enough on its own to push every result row
/// under the keyboard — reproduced on iPhone 17 as *zero* rows visible while typing. `header` is
/// a closure rather than a plain `View` so its one caller with something to give up
/// (`SubmitScreen`'s subhead) can drop it once there is something worth the room instead — the
/// keyboard-avoidance arrangement this file already fought for (see `body` below) is untouched;
/// only what `header` chooses to draw changes.
struct SongSearch<Header: View, Footer: View>: View {
    let store: SubmitStore
    let player: PreviewPlayer
    /// The screen's accent, so the chosen row and the field agree with everything above them.
    let accent: PhaseAccent
    var isFieldFocused: FocusState<Bool>.Binding
    let choose: (TrackDTO) -> Void
    /// What sits above the field. The headline, usually. Takes whether results are being
    /// browsed, so a caller with a subhead to spare can give the results the room back.
    @ViewBuilder let header: (Bool) -> Header
    /// What sits under it while there is nothing to show.
    @ViewBuilder let footer: Footer

    /// A ceiling on the gap above `header`, or `nil` for a plain, uncapped `Spacer`.
    ///
    /// `SubmitScreen` is the one caller that sets this: its header sits directly under the
    /// round's own chrome, and an uncapped gap there put "Today's song." a variable — and
    /// often large — distance under it. `SearchSheet` leaves it `nil`: its own header **is**
    /// the screen's title, so there is nothing above it to crowd.
    var topGapCap: CGFloat? = nil
    /// Whether anything has come back to look at. `.idle` and an empty result set are the same
    /// screen: a field, and room under it. `SubmitStore.isBrowsingResults` is the one definition;
    /// `header(_:)` below is how a host gets the answer, rather than rederiving it itself.
    private var isBrowsing: Bool { store.isBrowsingResults }

    /// **The footer travels with the field; the flexible gaps sit above and below the block.**
    ///
    /// The flexible gap used to sit between the field and the footer, which put the whole
    /// explanation of the game at the bottom of the screen, a third of a page away from the
    /// control it explains. Nothing tied the two together except the reader's willingness to
    /// assume it. Now the gap is *outside* the block: the headline, the field, what it is for,
    /// and — after a full `blockGap` rather than jammed against it — the sentence explaining
    /// why, read as one thing with room above and below it.
    ///
    /// **Nothing is pinned to the bottom edge, and that is deliberate — arrived at the hard
    /// way.** This screen's column is laid out at the full height of the device, keyboard
    /// included, and the keyboard is up from the moment it appears. Anything genuinely pinned to
    /// the bottom is therefore pinned *underneath* the keyboard: as the last item after a
    /// flexible gap it was clipped in half, padding it clear only made SwiftUI's avoidance lift
    /// the whole screen and drive the header under the status bar, and `safeAreaInset` did not
    /// help either because it resolves against this container — which already extends past the
    /// keyboard — rather than against the window. So the column places its block with a capped
    /// gap above it and an open one below, and everything lands above the keyboard every time.
    var body: some View {
        VStack(alignment: .leading, spacing: Layout.blockGap) {
            // Two flexible gaps when there is nothing to show, one when there is. That is the
            // whole of the rise: SwiftUI resolves the field to the middle of an empty screen and
            // to just under the headline on a full one.
            if !isBrowsing {
                Spacer(minLength: Space.none)
                    .frame(maxHeight: topGapCap ?? .infinity)
            }
            header(isBrowsing)
            field
            if isBrowsing {
                results
            } else {
                footer
                Spacer(minLength: Space.none)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.22), value: isBrowsing)
        // Only the paper behind the controls dismisses focus; rows and the field keep their own
        // gestures and do not become accidental keyboard-dismiss taps.
        //
        // **This layer alone only covers the idle state**, which is why the browsing state went
        // unnoticed: `rows` is a `ScrollView`, a `ScrollView` is greedy, and the empty half of a
        // one-result search is therefore *inside* it. A scroll view eats a tap on its empty area
        // rather than passing it to what is behind, so every tap under the last result did
        // nothing at all. `rows` carries its own dismissal for that reason.
        .background {
            Palette.paper
                .contentShape(Rectangle())
                .onTapGesture(perform: dismissFocus)
        }
    }

    /// Puts the keyboard away.
    private func dismissFocus() {
        isFieldFocused.wrappedValue = false
    }

    // MARK: - The field

    /// The search field, and **its own** failure directly beneath it.
    ///
    /// *"No songs matched that."* belongs under the box the words were typed into, not at the
    /// foot of the screen under something the reader has not touched.
    @ViewBuilder private var field: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: Space.sm) {
            InsetField(
                "search.placeholder",
                text: $store.query,
                isFocused: isFieldFocused.wrappedValue
            )
            .focused(isFieldFocused)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            // `docs/12` §5: the search field supports hardware keyboard return-to-select.
            .submitLabel(.search)

            if let key = searchErrorKey { errorLine(key) }
        }
    }

    /// One line of `alert`, wherever a failure has to be said.
    private func errorLine(_ key: String) -> some View {
        Text(verbatim: Copy.string(key))
            .typeStyle(.caption)
            .foregroundStyle(Palette.alert)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - What came back

    /// The results, or the one line that replaces them.
    ///
    /// There is deliberately no spinner. `docs/08` §10: a refresh shows *nothing*; the screen's
    /// job while a debounced search is in flight is to keep showing what it had.
    @ViewBuilder private var results: some View {
        VStack(alignment: .leading, spacing: Layout.itemGap) {
            SectionLabel("search.results")
            rows(store.results.value ?? [])
        }
    }

    private func rows(_ tracks: [TrackDTO]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.sm) {
                ForEach(tracks) { track in
                    TrackRow(
                        track: track,
                        // No `preview_url` → no control (`docs/06` §7).
                        preview: track.previewURL.map { _ in
                            TrackRow.Preview(isPlaying: player.playing == track.trackKey) {
                                player.toggle(track)
                            }
                        },
                        style: .surface,
                        action: { choose(track) }
                    )
                    .debugSearchDelayValue(store.debugSearchDelayMilliseconds)
                }
            }
            .padding(.bottom, Layout.blockGap)
        }
        .scrollDismissesKeyboard(.interactively)
        // A drag already puts the keyboard away; a tap on the empty space under the results did
        // not, because the scroll view is what occupies that space and it absorbs the tap before
        // the dismissal layer behind it ever sees one. `simultaneousGesture` rather than
        // `onTapGesture`, so it adds to the rows instead of replacing them: a tap on a row still
        // chooses that track, and also drops the keyboard on the way to the confirm screen, which
        // is what somebody who just tapped a result wanted either way.
        .simultaneousGesture(TapGesture().onEnded(dismissFocus))
    }

    /// The message that belongs under the field: search failed, or search worked and matched
    /// nothing. Both are one line, and both leave the field as the way forward.
    private var searchErrorKey: String? {
        switch store.results {
        case .failed: store.searchErrorKey
        case .loaded, .stale: (store.results.value ?? []).isEmpty ? "search.empty" : nil
        case .idle, .loading: nil
        }
    }
}

extension View {
    @ViewBuilder func debugSearchDelayValue(_ milliseconds: Int?) -> some View {
        #if DEBUG
        accessibilityValue(milliseconds.map(String.init) ?? "")
        #else
        self
        #endif
    }
}
