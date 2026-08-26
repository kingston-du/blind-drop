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
            if store == nil {
                store = env.routeStores.insightsStore(for: await env.circles.resolveActiveID())
            }
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
            Text("insights.headline").typeStyle(.displayL).foregroundStyle(Palette.ink)
            Text("insights.subtitle").typeStyle(.bodyM).foregroundStyle(Palette.inkDim)
        }
    }

    /// Three cards, not one ruled panel — a relationship is a thing with a person on it, and each
    /// one gets its own surface so the name and the rate read together. The two strong reads take
    /// the revealed-data accent; the low one takes `inkSubtle`, because a low read is still data.
    private var yourReads: some View {
        VStack(alignment: .leading, spacing: Layout.itemGap) {
            InsightReadCard(
                titleKey: "insights.youknow", read: insights.youKnowBest,
                entries: insights.yourReads, accent: Palette.ultramarine,
                select: select, openLeaderboard: openLeaderboard
            )
            InsightReadCard(
                titleKey: "insights.knowsyou", read: insights.knowsYouBest,
                entries: insights.readsYou, accent: Palette.ultramarine,
                select: select, openLeaderboard: openLeaderboard
            )
            InsightReadCard(
                titleKey: "insights.hardest", read: insights.hardestToRead,
                entries: insights.hardestToReadRanked, accent: Palette.inkSubtle,
                select: select, openLeaderboard: openLeaderboard
            )
        }
    }

    private var mutualReads: some View {
        VStack(alignment: .leading, spacing: Layout.itemGap) {
            InsightPairList(title: "insights.mutual.recognition", pairs: insights.mutualRecognition, accent: Palette.ultramarine, select: select)
            InsightPairList(title: "insights.mutual.misses", pairs: insights.mutualMisses, accent: Palette.inkSubtle, select: select)
        }
    }

    private var confusion: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel("insights.confusion")
            InsightConfusionList(confusion: insights.confusion, select: select)
        }
    }
}

/// One "Your reads" card, now drawn the way the flight sheet draws a person — the name is the
/// hero figure and the rate is the comparable numeral beside it, with the proportion bar
/// underneath. **The card itself is the tap target for the leaderboard**, and the name is a
/// second, nested control that goes straight to a profile instead, the same "tap the person, not
/// the row" split `FlightCard` already draws between its card tap and its inline controls.
private struct InsightReadCard: View {
    let titleKey: String
    let read: InsightReadDTO?
    /// The full ranked set this card's stat is drawn from — already fetched, already sorted by
    /// the server (or, for "Hardest to read", re-sorted here off the same payload). Handed
    /// straight to the leaderboard rather than re-fetched, because it is the same list this
    /// card's own number came from.
    let entries: [InsightReadDTO]
    /// The revealed-data accent for the two strong reads; `inkSubtle` for the low one.
    let accent: Color
    let select: (MemberDTO) -> Void
    let openLeaderboard: (InsightLeaderboardTarget) -> Void

    var body: some View {
        Group {
            if let read {
                VStack(alignment: .leading, spacing: Space.sm) {
                    SectionLabel(verbatim: Copy.string(titleKey))
                    HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                        Button { select(read.member) } label: {
                            Text(verbatim: read.member.displayName)
                                .typeStyle(.displayS).foregroundStyle(Palette.ink)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("insights.member.\(read.member.userID)")
                        Spacer(minLength: Space.sm)
                        Text(verbatim: ScoringFormat.percent(read.rate))
                            .typeStyle(.numberM).foregroundStyle(accent)
                    }
                    ProportionTrack(progress: read.rate, fill: accent)
                    Text(verbatim: Copy.format("insights.detail", read.correct, read.possible))
                        .typeStyle(.bodyS).foregroundStyle(Palette.inkDim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .cardSurface(radius: Radius.panel, inset: Space.lg)
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
    /// The revealed-data accent for "they read each other"; `inkSubtle` for "neither has read
    /// the other", whose rate is zero by definition.
    let accent: Color
    let select: (MemberDTO) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionLabel(title)
            if pairs.isEmpty {
                Text("insights.mutual.empty").typeStyle(.bodyM).foregroundStyle(Palette.inkDim)
            } else {
                VStack(spacing: Space.none) {
                    ForEach(pairs) { pair in
                        // A list row, not a card: the names and their denominator lead, and the
                        // rate rides the trailing edge in the data voice.
                        HStack(spacing: Space.md) {
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
                            Spacer(minLength: Space.sm)
                            Text(verbatim: ScoringFormat.percent(pair.rate))
                                .typeStyle(.monoM).foregroundStyle(accent)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                        // Names on the leading edge, the count as a large display-face numeral on
                        // the trailing edge — the same number language the percentage bars above
                        // speak, so "5 times" reads as a fact of the same weight as a percentage.
                        HStack(alignment: .top, spacing: Space.md) {
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
                            Spacer(minLength: Space.sm)
                            VStack(alignment: .trailing, spacing: Space.none) {
                                Text(verbatim: "\(pair.count)")
                                    .typeStyle(.numberM).foregroundStyle(Palette.ink)
                                Text("insights.confusion.times")
                                    .typeStyle(.bodyS).foregroundStyle(Palette.inkDim)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(verbatim: Copy.format("insights.confusion.detail", pair.count)))
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
