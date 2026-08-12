import SwiftUI

/// `docs/08` §3.1 — the search sheet, presented from **Drop a song**.
///
/// ```
/// │  [ Search for a song            ]  │   InsetField, auto-focused
/// │  ▓▓  Ribs / Lorde            ▶︎    │   TrackRow
/// │  ▓▓  Nights / Frank Ocean    ▶︎    │
/// │  ─────────────────────────────────  │
/// │  Paste a Spotify or Apple Music link │  always present, below the results
/// ```
///
/// Three rules from that section shape everything here:
///
/// - **The empty query is a blank sheet.** No suggestions, no trending, no recents. *"This app
///   does not have opinions about what you should drop."*
/// - **The paste affordance is always present**, including under an error — an outage at Apple
///   takes search away and leaves the link path, which is exactly what `search.error` says.
/// - **A track with no preview gets no control at all**, not a disabled one (`docs/06` §7). That
///   is `TrackRow`'s `preview` being `nil` rather than a flag it renders greyed.
struct SearchSheet: View {
    let store: SubmitStore
    let player: PreviewPlayer
    /// The chosen track goes to `ConfirmScreen`, which is pushed **within the sheet** (`docs/08`
    /// §3.2) rather than onto the app's own path — a modal's stack is its own.
    let choose: (TrackDTO) -> Void
    let close: () -> Void

    /// `docs/08` §3.1: *"field auto-focused, keyboard up immediately."* The 90-second budget
    /// starts with the first keystroke, and a tap to focus is one of them.
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.blockGap) {
            field
            results
            Spacer(minLength: Space.none)
            paste
        }
        .padding(.horizontal, Layout.screenInset)
        .padding(.vertical, Layout.blockGap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.paper)
        .onAppear { isFieldFocused = true }
        // A preview that kept playing after the sheet closed would be a sound with no visible way
        // to stop it (`docs/06` §4 — one at a time, and this one is over).
        .onDisappear {
            player.stop()
            store.cancel()
        }
    }

    @ViewBuilder private var field: some View {
        @Bindable var store = store
        HStack(spacing: Space.md) {
            InsetField("search.placeholder", text: $store.query)
                .focused($isFieldFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                // `docs/12` §5: the search field supports hardware keyboard return-to-select.
                .submitLabel(.search)
            CloseButton(action: close)
        }
    }

    /// The results, or the one line that replaces them.
    ///
    /// There is deliberately no spinner. `docs/08` §10: a refresh shows *nothing*; the sheet's job
    /// while a 250ms-debounced search is in flight is to keep showing what it had, which is either
    /// the previous results or an empty sheet.
    @ViewBuilder private var results: some View {
        switch store.results {
        case .idle:
            // The blank sheet. Not an `EmptyState` — an empty state is an invitation with a
            // headline and a button, and this is a field waiting for a second character.
            EmptyView()
        case .loading, .loaded, .stale:
            rows(store.results.value ?? [])
        case .failed:
            message(store.searchErrorKey)
        }
    }

    @ViewBuilder private func rows(_ tracks: [TrackDTO]) -> some View {
        if tracks.isEmpty {
            message("search.empty")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.none) {
                    ForEach(tracks) { track in
                        TrackRow(
                            track: track,
                            // No `preview_url` → no control (`docs/06` §7).
                            preview: track.previewURL.map { _ in
                                TrackRow.Preview(isPlaying: player.playing == track.trackKey) {
                                    player.toggle(track)
                                }
                            },
                            action: { choose(track) }
                        )
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    @ViewBuilder private func message(_ key: String?) -> some View {
        if let key {
            Text(verbatim: Copy.string(key))
                .typeStyle(.bodyM)
                .foregroundStyle(Palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// **Paste a Spotify or Apple Music link** — always here, whatever the results did.
    @ViewBuilder private var paste: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: Layout.itemGap) {
            Text("search.paste")
                .typeStyle(.bodyM)
                .foregroundStyle(Palette.inkDim)
            InsetField("search.paste.placeholder", text: $store.pasted)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .onSubmit { resolve() }
            if let key = store.pasteErrorKey {
                Text(verbatim: Copy.string(key))
                    .typeStyle(.caption)
                    .foregroundStyle(Palette.alert)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func resolve() {
        Task {
            if let track = await store.resolve() { choose(track) }
        }
    }
}
