import SwiftUI

/// Finding a song: the field, what came back, and the link box for when search cannot help.
///
/// One view, two hosts. It is the whole of `SubmitScreen` when nothing has been dropped yet,
/// and it is what `SearchSheet` presents when somebody comes back to change their mind. Both
/// need identical behaviour — the 250ms debounce, no spinner, the paste fallback always
/// present — and the way to guarantee identical behaviour is to have one of it.
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
    /// Whether a second flexible gap sits between `footer` and `paste`, so capping `topGapCap`
    /// does not also drag the paste fallback up with everything above it — the space saved at
    /// the top goes here instead, which is what keeps the paste line roughly where it was.
    /// `SearchSheet` leaves this `false`, matching its own uncapped top gap.
    var addsGapBeforePaste: Bool = false

    /// Whether anything has come back to look at. `.idle` and an empty result set are the same
    /// screen: a field, and room under it. `SubmitStore.isBrowsingResults` is the one definition;
    /// this file and its two hosts all read it rather than each rederiving the same check.
    private var isBrowsing: Bool { store.isBrowsingResults }

    /// Whether the link box has been asked for.
    ///
    /// It starts closed. The fallback has to be *findable* — it is the only way through when
    /// search is down or the song is unsearchable — but it is not what anybody came to do, and a
    /// second full-width field standing under the first one all the time reads as two equal
    /// choices when it is one choice and one escape hatch.
    @State private var isPasting = false
    @FocusState private var isPasteFocused: Bool

    /// **The footer travels with the field; the flexible gap goes below the paste line.**
    ///
    /// The flexible gap used to sit between the field and the footer, which put the whole
    /// explanation of the game at the bottom of the screen, a third of a page away from the
    /// control it explains. Nothing tied the two together except the reader's willingness to
    /// assume it. Now the gap is *below* the footer: the field, what it is for, and — after a
    /// full `blockGap` rather than jammed against it — the sentence explaining why, read as one
    /// block.
    ///
    /// The paste line follows the footer **in the flow**, with the flexible gap after it rather
    /// than before it. It is the last thing in the column and reads as its foot, but it is not
    /// pinned to the screen's bottom edge — and that is deliberate, arrived at the hard way.
    ///
    /// This screen's column is laid out at the full height of the device, keyboard included, and
    /// the keyboard is up from the moment it appears. Anything genuinely pinned to the bottom is
    /// therefore pinned *underneath* the keyboard: as the last item after a flexible gap it was
    /// clipped in half, padding it clear only made SwiftUI's avoidance lift the whole screen and
    /// drive the header under the status bar, and `safeAreaInset` did not help either because it
    /// resolves against this container — which already extends past the keyboard — rather than
    /// against the window. Putting the gap below it is the arrangement with no failure mode: the
    /// line lands under the sentence it belongs with, above the keyboard, every time.
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
                // The gap capped above reappears here: what it no longer spends pushing the
                // header down, it spends holding the paste line where it already was.
                if addsGapBeforePaste { Spacer(minLength: Space.none) }
                paste
                Spacer(minLength: Space.none)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.22), value: isBrowsing)
        // Only the paper behind the controls dismisses focus; rows, fields and the paste control
        // keep their own gestures and do not become accidental keyboard-dismiss taps.
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

    /// Puts the keyboard away. Two fields can hold it, and neither knows about the other.
    private func dismissFocus() {
        isFieldFocused.wrappedValue = false
        isPasteFocused = false
    }

    // MARK: - The field

    /// The search field, and **its own** failure directly beneath it.
    ///
    /// Search failing and a link failing are two different failures about two different fields,
    /// and each says so where it happened: *"No songs matched that."* belongs under the box the
    /// words were typed into, not at the foot of the screen under a control the reader has not
    /// touched. The paste box carries the other half (`resolve.error.*`) under itself.
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

    // MARK: - The fallback

    /// **Paste a Spotify or Apple Music link** — always here, whatever the results did.
    ///
    /// It is the answer to two different failures at once: search being down, and the song
    /// simply not being findable by name. Both end with a link in somebody's clipboard.
    ///
    /// **The words are the control until they are the heading.** Closed, `search.paste` is the
    /// button; opened, the same line stays put as the label over the field it just revealed. One
    /// string doing both jobs is what keeps the transition from being a swap — nothing is
    /// replaced, one thing appears underneath.
    ///
    /// Its failure — a bad link, or one the catalog does not carry — sits under **this** field,
    /// not under the search box above it, for the same reason the search error sits under that
    /// one: an error belongs where the thing that caused it is.
    ///
    /// **The words are centred; the field they open is not.** Centring is what stops one small
    /// line of mono caps at the foot of a left-aligned column from reading as a fourth ragged
    /// start — it sits under the column as a footer rather than in it as another item. The field
    /// stays full-width and leading-aligned, because it is a place to type and every other place
    /// to type in this app begins at the same left edge.
    @ViewBuilder private var paste: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: Space.sm) {
            if isPasting {
                SectionLabel("search.paste", style: .labelSmall)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                InsetField(
                    "search.paste.placeholder",
                    text: $store.pasted,
                    isFocused: isPasteFocused
                )
                .focused($isPasteFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.go)
                .onSubmit(resolve)

                if let key = store.pasteErrorKey { errorLine(key) }
            } else {
                Button {
                    isPasting = true
                    // The field it just revealed is the thing to type into, so the keyboard goes
                    // there rather than staying on the search field behind it.
                    isPasteFocused = true
                } label: {
                    // The target is on the *label*, not around the button: a frame outside a
                    // `Button` grows the layout without growing what is tappable.
                    SectionLabel("search.paste", color: Palette.ink, style: .labelSmall)
                        .multilineTextAlignment(.center)
                        .minimumTouchTarget()
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.18), value: isPasting)
    }

    /// The message that belongs under the field: search failed, or search worked and matched
    /// nothing. Both are one line, and both leave the paste box as the way forward.
    private var searchErrorKey: String? {
        switch store.results {
        case .failed: store.searchErrorKey
        case .loaded, .stale: (store.results.value ?? []).isEmpty ? "search.empty" : nil
        case .idle, .loading: nil
        }
    }

    private func resolve() {
        Task {
            if let track = await store.resolve() { choose(track) }
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
