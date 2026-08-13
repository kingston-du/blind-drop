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
struct SongSearch<Header: View, Footer: View>: View {
    let store: SubmitStore
    let player: PreviewPlayer
    /// The screen's accent, so the chosen row and the field agree with everything above them.
    let accent: PhaseAccent
    var isFieldFocused: FocusState<Bool>.Binding
    let choose: (TrackDTO) -> Void
    /// What sits above the field. The headline, usually.
    @ViewBuilder let header: Header
    /// What sits under it while there is nothing to show.
    @ViewBuilder let footer: Footer

    /// Whether anything has come back to look at. `.idle` and an empty result set are the same
    /// screen: a field, and room under it.
    private var isBrowsing: Bool {
        !(store.results.value ?? []).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.blockGap) {
            // Two flexible gaps when there is nothing to show, one when there is. That is the
            // whole of the rise: SwiftUI resolves the field to the middle of an empty screen and
            // to just under the headline on a full one.
            if !isBrowsing { Spacer(minLength: Space.none) }
            header
            field
            if isBrowsing {
                results
            } else {
                Spacer(minLength: Space.none)
                footer
                paste
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.22), value: isBrowsing)
    }

    // MARK: - The field

    @ViewBuilder private var field: some View {
        @Bindable var store = store
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
    }

    // MARK: - The fallback

    /// **Paste a Spotify or Apple Music link** — always here, whatever the results did.
    ///
    /// It is the answer to two different failures at once: search being down, and the song
    /// simply not being findable by name. Both end with a link in somebody's clipboard.
    @ViewBuilder private var paste: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel("search.paste")
            InsetField("search.paste.placeholder", text: $store.pasted)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .onSubmit(resolve)
            if let key = store.pasteErrorKey ?? searchErrorKey {
                Text(verbatim: Copy.string(key))
                    .typeStyle(.caption)
                    .foregroundStyle(Palette.alert)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
