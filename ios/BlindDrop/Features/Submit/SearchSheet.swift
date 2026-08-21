import SwiftUI

/// Searching again, after something has already been sealed.
///
/// The first search is not this — it is `SubmitScreen`, which *is* the search screen. This is
/// the second one: somebody has a sealed song and wants a different one, so the search arrives
/// over the top of what they have rather than in place of it, and it closes back onto it.
///
/// It shares `SongSearch` with the screen, so the field, the debounce, the rows and the paste
/// fallback behave identically in both. What it adds is a title, a way out, and the header that
/// says which of the two situations this is.
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

    private let accent = PhaseAccent.sealed

    var body: some View {
        SongSearch(
            store: store,
            player: player,
            accent: accent,
            isFieldFocused: $isFieldFocused,
            choose: choose,
            // Nothing here to give up while browsing — the sheet's header is only the modal
            // title and the close button, not `SubmitScreen`'s headline-and-subhead pair.
            header: { _ in header },
            footer: { EmptyView() }
        )
        .padding(.horizontal, Layout.screenInset)
        // **Top only** (`E28-02`). This used to pad both edges, which is the one structural
        // difference from `SubmitScreen` — the screen this shares `SongSearch` with, and the
        // one the owner pointed at as the layout to match. That screen never wraps `SongSearch`
        // in a bottom inset at all; its rows run to the true bottom of the column and are simply
        // visible through the keyboard, exactly like every list under a keyboard elsewhere in
        // the app. A bottom `padding` here instead drew a fixed strip of `paper` beneath
        // `SongSearch`'s own frame — the sheet default system background showed through it once
        // the keyboard's safe area pushed content above that strip — which is both the grey
        // band under the keyboard and, since `LazyVStack` rows kept laying out past where the
        // padded frame told `ScrollView` to stop clipping, the flashing gap a tap could still
        // land on a row through.
        .padding(.top, Layout.blockGap)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.paper)
        // Covers the presentation itself, not just this content's own frame — belt and braces
        // against the same system-background leak, wherever a future edit reintroduces it.
        .presentationBackground(Palette.paper)
        .presentationDetents([.large])
        .onAppear { isFieldFocused = true }
        // A preview that kept playing after the sheet closed would be a sound with no visible
        // way to stop it (`docs/06` §4 — one at a time, and this one is over).
        .onDisappear {
            player.stop()
            store.cancel()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Space.md) {
            Text("submit.headline")
                .typeStyle(.displayM)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: Space.sm)
            CloseButton(action: close)
        }
    }
}
