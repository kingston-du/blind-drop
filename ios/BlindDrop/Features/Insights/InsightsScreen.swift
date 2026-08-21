import SwiftUI

/// Circle-scoped relationships, deliberately reached from the header menu rather than the daily
/// game path. Every number comes from scored rounds, and every named person leads to their
/// existing profile rather than creating a second social surface.
struct InsightsScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var store: InsightsStore?
    @State private var selectedMember: MemberDTO?
    @State private var leaderboard: InsightLeaderboardTarget?

    var body: some View {
        Group {
            if let store { content(store) }
            else { InsightsSkeleton().padding(Layout.screenInset) }
        }
        .background(Palette.paper)
        .navigationTitle("insights.title")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedMember) { MemberProfileScreen(member: $0) }
        .navigationDestination(item: $leaderboard) { target in
            InsightLeaderboardScreen(target: target, select: { selectedMember = $0 })
        }
        .task {
            if store == nil { store = InsightsStore(api: env.api, circles: env.circles) }
            await store?.load()
        }
    }

    @ViewBuilder private func content(_ store: InsightsStore) -> some View {
        if store.state.isLoading && store.state.value == nil {
            InsightsSkeleton().padding(Layout.screenInset)
        } else if let insights = store.state.value {
            ScrollView {
                InsightsContent(
                    insights: insights,
                    select: { selectedMember = $0 },
                    openLeaderboard: { leaderboard = $0 }
                )
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
    var openLeaderboard: (InsightLeaderboardTarget) -> Void = { _ in }

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

    /// **One panel, not three** (`E28-08`) — the three cards used to be three separately
    /// bordered boxes under one heading, which is the cards-in-cards clutter the rest of this
    /// screen was drawn with too. A single ruled panel, one row per stat, is the shape
    /// `StandingsView.table` already gives a set of numbers; each row keeps its own centred
    /// content and its own tap targets, only the outer border is shared now.
    private var yourReads: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel("insights.yourreads")
            VStack(spacing: Space.none) {
                InsightReadCard(
                    titleKey: "insights.youknow", read: insights.youKnowBest,
                    entries: insights.yourReads, select: select, openLeaderboard: openLeaderboard
                )
                Rule()
                InsightReadCard(
                    titleKey: "insights.knowsyou", read: insights.knowsYouBest,
                    entries: insights.readsYou, select: select, openLeaderboard: openLeaderboard
                )
                Rule()
                InsightReadCard(
                    titleKey: "insights.hardest", read: insights.hardestToRead,
                    entries: insights.hardestToReadRanked, select: select, openLeaderboard: openLeaderboard
                )
            }
            .cardSurface(radius: Radius.panel, inset: Layout.rowInset)
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

/// One "Your reads" card, opened from a scored rate (`E28-07`). **The card itself is the tap
/// target for the leaderboard** — a centred percentage and name are what a glance is meant to
/// land on, with no chevron implying a single destination when the honest one is "see everyone,
/// ranked" — and the name is a second, nested control that goes straight to a profile instead,
/// the same "tap the person, not the row" split `FlightCard` already draws between its card tap
/// and its inline controls.
private struct InsightReadCard: View {
    let titleKey: String
    let read: InsightReadDTO?
    /// The full ranked set this card's stat is drawn from — already fetched, already sorted by
    /// the server (or, for "Hardest to read", re-sorted here off the same payload). Handed
    /// straight to the leaderboard rather than re-fetched, because it is the same list this
    /// card's own number came from.
    let entries: [InsightReadDTO]
    let select: (MemberDTO) -> Void
    let openLeaderboard: (InsightLeaderboardTarget) -> Void

    var body: some View {
        VStack(spacing: Space.xs) {
            SectionLabel(verbatim: Copy.string(titleKey))
            if let read {
                VStack(spacing: Space.xxs) {
                    Text(verbatim: ScoringFormat.percent(read.rate))
                        .typeStyle(.displayM).foregroundStyle(Palette.ink)
                    Button { select(read.member) } label: {
                        Text(verbatim: read.member.displayName).typeStyle(.bodyLStrong).foregroundStyle(Palette.ink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("insights.member.\(read.member.userID)")
                    Text(verbatim: Copy.format("insights.detail", read.correct, read.possible))
                        .typeStyle(.bodyS).foregroundStyle(Palette.inkDim)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    openLeaderboard(InsightLeaderboardTarget(kind: titleKey, titleKey: titleKey, entries: entries))
                }
                // One VoiceOver stop for the leaderboard tap, naming the whole card by its
                // number and its name — and the name is reachable a second way, as a genuine
                // child rather than a synthetic action, matching `FlightCard`'s own preview
                // control (`accessibilityChildren`) for the same reason: it is a real `Button`
                // drawn on screen, not a description of one.
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(verbatim:
                    "\(Copy.string(titleKey)): \(read.member.displayName), \(ScoringFormat.percent(read.rate))"))
                .accessibilityHint(Copy.string("insights.leaderboard.hint"))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    openLeaderboard(InsightLeaderboardTarget(kind: titleKey, titleKey: titleKey, entries: entries))
                }
                .accessibilityAction(named: Text(verbatim: Copy.string("insights.profile.hint"))) {
                    select(read.member)
                }
            } else {
                Text("insights.empty").typeStyle(.bodyM).foregroundStyle(Palette.inkDim)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.sm)
    }
}

/// A stat's full ranking, opened from its "Your reads" card. Second, third, last — every row
/// carries its own denominator, so a name near the bottom of a thin circle reads as *thin*
/// rather than as a verdict.
struct InsightLeaderboardTarget: Identifiable, Hashable {
    let kind: String
    let titleKey: String
    let entries: [InsightReadDTO]

    var id: String { kind }
}

struct InsightLeaderboardScreen: View {
    let target: InsightLeaderboardTarget
    let select: (MemberDTO) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.sm) {
                if target.entries.isEmpty {
                    Text("insights.empty").typeStyle(.bodyM).foregroundStyle(Palette.inkDim)
                } else {
                    VStack(spacing: Space.none) {
                        ForEach(Array(target.entries.enumerated()), id: \.element.id) { index, entry in
                            Button { select(entry.member) } label: {
                                HStack(spacing: Space.md) {
                                    Text(verbatim: "\(index + 1)")
                                        .typeStyle(.monoS).foregroundStyle(Palette.inkDim)
                                        .frame(minWidth: Space.xl, alignment: .leading)
                                    MonogramMark(name: entry.member.displayName, diameter: MonogramMark.compactDiameter)
                                    VStack(alignment: .leading, spacing: Space.xxs) {
                                        Text(verbatim: entry.member.displayName)
                                            .typeStyle(.bodyLStrong).foregroundStyle(Palette.ink)
                                        Text(verbatim: Copy.format("insights.detail", entry.correct, entry.possible))
                                            .typeStyle(.bodyS).foregroundStyle(Palette.inkDim)
                                    }
                                    Spacer(minLength: Space.sm)
                                    Text(verbatim: ScoringFormat.percent(entry.rate))
                                        .typeStyle(.bodyLStrong).foregroundStyle(Palette.ink)
                                }
                                .padding(.vertical, Space.sm)
                            }
                            .buttonStyle(.plain)
                            if entry.id != target.entries.last?.id { Rule() }
                        }
                    }
                    .cardSurface(radius: Radius.panel, inset: Layout.rowInset)
                }
            }
            .padding(Layout.screenInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.paper)
        .navigationTitle(Text(verbatim: Copy.string(target.titleKey)))
        .navigationBarTitleDisplayMode(.inline)
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
                    ForEach(Array(pairs.enumerated()), id: \.element.id) { index, pair in
                        // **A rank on the left, not centred names** (`E28-07`): the pair reads
                        // as one row in a small table — a position, who it is, how often — the
                        // same shape `StandingsView.table` already uses, rather than two names
                        // floating in the middle of the card with nothing anchoring them.
                        HStack(alignment: .top, spacing: Space.md) {
                            Text(verbatim: "\(index + 1)")
                                .typeStyle(.monoS).foregroundStyle(Palette.inkDim)
                                .frame(minWidth: Space.xl, alignment: .leading)
                            VStack(alignment: .leading, spacing: Space.xxs) {
                                HStack(spacing: Space.xs) {
                                    ForEach(Array(pair.members.enumerated()), id: \.element.userID) { memberIndex, member in
                                        if memberIndex > 0 {
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
            if confusion.pairs.isEmpty {
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

/// Insights' shape in `paperSunk` — three ruled panels, the sections this screen actually has
/// (`E28-08`). `RoundSkeleton` promised a round's three generic blocks; with `E28-06`'s in-place
/// refresh this is now seen once per visit, not on every return trip.
struct InsightsSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Layout.blockGap) {
            ForEach([Layout.buttonHeight * 4, Layout.buttonHeight * 2, Layout.buttonHeight * 2], id: \.self) { height in
                RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                    .fill(Palette.paperSunk)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
            }
        }
        .accessibilityHidden(true)
    }
}
