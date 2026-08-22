import SwiftUI

/// A circle-scoped person, made only of finished play. There is intentionally no editable or
/// social surface here: no bio, follows, counts, or activity beyond songs this circle has scored.
struct MemberProfileScreen: View {
    @Environment(AppEnvironment.self) private var env
    let member: MemberDTO
    @State private var store: MemberProfileStore?

    var body: some View {
        Group {
            if let store {
                content(store)
            } else {
                ProfileSkeleton().padding(Layout.screenInset)
            }
        }
        .background(Palette.paper)
        .navigationTitle(Text(verbatim: member.displayName))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store == nil {
                store = env.routeStores.profileStore(
                    member: member,
                    circleID: await env.circles.resolveActiveID()
                )
            }
            await store?.load()
        }
    }

    @ViewBuilder private func content(_ store: MemberProfileStore) -> some View {
        if store.state.isLoading && store.state.value == nil {
            ProfileSkeleton().padding(Layout.screenInset)
        } else if let profile = store.state.value {
            ScrollView {
                MemberProfileContent(profile: profile, isOwnProfile: member.userID == env.session.user?.userID)
                    .padding(Layout.screenInset)
            }
        } else if let error = store.state.error {
            VStack(alignment: .leading, spacing: Layout.blockGap) {
                Text(LocalizedStringKey(error.copyKey)).typeStyle(.bodyM).foregroundStyle(Palette.inkDim)
                PrimaryButton("error.retry", fill: .neutral) { Task { await store.load() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Layout.screenInset)
        }
    }
}

/// Value-driven profile content keeps snapshot coverage on exactly the hierarchy a person sees.
struct MemberProfileContent: View {
    let profile: MemberProfileDTO
    let isOwnProfile: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.blockGap) {
            header
            metrics
            if !isOwnProfile { pairwise }
            recentTracks
        }
    }

    // The subtitle line ("Your history in this circle." / "Their history in this circle.")
    // is gone (`E28-06`) — self-explanatory once the numbers under it stop hiding behind a
    // sample-size gate (amendment A1), and one fewer sentence between the name and the numbers.
    //
    // **A face, not a sentence** (`E28-08`). `MonogramMark` gives the header the same
    // circled-initial language the sealed card's stamp uses, in neutral ink rather than
    // amber — a person, not a settings-list row. The strip of covers under it is the same
    // move: content the server already sent (`recentTracks`, below) standing in for the
    // deleted subtitle rather than a second sentence explaining what the screen is.
    private var header: some View {
        VStack(alignment: .leading, spacing: Layout.itemGap) {
            HStack(spacing: Space.md) {
                MonogramMark(name: profile.member.displayName, diameter: Layout.Artwork.recordRow)
                Text(verbatim: profile.member.displayName).typeStyle(.displayL).foregroundStyle(Palette.ink)
            }
            if !profile.recentTracks.isEmpty { artworkStrip }
        }
    }

    /// The last five covers this circle has actually seen from them (`E28-08`) — the one place
    /// arbitrary colour belongs on this screen, because artwork is content the server already
    /// sent for `recentTracks` below, not decoration invented for the header.
    private var artworkStrip: some View {
        HStack(spacing: Space.xs) {
            ForEach(profile.recentTracks.prefix(5)) { entry in
                ArtworkView(entry.track, size: Layout.Artwork.recordRow)
            }
        }
        .accessibilityHidden(true)
    }

    // **One panel, not three** (`E28-08`): the numbers used to be three separately bordered
    // boxes, which is the cards-in-cards clutter the rest of this screen was also drawn with.
    // Stacked, ruled rows are `StandingsView.table`'s own shape for a set of people; this is the
    // same shape for a set of numbers about one person instead.
    private var metrics: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel("profile.stats")
            VStack(spacing: Space.none) {
                statRow(StatFigure(
                    label: "results.ear.label",
                    value: profile.ear.value != nil ? ScoringFormat.percent(profile.ear.value) : ScoringFormat.unavailable,
                    detail: profile.ear.value != nil ? Copy.format("profile.samples", profile.ear.samples) : Copy.string("profile.rounds.none"),
                    progress: profile.ear.value
                ))
                Rule()
                statRow(StatFigure(
                    label: "results.readability.label",
                    value: profile.readability.value != nil ? ScoringFormat.percent(profile.readability.value) : ScoringFormat.unavailable,
                    detail: profile.readability.value != nil ? Copy.format("profile.samples", profile.readability.samples) : Copy.string("profile.rounds.none"),
                    progress: profile.readability.value
                ))
                Rule()
                statRow(StatFigure(label: "profile.drops", value: "\(profile.dropCount)"))
            }
            .cardSurface(radius: Radius.panel, inset: Layout.rowInset)
        }
    }

    private func statRow(_ figure: StatFigure) -> some View {
        figure.padding(.vertical, Space.sm)
    }

    private var pairwise: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel("profile.pairwise")
            VStack(spacing: Space.none) {
                statRow(pairwiseFigure(title: "profile.youread", read: profile.youReadThem))
                Rule()
                statRow(pairwiseFigure(title: "profile.theyread", read: profile.theyReadYou))
            }
            .cardSurface(radius: Radius.panel, inset: Layout.rowInset)
        }
    }

    private func pairwiseFigure(title: LocalizedStringKey, read: PairwiseReadDTO?) -> StatFigure {
        let hasRounds = (read?.possible ?? 0) > 0
        return StatFigure(
            label: title,
            value: hasRounds ? ScoringFormat.percent(read?.rate) : ScoringFormat.unavailable,
            detail: (hasRounds ? read : nil).map { Copy.format("profile.pairwise.detail", $0.correct, $0.possible) }
                ?? Copy.string("profile.rounds.none"),
            progress: hasRounds ? read?.rate : nil
        )
    }

    private var recentTracks: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionLabel("profile.recent")
            if profile.recentTracks.isEmpty {
                Text("profile.recent.empty").typeStyle(.bodyM).foregroundStyle(Palette.inkDim)
            } else {
                VStack(spacing: Space.none) {
                    ForEach(profile.recentTracks) { entry in
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            Text(verbatim: ProfileDate.string(entry.localDate))
                                .typeStyle(.monoS).foregroundStyle(Palette.inkDim)
                            TrackRow(track: entry.track)
                        }
                        if entry.id != profile.recentTracks.last?.id { Rule() }
                    }
                }
            }
        }
    }
}

/// The profile's shape in `paperSunk` — a mark and a name, a three-row panel, a list (`E28-08`).
/// `RoundSkeleton` promised a round's three generic blocks, the wrong shape for this screen; with
/// `E28-06`'s in-place refresh this is now seen once per visit rather than on every return trip.
struct ProfileSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Layout.blockGap) {
            HStack(spacing: Space.md) {
                Circle().fill(Palette.paperSunk).frame(width: Layout.Artwork.recordRow, height: Layout.Artwork.recordRow)
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Palette.paperSunk).frame(width: Space.x6 * 2 + Space.lg, height: Layout.buttonHeight * 0.6)
            }
            RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                .fill(Palette.paperSunk).frame(height: Layout.buttonHeight * 3)
            RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                .fill(Palette.paperSunk).frame(height: Layout.buttonHeight * 2)
        }
        .accessibilityHidden(true)
    }
}

private enum ProfileDate {
    static func string(_ localDate: String) -> String {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: localDate) else { return localDate }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
