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
                RecordSkeleton()
            }
        }
        .background(Palette.paper)
        .navigationTitle(Text("record.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        // Opaque, and that is the whole reason the sticky date strip stopped reading as a slice
        // through the list. The default bar is translucent, the `ScrollView` runs under it, and
        // the pinned header — opaque, and starting at the top of the *safe area* — cut whatever
        // row was ghosting through the blur clean in half. Nothing to ghost, nothing to cut.
        .toolbarBackground(Palette.paper, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        // One `toolbar`, not two, because two leave the order to SwiftUI and it put the export
        // glyph to the *left* of the filter. Declared together they land in declaration order:
        // filter, then export at the trailing edge, which is where an export belongs and where
        // it was asked for. iOS 26 merges adjacent trailing items into one glass capsule — that
        // is the platform's own grouping and is left alone.
        .toolbar { trailingToolbar }
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

    @ViewBuilder
    private func content(_ store: RecordStore) -> some View {
        VStack(spacing: Space.none) {
            if let error = store.state.error, store.state.value != nil {
                // A pagination refresh failed over the list we already have: flag it, keep it.
                OfflineBanner(error: error)
                    .padding(.horizontal, Layout.screenInset)
                    .padding(.top, Space.sm)
            }
            exportStatus(store)
            if store.state.isLoading {
                RecordSkeleton()
                    .padding(Layout.screenInset)
            } else if let error = store.state.error {
                // The first load failed with nothing to fall back on. A plain line, not a
                // boxed banner — the same failed-state treatment Group, Insights and Profile
                // already use. No grey panel around the words, just the words.
                VStack(alignment: .leading, spacing: Layout.blockGap) {
                    Text(LocalizedStringKey(error.copyKey))
                        .typeStyle(.bodyM)
                        .foregroundStyle(Palette.inkDim)
                    PrimaryButton("error.retry", fill: .neutral) { Task { await store.load() } }
                }
                .padding(Layout.screenInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if store.days.isEmpty {
                empty(store)
            } else {
                archive(store)
            }
        }
    }

    private func archive(_ store: RecordStore) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.none, pinnedViews: [.sectionHeaders]) {
                lede
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
    /// **One line, and no `displayL` title over it.** There was one, and it printed *The Record*
    /// a second time directly under a navigation bar already saying it — two headings and a
    /// subtitle before the first night, on a screen whose bar now also carries the filter and the
    /// export. `InsightsScreen` has never drawn its own title over the inline one and reads the
    /// better for it; this is the same call. The night headers are the page's typography now.
    ///
    /// No counts. The archive is paginated, so any total the screen could print would be the
    /// total *so far*, which reads as the total and is not one.
    private var lede: some View {
        Text("record.subtitle")
            .typeStyle(.bodyM)
            .foregroundStyle(Palette.inkDim)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Layout.screenInset)
            .padding(.top, Space.sm)
            .padding(.bottom, Space.xs)
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

    /// The sticky night header, **and the way into that night's results**.
    ///
    /// **Paper, not `paperSunk`, and it earns its edge with a rule instead of a fill.** The
    /// darker fill was there so a header pinned over a scrolling list read as on top of it —
    /// a real problem, solved the wrong way. It made the strip a plate wedged under a
    /// translucent bar, crisp along its top edge and mushy along its bottom, which is what read
    /// as *clipped*. An opaque navigation bar removes the ghosting the fill was compensating
    /// for, and a full-bleed `edge` rule along the bottom gives the strip the one hard boundary
    /// it actually needs: the one between it and the songs it names.
    ///
    /// **The date is the page's heading now, not its apparatus.** It was a `SectionLabel` —
    /// 11pt mono, tracked, uppercase, `inkDim` — which is the right treatment for a caption over
    /// a block and the wrong one for the unit this entire screen is organised by. At `displayS`
    /// in `ink` it is what a reader scrolls *to*, which is what a date in an archive is for, and
    /// it takes the screen's dropped `displayL` title's job without repeating the bar's word.
    ///
    /// A cued night carries its cue under the date — one neutral line, nothing when there was
    /// none (`docs/18-CUES.md` §7) — **in the face the cue wears everywhere else**, `bodyLStrong`,
    /// the same as `CueBanner`. It was `bodyS`/`inkDim`, two steps down from every other cue in
    /// the app, which made the one line saying what the night was about the quietest thing on the
    /// strip. `inkDim` rather than `CueBanner`'s `ink` because the roles invert here: on a live
    /// round the cue is the brief and the label above it is apparatus, while in the archive the
    /// night is what you are navigating by and the cue is a fact about it.
    ///
    /// The label the live round shows ("Tonight's cue:") is still not repeated: the date already
    /// names the night, so the cue text alone is the line.
    ///
    /// **The results live here, not on a song's overflow.** *(Owner, 2026-09-03.)* They were an
    /// item in `TrackUtilityMenu` alongside **Open in Spotify** / **Open in Apple Music**, which
    /// put a night-scoped action inside a menu whose every other item acts on the one song it
    /// hangs off — and repeated it identically on all three-to-twelve rows of the same night, so
    /// reaching a night's results meant picking an arbitrary song first. The action belongs to
    /// the night, and the night already has a header.
    ///
    /// **A whole tappable header with a chevron, not an ellipsis.** There is exactly one
    /// night-scoped action, and an overflow menu holding one item promises a set and charges two
    /// taps for it. The chevron is the app's existing "this pushes a screen" affordance
    /// (`GroupScreen.recordButton`), and a fixed glyph rather than a trailing text button because
    /// an uncapped label sharing this row with the date starves one of the two at accessibility
    /// sizes — the failure `CueBanner.isStacked` already documents.
    ///
    /// It is centred against the whole strip rather than pinned to the date's line: on a cued
    /// night the header is two lines and a top-aligned chevron sits against the top edge of a
    /// block it is the affordance for, which reads as attached to the date rather than to the
    /// night. Centred, it stays the strip's own control at every height the cue can take.
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
            // Asymmetric, and deliberately: a header wants more air above it, separating it from
            // the night that ended, than below it, where it is binding to its own songs. Even
            // padding on a 24pt date reads as a block floating between two lists.
            .padding(.top, Space.xl)
            .padding(.bottom, Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.paper)
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

    /// Day one, or a filter that matched nothing. Either way the screen still says what it is
    /// and what will end up in it — an archive with nothing in it yet is a promise, not a fault.
    private func empty(_ store: RecordStore) -> some View {
        VStack(alignment: .leading, spacing: Space.none) {
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
        // `displayM` in `ink`, which is what `RecordSnapshotTests.filteredEmptyMatrix` has always
        // rendered while the screen quietly drew `bodyL`/`inkDim` — the golden had the better
        // answer. With the screen's own `displayL` title gone there is nothing above this line to
        // give an empty archive structure, so the sentence has to be the structure.
        .typeStyle(.displayM)
        .foregroundStyle(Palette.ink)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Layout.blockGap)
    }

    @ToolbarContentBuilder
    private var trailingToolbar: some ToolbarContent {
        filterToolbar
        exportToolbar
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
                        // Same reason `filterToolbar` labels its visual content as well as the
                        // menu node: SwiftUI does not reliably forward the modifier to the UIKit
                        // toolbar button.
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
