import SwiftUI

/// A finished night's answers, loaded on their own.
///
/// **Two callers, one screen.** The Record pushes it from a night's date header, and the dark
/// hours push it from *"Tonight's round is done."* — the round that just ended is not the round
/// `GET /rounds/current` is returning at 3 a.m., so that screen reaches its results by id like
/// any other past night (`docs/18-CUES.md` §7). It used to be `private` inside `RecordScreen`
/// and is here now because it is a Results screen that The Record happens to link to, not a part
/// of The Record.
///
/// It is a loader, not a layout: `ResultsScreen` draws the night, exactly as it draws tonight's.
struct PastResultsScreen: View {
    @Environment(AppEnvironment.self) private var env
    /// Handed to `ResultsStore`, which is where the share entry for this round is actually built
    /// (`ResultsStore.shareEntry`) — a night three weeks old gets the same **Share tonight**
    /// button as tonight's, because both paths now ask the same store for it.
    @Environment(\.artworkLoader) private var artworkLoader
    let roundID: String
    /// The same 30-second preview the calling screen plays through (`docs/06` §4), shared so
    /// starting a preview here stops whatever that screen had going — and so a past round's cards
    /// get the same tap-to-preview the live results already had (`docs/17` §2, `E29-02`).
    let player: PreviewPlayer
    @State private var store: ResultsStore?

    var body: some View {
        Group {
            if let store, store.state.value != nil {
                ResultsScreen(state: store.viewState(resolve: nil), isPastRound: true, player: player)
            } else if let error = store?.state.error {
                Text(LocalizedStringKey(error.copyKey))
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.alert)
                    .padding(Layout.screenInset)
            } else {
                PastResultsSkeleton().padding(Layout.screenInset)
            }
        }
        .background(Palette.paper)
        .toolbar(.visible, for: .navigationBar)
        // From the cache, so a night opened twice does not load twice (`E44-03`). Before this,
        // the store was built fresh on every push and the skeleton was drawn over a payload the
        // app had already fetched — the same defect `RouteStoreCache` was written for, on the one
        // screen it did not reach. `load()` refreshes in place over what the cache returns.
        .task {
            let built = store ?? env.routeStores.resultsStore(for: roundID) {
                ResultsStore(
                    api: env.api, roundID: roundID, circles: env.circles, artworkLoader: artworkLoader
                )
            }
            store = built
            await built.load()
        }
        .onDisappear {
            // Same rule as the live round's results (`docs/10` §5): leaving this screen takes
            // its share card's temporary files with it, whether or not a share sheet ever opened.
            store?.discardShareRender()
        }
    }
}

/// Three bars where the answers will be. The same shape The Record's own skeleton draws, kept
/// separate because that one is private to its screen and this one moved out with this view.
private struct PastResultsSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Layout.blockGap) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Palette.paperSunk)
                    .frame(height: Layout.buttonHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }
}
