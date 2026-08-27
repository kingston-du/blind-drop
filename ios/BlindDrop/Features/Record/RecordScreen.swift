import SwiftUI

private struct RecordResultsRoute: Hashable, Identifiable {
    let id: String
}

/// The Record: newest first, date-grouped, filterable, and free of feed mechanics.
struct RecordScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openURL) private var openURL

    @State private var store: RecordStore?
    @State private var player = PreviewPlayer()
    @State private var resultsRoute: RecordResultsRoute?

    var body: some View {
        Group {
            if let store {
                content(store)
            } else {
                RecordSkeleton()
            }
        }
        .background(Palette.paper)
        .navigationTitle(Text("record.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar { filterToolbar }
        .task {
            if store == nil {
                store = env.routeStores.recordStore(for: await env.circles.resolveActiveID())
            }
            await store?.load()
        }
        .onDisappear { player.stop() }
        .navigationDestination(item: $resultsRoute) { route in
            RecordResultsScreen(roundID: route.id)
        }
    }

    @ViewBuilder
    private func content(_ store: RecordStore) -> some View {
        VStack(spacing: Space.none) {
            if let error = store.state.error {
                OfflineBanner(error: error)
                    .padding(.horizontal, Layout.screenInset)
                    .padding(.top, Space.sm)
            }
            if store.state.isLoading {
                RecordSkeleton()
                    .padding(Layout.screenInset)
            } else if store.days.isEmpty {
                empty(store)
            } else {
                archive(store)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: Space.none) {
            exportFooter(store)
        }
    }

    private func archive(_ store: RecordStore) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.none, pinnedViews: [.sectionHeaders]) {
                title
                ForEach(store.days) { day in
                    Section {
                        VStack(spacing: Space.none) {
                            ForEach(day.entries) { entry in
                                recordRow(entry, day: day, store: store)
                            }
                        }
                        .padding(.horizontal, Layout.screenInset)
                    } header: {
                        dateHeader(day, store: store)
                    }
                }
            }
            .padding(.bottom, Layout.blockGap)
        }
    }

    /// What the archive is, in one line, above the first date header.
    ///
    /// It scrolls with the list rather than sitting in the navigation bar, because the numbers
    /// in it are the point — how much of this there now is — and a subtitle in a bar is chrome
    /// nobody reads twice.
    private var title: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("record.title")
                .typeStyle(.displayL)
                .foregroundStyle(Palette.ink)
            // No counts. The archive is paginated, so any total the screen could print would be
            // the total *so far*, which reads as the total and is not one.
            Text("record.subtitle")
                .typeStyle(.bodyM)
                .foregroundStyle(Palette.inkDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Layout.screenInset)
        .padding(.bottom, Layout.itemGap)
    }

    private func recordRow(
        _ entry: RecordEntryDTO,
        day: RecordDayDTO,
        store: RecordStore
    ) -> some View {
        VStack(spacing: Space.none) {
            HStack(alignment: .center, spacing: Space.sm) {
                TrackRow(
                    track: entry.track,
                    preview: preview(for: entry.track),
                    attribution: entry.displayName
                )
                TrackUtilityMenu(track: entry.track) {
                    resultsRoute = RecordResultsRoute(id: day.roundID)
                }
            }
            // A rule under every row but the last of its day. The date headers already separate
            // the days; inside one, the rule is what keeps three songs from reading as a
            // paragraph.
            if entry.id != day.entries.last?.id { Rule(color: Palette.edge) }
        }
        .onAppear {
            Task {
                await store.loadMoreIfNeeded(
                    row: RecordRowID(roundID: day.roundID, userID: entry.userID)
                )
            }
        }
    }

    /// The sticky date strip. A step darker than `paper` so a header pinned over a scrolling
    /// list is visibly on top of it rather than floating in it.
    private func dateHeader(_ day: RecordDayDTO, store: RecordStore) -> some View {
        SectionLabel(
            verbatim: store.calendar?.shareDate(localDate: day.localDate) ?? day.localDate
        )
        .padding(.horizontal, Layout.screenInset)
        .padding(.vertical, Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.paperSunk)
    }

    /// Day one, or a filter that matched nothing. Either way the screen still says what it is
    /// and what will end up in it — an archive with nothing in it yet is a promise, not a fault.
    private func empty(_ store: RecordStore) -> some View {
        VStack(alignment: .leading, spacing: Space.none) {
            Text("record.title")
                .typeStyle(.displayL)
                .foregroundStyle(Palette.ink)
            emptyLine(store)
            Spacer(minLength: Space.none)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Layout.screenInset)
    }

    @ViewBuilder private func emptyLine(_ store: RecordStore) -> some View {
        Group {
            if let member = store.selectedMember {
                Text(verbatim: Copy.format("record.empty.filtered", member.displayName))
            } else {
                Text("record.empty")
            }
        }
        .typeStyle(.bodyL)
        .foregroundStyle(Palette.inkDim)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Layout.blockGap)
    }

    @ToolbarContentBuilder
    private var filterToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if let store {
                Menu {
                    Button("record.filter.all") { Task { await store.select(memberID: nil) } }
                    ForEach(store.members) { member in
                        Button {
                            Task { await store.select(memberID: member.userID) }
                        } label: {
                            Text(verbatim: member.displayName)
                        }
                    }
                } label: {
                    HStack(spacing: Space.xs) {
                        Text(verbatim: store.filterName)
                            .typeStyle(.bodyM)
                        Image(systemName: "chevron.down")
                    }
                    .foregroundStyle(Palette.inkDim)
                    .minimumTouchTarget()
                    // SwiftUI's toolbar `Menu` does not consistently forward a modifier from the
                    // menu node to the UIKit toolbar button. Put the label on its visual content
                    // as well so VoiceOver and XCTest receive it on every supported OS.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("record.filter.label"))
                }
                .accessibilityLabel(Text("record.filter.label"))
            }
        }
    }

    private func exportFooter(_ store: RecordStore) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            exportStatus(store.spotifyExport)
            exportStatus(store.appleExport)
            // Side by side, as two equal choices. Stacked, each full width, they read as a
            // primary and a runner-up, and neither of them is either.
            HStack(spacing: Space.sm) {
                IconOutlineButton(
                    systemImage: "square.and.arrow.up",
                    "record.export.spotify",
                    isEnabled: store.spotifyExport != .working
                ) { Task { await store.exportToSpotify() } }

                IconOutlineButton(
                    systemImage: "square.and.arrow.up",
                    "record.export.apple",
                    isEnabled: store.appleExport != .working
                ) { Task { await store.exportToAppleMusic() } }
            }
        }
        .padding(.horizontal, Layout.screenInset)
        .padding(.vertical, Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.paper)
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.edge).frame(height: Stroke.border)
        }
    }

    @ViewBuilder
    private func exportStatus(_ state: RecordExportState) -> some View {
        switch state {
        case .idle:
            EmptyView()
        case .working:
            Text("record.export.working")
                .typeStyle(.caption)
                .foregroundStyle(Palette.inkDim)
        case let .succeeded(result):
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("record.export.done")
                    .typeStyle(.caption)
                    .foregroundStyle(Palette.inkDim)
                if result.unresolvedCount > 0 {
                    Text(verbatim: Copy.format(
                        "record.export.partial",
                        result.unresolvedCount,
                        result.service.rawValue
                    ))
                    .typeStyle(.caption)
                    .foregroundStyle(Palette.inkDim)
                }
                if let url = result.url {
                    SecondaryButton("record.export.open") { openURL(url) }
                }
            }
        case let .failed(error):
            Text(failureKey(error))
                .typeStyle(.caption)
                .foregroundStyle(Palette.alert)
        }
    }

    private func failureKey(_ error: PlaylistExportError) -> LocalizedStringKey {
        switch error {
        case .denied: "record.export.denied"
        case .noSubscription: "record.export.nosub"
        case .failed: "record.export.failed"
        }
    }

    private func preview(for track: TrackDTO) -> TrackRow.Preview? {
        guard track.previewURL != nil else { return nil }
        return TrackRow.Preview(isPlaying: player.playing == track.trackKey) {
            player.toggle(track)
        }
    }
}

private struct RecordResultsScreen: View {
    @Environment(AppEnvironment.self) private var env
    /// Handed to `ResultsStore`, which is where the share entry for this round is actually built
    /// (`ResultsStore.shareEntry`) — a night three weeks old gets the same **Share tonight**
    /// button as tonight's, because both paths now ask the same store for it.
    @Environment(\.artworkLoader) private var artworkLoader
    let roundID: String
    @State private var store: ResultsStore?

    var body: some View {
        Group {
            if let store, store.state.value != nil {
                ResultsScreen(state: store.viewState(resolve: nil))
            } else if let error = store?.state.error {
                Text(LocalizedStringKey(error.copyKey))
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.alert)
                    .padding(Layout.screenInset)
            } else {
                RecordSkeleton().padding(Layout.screenInset)
            }
        }
        .background(Palette.paper)
        .toolbar(.visible, for: .navigationBar)
        .task {
            let built = store ?? ResultsStore(
                api: env.api, roundID: roundID, circles: env.circles, artworkLoader: artworkLoader
            )
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

private struct RecordSkeleton: View {
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
