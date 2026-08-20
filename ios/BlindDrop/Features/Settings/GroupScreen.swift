import SwiftUI

/// The circle's members, ranked by all-time Ear (`E24-01`, `docs/02` §4). Readability rides
/// along on the same row, unranked and unaccented — the same asymmetry `StandingsView` argues,
/// because it is the same rule (`docs/02` §4.5). This is a thing to look at first; a roster to
/// manage is second, which is why whatever admin surface exists sits below the leaderboard and
/// stays quiet (`CLAUDE.md` §2.5 — no accent belongs on a screen that isn't the reveal or How to
/// play).
struct GroupScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var store: GroupStore?
    @State private var selectedMember: MemberDTO?

    var body: some View {
        Group {
            if let store {
                content(store)
            } else {
                RoundSkeleton().padding(Layout.screenInset)
            }
        }
        .background(Palette.paper)
        .navigationTitle(Text("group.title"))
        .navigationBarTitleDisplayMode(.inline)
        // Scoped to this screen's own local state — it still pushes onto the root
        // `NavigationStack` `RootView` owns (`docs/13` §4), the same trick `RoundScreen`'s own
        // nested `.navigationDestination(item:)` uses. `Route` itself stays a closed, three-case
        // enum (`docs/13` §4: *"adding a fourth case is a product change"*) — a member's profile
        // is not a fourth destination, it is a value pushed from a screen that is already one.
        .navigationDestination(item: $selectedMember) { member in
            MemberProfilePlaceholder(member: member)
        }
        .task {
            if store == nil { store = GroupStore(api: env.api, circles: env.circles) }
            await store?.load()
        }
    }

    @ViewBuilder
    private func content(_ store: GroupStore) -> some View {
        if store.state.isLoading {
            RoundSkeleton().padding(Layout.screenInset)
        } else if let error = store.state.error {
            VStack(alignment: .leading, spacing: Layout.blockGap) {
                Text(LocalizedStringKey(error.copyKey))
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.inkDim)
                PrimaryButton("error.retry", fill: .neutral) { Task { await store.load() } }
            }
            .padding(Layout.screenInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if let group = store.group {
            ScrollView {
                GroupContent(
                    group: group,
                    bestEar: store.bestEar,
                    readabilityByUserID: store.readabilityByUserID,
                    standingsLoading: store.standings.isLoading && store.standings.value == nil,
                    isThinHistory: store.isThinHistory,
                    select: { selectedMember = $0 }
                )
                .padding(Layout.screenInset)
            }
        }
    }
}

/// The screen's whole loaded state, as a value — no store, no network, which is what makes it
/// the thing a snapshot golden points at (the same split `RecordSnapshotContent` and
/// `ResultsScreen`'s `state:` initialiser make for their own store-backed screens).
struct GroupContent: View {
    let group: GroupDTO
    let bestEar: [EarStandingDTO]
    let readabilityByUserID: [String: ReadabilityStandingDTO]
    /// The leaderboard's own in-flight state — distinct from the roster's, the same split
    /// `ResultsStore` makes between the answers and the standings (`docs/13`). The roster can be
    /// on screen while the ranking is still arriving.
    var standingsLoading: Bool = false
    let isThinHistory: Bool
    let select: (MemberDTO) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: Layout.blockGap) {
            Text(verbatim: group.name)
                .typeStyle(.displayM)
                .foregroundStyle(Palette.ink)

            leaderboard

            // Secondary, deliberately: below the leaderboard, in the quiet apparatus voice, and
            // gated on `isAdmin` so a non-admin sees nothing here at all. `E21-01` (same batch,
            // different worktree) owns rename, reveal-hour and leave; this is only what already
            // exists on `GroupDTO` today, kept out of its way rather than duplicating it.
            if group.isAdmin {
                adminSection
            }
        }
    }

    @ViewBuilder
    private var leaderboard: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel("results.standings.ear")
            if standingsLoading {
                RoundSkeleton()
            } else if isThinHistory {
                Text("group.standings.thin")
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.inkDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .rowSurface()
            } else {
                VStack(spacing: Space.sm) {
                    ForEach(bestEar) { standing in
                        MemberStandingRow(
                            standing: standing,
                            readability: readabilityByUserID[standing.userID]
                        ) {
                            if let member = group.members.first(where: { $0.id == standing.userID }) {
                                select(member)
                            }
                        }
                    }
                }
            }
        }
    }

    private var adminSection: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionLabel("group.admin")
            HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                Text("onboarding.invite.title")
                Spacer(minLength: Space.sm)
                Text(verbatim: group.inviteCode)
            }
            .typeStyle(.bodyM)
            .foregroundStyle(Palette.inkDim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .rowSurface()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: Copy.format(
                "a11y.invite.code", JoinOrCreateScreen.spelled(group.inviteCode)
            )))
        }
    }
}

/// One member, tappable: the identical rank/name/numbers layout `StandingsView` draws, wrapped
/// as a real control rather than static text — mirrors `CircleSwitcherSheet`'s row exactly
/// (`Button` wrapping the content, `.buttonStyle(.plain)`, `.accessibilityElement(children:
/// .ignore)`, an explicit `.isButton` trait, a hint naming the action).
struct MemberStandingRow: View {
    let standing: EarStandingDTO
    let readability: ReadabilityStandingDTO?
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            StandingRowContent(standing: standing, readability: readability)
                .frame(maxWidth: .infinity, alignment: .leading)
                .rowSurface()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: StandingRowContent.announcement(
            standing: standing, readability: readability
        )))
        .accessibilityHint(Copy.string("a11y.group.row.hint"))
        .accessibilityAddTraits(.isButton)
    }
}

/// Enough to prove the row is a real control wired to a real destination, without building
/// `E24-02`'s actual profile (Ear, Readability, drop history, You vs. them — a separate,
/// not-yet-built slice). Circle-scoped by construction: it only ever receives a member drawn
/// from the active circle's own roster.
struct MemberProfilePlaceholder: View {
    let member: MemberDTO

    var body: some View {
        Text("group.profile.placeholder")
            .typeStyle(.bodyM)
            .foregroundStyle(Palette.inkDim)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Layout.screenInset)
            .background(Palette.paper)
            .navigationTitle(Text(verbatim: member.displayName))
            .navigationBarTitleDisplayMode(.inline)
    }
}
