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
                RoundSkeleton().padding(Layout.screenInset)
            }
        }
        .background(Palette.paper)
        .navigationTitle(Text(verbatim: member.displayName))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store == nil { store = MemberProfileStore(member: member, api: env.api, circles: env.circles) }
            await store?.load()
        }
    }

    @ViewBuilder private func content(_ store: MemberProfileStore) -> some View {
        if store.state.isLoading && store.state.value == nil {
            RoundSkeleton().padding(Layout.screenInset)
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

    static let minimumSamples = GroupStore.thinHistoryThreshold

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.blockGap) {
            header
            metrics
            if !isOwnProfile { pairwise }
            recentTracks
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(verbatim: profile.member.displayName).typeStyle(.displayL).foregroundStyle(Palette.ink)
            Text(isOwnProfile ? "profile.subtitle.own" : "profile.subtitle.member")
                .typeStyle(.bodyM).foregroundStyle(Palette.inkDim)
        }
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel("profile.stats")
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Space.sm) { metricCards }
                VStack(alignment: .leading, spacing: Space.sm) { metricCards }
            }
        }
    }

    @ViewBuilder private var metricCards: some View {
        ProfileMetricCard(title: "results.ear.label", metric: profile.ear)
        ProfileMetricCard(title: "results.readability.label", metric: profile.readability)
        ProfileCountCard(count: profile.dropCount)
    }

    @ViewBuilder private var pairwise: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel("profile.pairwise")
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Space.sm) {
                    PairwiseReadCard(title: "profile.youread", read: profile.youReadThem)
                    PairwiseReadCard(title: "profile.theyread", read: profile.theyReadYou)
                }
                VStack(alignment: .leading, spacing: Space.sm) {
                    PairwiseReadCard(title: "profile.youread", read: profile.youReadThem)
                    PairwiseReadCard(title: "profile.theyread", read: profile.theyReadYou)
                }
            }
        }
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

private struct ProfileMetricCard: View {
    let title: LocalizedStringKey
    let metric: ProfileRateDTO

    private var hasEnoughHistory: Bool { metric.samples >= MemberProfileContent.minimumSamples }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionLabel(title)
            Text(verbatim: hasEnoughHistory ? ScoringFormat.percent(metric.value) : ScoringFormat.unavailable)
                .typeStyle(.displayM).foregroundStyle(Palette.ink)
            Text(verbatim: hasEnoughHistory
                 ? Copy.format("profile.samples", metric.samples)
                 : Copy.format("profile.samples.minimum", MemberProfileContent.minimumSamples))
                .typeStyle(.bodyS).foregroundStyle(Palette.inkDim).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: Radius.panel, inset: Layout.rowInset)
    }
}

private struct ProfileCountCard: View {
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionLabel("profile.drops")
            Text(verbatim: "\(count)").typeStyle(.displayM).foregroundStyle(Palette.ink)
            Text(verbatim: Copy.format("profile.drops.detail", count))
                .typeStyle(.bodyS).foregroundStyle(Palette.inkDim).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: Radius.panel, inset: Layout.rowInset)
    }
}

private struct PairwiseReadCard: View {
    let title: LocalizedStringKey
    let read: PairwiseReadDTO?

    private var enoughHistory: Bool { (read?.possible ?? 0) >= MemberProfileContent.minimumSamples }

    var body: some View {
        let detail = enoughHistory ? read : nil
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionLabel(title)
            Text(verbatim: enoughHistory ? ScoringFormat.percent(read?.rate) : ScoringFormat.unavailable)
                .typeStyle(.displayM).foregroundStyle(Palette.ink)
            Text(verbatim: detail.map { Copy.format("profile.pairwise.detail", $0.correct, $0.possible) }
                 ?? Copy.format("profile.pairwise.minimum", MemberProfileContent.minimumSamples))
                .typeStyle(.bodyS).foregroundStyle(Palette.inkDim).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: Radius.panel, inset: Layout.rowInset)
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
