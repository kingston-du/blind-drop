import SwiftUI

private struct RecordResultsRoute: Hashable, Identifiable {
    let id: String
}

/// The Record: newest first, date-grouped, filterable, and free of feed mechanics.
struct RecordScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var loadToken = 0
    @State private var store: RecordStore?
    @State private var player = PreviewPlayer()
    @State private var resultsRoute: RecordResultsRoute?
    @State private var selectedMember: MemberDTO?

    var body: some View {
        Group {
            if let store {
                content(store)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.none) {
                        RecordPageHeading().padding(Layout.screenInset)
                        RecordFilterLabel(name: Copy.string("record.filter.all"))
                            .accessibilityHidden(true)
                            .padding(.horizontal, Layout.screenInset)
                        RecordSkeleton().padding(Layout.screenInset)
                    }
                }
            }
        }
        .background(Palette.paper)
        .navigationTitle(Text(verbatim: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Palette.paper, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar { exportToolbar }
        // One task, so construction cannot race the load — `RoundScreen`'s reasoning, and the
        // same `id:` handle so a foreground can re-run it.
        .task(id: loadToken) {
            if store == nil {
                store = env.routeStores.recordStore(for: await env.circles.resolveActiveID())
            }
            await store?.load()
        }
        .onChange(of: scenePhase) { _, phase in
            // `docs/08` §10: on foreground, refetch. The archive gains a night at `scores_at`,
            // two hours after reveal — reliably while the app is backgrounded — and the cached
            // store would otherwise still be holding last night's answer.
            if phase == .active { loadToken += 1 }
        }
        .onDisappear {
            player.stop()
            store?.clearFinishedExports()
        }
        .navigationDestination(item: $resultsRoute) { route in
            PastResultsScreen(roundID: route.id, player: player)
        }
        .navigationDestination(item: $selectedMember) { MemberProfileScreen(member: $0) }
    }

    private func content(_ store: RecordStore) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.none, pinnedViews: [.sectionHeaders]) {
                RecordPageHeading()
                    .padding(Layout.screenInset)
                memberFilter(store)
                    .padding(.horizontal, Layout.screenInset)
                    .padding(.bottom, Space.sm)
                if let error = store.state.error, store.state.value != nil {
                    OfflineBanner(error: error)
                        .padding(.horizontal, Layout.screenInset)
                        .padding(.top, Space.sm)
                }
                exportStatus(store)
                if store.state.isLoading {
                    RecordSkeleton().padding(Layout.screenInset)
                } else if let error = store.state.error, store.state.value == nil {
                    VStack(alignment: .leading, spacing: Layout.blockGap) {
                        Text(LocalizedStringKey(error.copyKey))
                            .typeStyle(.bodyM)
                            .foregroundStyle(Palette.inkDim)
                        PrimaryButton("error.retry", fill: .neutral) { Task { await store.load() } }
                    }
                    .padding(Layout.screenInset)
                } else if store.days.isEmpty {
                    emptyLine(store).padding(.horizontal, Layout.screenInset)
                } else {
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
            }
            .padding(.bottom, Layout.blockGap)
        }
        // Pin at the viewport edge, without an automatic content margin above the header.
        .contentMargins(.top, Space.none, for: .scrollContent)
        .clipped()
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
                    attribution: entry.displayName,
                    onAttributionTap: {
                        selectedMember = MemberDTO(userID: entry.userID, displayName: entry.displayName, role: nil)
                    }
                )
                TrackUtilityMenu(track: entry.track)
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

    /// The pinned date and optional cue open that night's results.
    private func dateHeader(_ day: RecordDayDTO, store: RecordStore) -> some View {
        Button {
            resultsRoute = RecordResultsRoute(id: day.roundID)
        } label: {
            HStack(alignment: .center, spacing: Space.sm) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(
                        verbatim: store.calendar?.shareDate(localDate: day.localDate) ?? day.localDate
                    )
                    .typeStyle(.displayS)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    if let cue = day.cue {
                        Text(verbatim: cue.text)
                            .typeStyle(.bodyLStrong)
                            .foregroundStyle(Palette.inkDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(Font(Typography.uiFont(.bodyLStrong)))
                    .foregroundStyle(Palette.inkSubtle)
            }
            .padding(.horizontal, Layout.screenInset)
            // Bind the filter to the first night; later nights keep their section spacing.
            .padding(.top, day.id == store.days.first?.id ? Space.sm : Space.xl)
            .padding(.bottom, Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Extend only the opaque backing across the scroll/nav seam. The label and
            // hit target retain their layout, while no preceding song can peek above it.
            .background { Palette.paper.padding(.top, -Space.sm) }
            .overlay(alignment: .bottom) { Rule(color: Palette.edge) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // One stop that says what it is and what it does, rather than a date, a cue line and a
        // chevron read as three (`docs/12` §2). The hint carries the action's own copy.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("record.results"))
    }

    @ViewBuilder private func emptyLine(_ store: RecordStore) -> some View {
        Group {
            if let member = store.selectedMember {
                Text(verbatim: Copy.format("record.empty.filtered", member.displayName))
            } else {
                Text("record.empty")
            }
        }
        .typeStyle(.displayM)
        .foregroundStyle(Palette.ink)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Layout.blockGap)
    }

    private func memberFilter(_ store: RecordStore) -> some View {
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
            RecordFilterLabel(name: store.filterName)
        }
        .accessibilityLabel(Text("record.filter.label"))
        .accessibilityValue(Text(verbatim: store.filterName))
    }

    /// Export, in the bar (owner, 2026-09-10).
    ///
    /// It was a permanent two-button footer, pinned by a bottom `safeAreaInset` across every
    /// state of the screen — a rare, heavy, once-in-a-while action holding sixty points of the
    /// list hostage on every scroll, and reading as the screen's primary action, which it is
    /// not. Reading the archive is.
    ///
    /// A menu rather than two bar buttons, because the two destinations are one decision made
    /// twice a year, and `record.export.*` are full sentences that no bar has room for. The two
    /// paths stay independent — a running Spotify export disables its own item and not Apple's —
    /// which is the one thing the footer had right.
    @ToolbarContentBuilder
    private var exportToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if let store {
                Menu {
                    Button("record.export.spotify") { Task { await store.exportToSpotify() } }
                        .disabled(store.spotifyExport == .working)
                    Button("record.export.apple") { Task { await store.exportToAppleMusic() } }
                        .disabled(store.appleExport == .working)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(Palette.inkDim)
                        .minimumTouchTarget()
                        // Label the visual content too for UIKit toolbar accessibility.
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("record.export.label"))
                }
                .accessibilityLabel(Text("record.export.label"))
            }
        }
    }

    /// What the export is doing, once it is doing something.
    ///
    /// The footer used to carry this under its buttons. With the buttons in the bar the report
    /// cannot live there — a menu closes — so it becomes a strip above the list, and only when
    /// there is something to report: both paths idle renders nothing at all, which is the state
    /// the screen is in almost always.
    ///
    /// `paperSunk`, which is the tier the night headers just vacated, and that is the point. A
    /// recessed unbordered strip is `CueBanner`'s material and means *the standing condition of
    /// this screen right now* — which is exactly what a playlist being built is. Paper would put
    /// it on the same plane as the headers and read as the first night in the list.
    @ViewBuilder
    private func exportStatus(_ store: RecordStore) -> some View {
        if store.spotifyExport != .idle || store.appleExport != .idle {
            VStack(alignment: .leading, spacing: Space.sm) {
                exportLine(store.spotifyExport)
                exportLine(store.appleExport)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Layout.screenInset)
            .padding(.vertical, Space.md)
            .background(Palette.paperSunk)
            .overlay(alignment: .bottom) { Rule(color: Palette.edge) }
        }
    }

    @ViewBuilder
    private func exportLine(_ state: RecordExportState) -> some View {
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

/// Shared with snapshots so the page typography is exercised by the layout matrix.
struct RecordPageHeading: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("record.title")
                .typeStyle(.displayL)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Text("record.subtitle")
                .typeStyle(.bodyM)
                .foregroundStyle(Palette.inkDim)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RecordFilterLabel: View {
    let name: String

    var body: some View {
        HStack(spacing: Space.xs) {
            Text(verbatim: name)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: "chevron.down")
        }
        .typeStyle(.bodyM)
        .foregroundStyle(Palette.inkDim)
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.sm)
        .minimumTouchTarget()
        // Draw the stroke after the touch-target frame so the capsule's full bounds are
        // identical on every edge; this avoids the bottom edge being visually clipped.
        .background(Palette.paper, in: Capsule())
        .overlay {
            Capsule().stroke(Palette.edgeStrong, lineWidth: Stroke.border)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
