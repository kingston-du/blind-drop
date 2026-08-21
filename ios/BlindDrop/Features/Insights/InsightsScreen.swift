import SwiftUI

/// Circle-scoped relationships, deliberately reached from the header menu rather than the daily
/// game path. Every number comes from scored rounds, and every named person leads to their
/// existing profile rather than creating a second social surface.
struct InsightsScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var store: InsightsStore?
    @State private var selectedMember: MemberDTO?

    var body: some View {
        Group {
            if let store { content(store) }
            else { RoundSkeleton().padding(Layout.screenInset) }
        }
        .background(Palette.paper)
        .navigationTitle("insights.title")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedMember) { MemberProfileScreen(member: $0) }
        .task {
            if store == nil { store = InsightsStore(api: env.api, circles: env.circles) }
            await store?.load()
        }
    }

    @ViewBuilder private func content(_ store: InsightsStore) -> some View {
        if store.state.isLoading && store.state.value == nil {
            RoundSkeleton().padding(Layout.screenInset)
        } else if let insights = store.state.value {
            ScrollView {
                InsightsContent(insights: insights, select: { selectedMember = $0 })
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

/// Value-driven content keeps snapshots focused on the exact surface a person sees.
struct InsightsContent: View {
    let insights: InsightsDTO
    var select: (MemberDTO) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.blockGap) {
            header
            yourReads
            mutualReads
            confusion
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("insights.title").typeStyle(.displayL).foregroundStyle(Palette.ink)
            Text("insights.subtitle").typeStyle(.bodyM).foregroundStyle(Palette.inkDim)
        }
    }

    private var yourReads: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel("insights.yourreads")
            InsightReadCard(title: "insights.youknow", read: insights.youKnowBest, select: select)
            InsightReadCard(title: "insights.knowsyou", read: insights.knowsYouBest, select: select)
            InsightReadCard(title: "insights.hardest", read: insights.hardestToRead, select: select)
        }
    }

    private var mutualReads: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel("insights.mutual")
            InsightPairList(title: "insights.mutual.recognition", pairs: insights.mutualRecognition, select: select)
            InsightPairList(title: "insights.mutual.misses", pairs: insights.mutualMisses, select: select)
        }
    }

    private var confusion: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel("insights.confusion")
            InsightConfusionList(confusion: insights.confusion, select: select)
        }
    }
}

private struct InsightReadCard: View {
    let title: LocalizedStringKey
    let read: InsightReadDTO?
    let select: (MemberDTO) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionLabel(title)
            if let read {
                Button { select(read.member) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                        Text(verbatim: read.member.displayName).typeStyle(.bodyLStrong).foregroundStyle(Palette.ink)
                        Spacer(minLength: Space.sm)
                        Text(verbatim: ScoringFormat.percent(read.rate)).typeStyle(.bodyLStrong).foregroundStyle(Palette.ink)
                        Image(systemName: "chevron.right").foregroundStyle(Palette.inkDim)
                    }
                    .minimumTouchTarget()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("insights.member.\(read.member.userID)")
                .accessibilityHint(Copy.string("insights.profile.hint"))
                Text(verbatim: Copy.format("insights.detail", read.correct, read.possible))
                    .typeStyle(.bodyS).foregroundStyle(Palette.inkDim)
            } else {
                Text("insights.empty").typeStyle(.bodyM).foregroundStyle(Palette.inkDim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: Radius.panel, inset: Layout.rowInset)
    }
}

private struct InsightPairList: View {
    let title: LocalizedStringKey
    let pairs: [InsightPairDTO]
    let select: (MemberDTO) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionLabel(title)
            if pairs.isEmpty {
                Text("insights.mutual.empty").typeStyle(.bodyM).foregroundStyle(Palette.inkDim)
            } else {
                VStack(spacing: Space.none) {
                    ForEach(pairs) { pair in
                        VStack(alignment: .leading, spacing: Space.xs) {
                            HStack(spacing: Space.xs) {
                                ForEach(Array(pair.members.enumerated()), id: \.element.userID) { index, member in
                                    if index > 0 {
                                        Text("insights.pair.separator").typeStyle(.bodyLStrong).foregroundStyle(Palette.ink)
                                    }
                                    Button { select(member) } label: {
                                        Text(verbatim: member.displayName).typeStyle(.bodyLStrong).foregroundStyle(Palette.ink)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("insights.member.\(member.userID)")
                                    .accessibilityHint(Copy.string("insights.profile.hint"))
                                }
                            }
                            Text(verbatim: Copy.format("insights.detail", pair.correct, pair.possible))
                                .typeStyle(.bodyS).foregroundStyle(Palette.inkDim)
                        }
                        .padding(.vertical, Space.sm)
                        if pair.id != pairs.last?.id { Rule() }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: Radius.panel, inset: Layout.rowInset)
    }
}

private struct InsightConfusionList: View {
    let confusion: InsightConfusionDTO
    let select: (MemberDTO) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if !confusion.hasEnoughHistory {
                Text(verbatim: Copy.format("insights.confusion.minimum", confusion.scoredRounds, confusion.minimumRounds))
                    .typeStyle(.bodyM).foregroundStyle(Palette.inkDim)
            } else if confusion.pairs.isEmpty {
                Text("insights.confusion.empty").typeStyle(.bodyM).foregroundStyle(Palette.inkDim)
            } else {
                VStack(spacing: Space.none) {
                    ForEach(confusion.pairs) { pair in
                        VStack(alignment: .leading, spacing: Space.xs) {
                            HStack(spacing: Space.xs) {
                                Button { select(pair.actualMember) } label: {
                                    Text(verbatim: pair.actualMember.displayName).typeStyle(.bodyLStrong).foregroundStyle(Palette.ink)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("insights.member.\(pair.actualMember.userID)")
                                .accessibilityHint(Copy.string("insights.profile.hint"))
                                Text("insights.confusion.as").typeStyle(.bodyM).foregroundStyle(Palette.inkDim)
                                Button { select(pair.mistakenForMember) } label: {
                                    Text(verbatim: pair.mistakenForMember.displayName).typeStyle(.bodyLStrong).foregroundStyle(Palette.ink)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("insights.member.\(pair.mistakenForMember.userID)")
                                .accessibilityHint(Copy.string("insights.profile.hint"))
                            }
                            Text(verbatim: Copy.format("insights.confusion.detail", pair.count))
                                .typeStyle(.bodyS).foregroundStyle(Palette.inkDim)
                        }
                        .padding(.vertical, Space.sm)
                        if pair.id != confusion.pairs.last?.id { Rule() }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: Radius.panel, inset: Layout.rowInset)
    }
}
