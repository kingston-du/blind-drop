import SwiftUI

/// A circle is a leaderboard first and a settings screen second. Admin-only controls are absent
/// for members; the server remains the authority for every mutation.
struct GroupScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var store: GroupStore?
    @State private var selectedMember: MemberDTO?

    var body: some View {
        Group {
            if let store { content(store) }
            else { RoundSkeleton().padding(Layout.screenInset) }
        }
        .background(Palette.paper)
        .navigationTitle(Text("group.title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedMember) { MemberProfilePlaceholder(member: $0) }
        .task {
            if store == nil { store = GroupStore(api: env.api, circles: env.circles) }
            await store?.load()
        }
    }

    @ViewBuilder private func content(_ store: GroupStore) -> some View {
        if store.state.isLoading {
            RoundSkeleton().padding(Layout.screenInset)
        } else if let error = store.state.error, store.group == nil {
            VStack(alignment: .leading, spacing: Layout.blockGap) {
                Text(LocalizedStringKey(error.copyKey)).typeStyle(.bodyM).foregroundStyle(Palette.inkDim)
                PrimaryButton("error.retry", fill: .neutral) { Task { await store.load() } }
            }
            .padding(Layout.screenInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if let group = store.group {
            GroupDetailView(
                group: group,
                bestEar: store.bestEar,
                readabilityByUserID: store.readabilityByUserID,
                unrankedMembers: store.unrankedMembers,
                standingsLoading: store.standings.isLoading && store.standings.value == nil,
                standingsErrorKey: store.standings.error?.copyKey,
                isThinHistory: store.isThinHistory,
                isSaving: store.isSaving,
                isLeaving: store.isLeaving,
                errorKey: store.errorKey,
                revealHourEffectiveFrom: store.revealHourEffectiveFrom,
                select: { selectedMember = $0 },
                onRetryStandings: { await store.load() },
                onSaveName: { await store.rename(to: $0) },
                onPickRevealHour: { await store.setRevealHour($0) },
                onLeave: {
                    guard await store.leave() else { return false }
                    env.router.path = []
                    return true
                }
            )
        }
    }
}

/// Value-driven content keeps the live screen and snapshot coverage on the same layout.
struct GroupDetailView: View {
    let group: GroupDTO
    var bestEar: [EarStandingDTO] = []
    var readabilityByUserID: [String: ReadabilityStandingDTO] = [:]
    var unrankedMembers: [MemberDTO] = []
    var standingsLoading = false
    var standingsErrorKey: String?
    var isThinHistory = false
    var isSaving = false
    var isLeaving = false
    var errorKey: String?
    var revealHourEffectiveFrom: String?
    var select: (MemberDTO) -> Void = { _ in }
    var onRetryStandings: () async -> Void = {}
    var onSaveName: (String) async -> Bool = { _ in true }
    var onPickRevealHour: (Int) async -> Bool = { _ in true }
    var onLeave: () async -> Bool = { true }

    @State private var nameField = ""
    @State private var nameDirty = false
    @State private var didSaveName = false
    @State private var confirmsLeaving = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.blockGap) {
                nameSection
                leaderboard
                details
                if let errorKey {
                    Text(LocalizedStringKey(errorKey)).typeStyle(.bodyM).foregroundStyle(Palette.alert)
                }
                Button("group.leave", role: .destructive) { confirmsLeaving = true }
                    .buttonStyle(.plain).typeStyle(.bodyL).foregroundStyle(Palette.alert)
                    .minimumTouchTarget().disabled(isLeaving)
            }
            .padding(Layout.screenInset)
        }
        .onAppear { nameField = group.name }
        .onChange(of: group.name) { _, new in if !nameDirty { nameField = new } }
        .alert("group.leave.confirm.title", isPresented: $confirmsLeaving) {
            Button("group.leave.confirm.action", role: .destructive) { Task { _ = await onLeave() } }
            Button("settings.cancel", role: .cancel) {}
        } message: { Text("group.leave.confirm.body") }
    }

    @ViewBuilder private var nameSection: some View {
        if group.isAdmin {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionLabel("group.name.label")
                InsetField("group.name.label", text: $nameField, isFocused: nameFocused)
                    .focused($nameFocused).textInputAutocapitalization(.words).submitLabel(.done)
                    .onChange(of: nameField) { _, _ in nameDirty = true; didSaveName = false }
                    .onSubmit { Task { await saveName() } }
                Text("group.name.help").typeStyle(.caption).foregroundStyle(Palette.inkDim)
                if didSaveName { Text("group.name.saved").typeStyle(.bodyM).foregroundStyle(Palette.inkDim) }
                PrimaryButton("group.name.save", fill: .neutral, isEnabled: canSaveName) { Task { await saveName() } }
            }
        } else {
            Text(verbatim: group.name).typeStyle(.displayM).foregroundStyle(Palette.ink)
        }
    }

    private var canSaveName: Bool {
        !isSaving && nameDirty && !nameField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private func saveName() async {
        guard canSaveName else { return }
        nameFocused = false
        if await onSaveName(nameField) { nameDirty = false; didSaveName = true }
    }

    @ViewBuilder private var leaderboard: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel("results.standings.ear")
            if standingsLoading {
                RoundSkeleton()
            } else if let standingsErrorKey {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text(LocalizedStringKey(standingsErrorKey)).typeStyle(.bodyM).foregroundStyle(Palette.inkDim)
                    PrimaryButton("error.retry", fill: .neutral) { Task { await onRetryStandings() } }
                }
            } else if isThinHistory {
                Text("group.standings.thin").typeStyle(.bodyM).foregroundStyle(Palette.inkDim)
                ForEach(group.members) { member in
                    MemberRosterRow(member: member, select: { select(member) })
                }
            } else {
                ForEach(bestEar) { standing in
                    if let member = group.members.first(where: { $0.userID == standing.userID }) {
                        MemberStandingRow(member: member, standing: standing,
                                          readability: readabilityByUserID[standing.userID], select: { select(member) })
                    }
                }
                ForEach(rosterMembers) { member in
                    MemberRosterRow(member: member, select: { select(member) })
                }
            }
        }
    }

    private var rosterMembers: [MemberDTO] {
        bestEar.isEmpty && unrankedMembers.isEmpty ? group.members : unrankedMembers
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Layout.blockGap) {
            if group.isAdmin { revealHourSection }
            timezoneSection
        }
    }

    private var revealHourSection: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel("group.revealhour.label")
            Menu {
                Picker("group.revealhour.label", selection: Binding(get: { group.revealHour }, set: { hour in
                    Task { await onPickRevealHour(hour) }
                })) {
                    ForEach(Array(RevealHour.allowed), id: \.self) { Text(verbatim: RevealHour.formatted($0)).tag($0) }
                }
            } label: { controlRow(chevron: true) { Text(verbatim: RevealHour.formatted(group.revealHour)) } }
            .disabled(isSaving).accessibilityLabel(Text("group.revealhour.label"))
            Text("group.revealhour.help").typeStyle(.caption).foregroundStyle(Palette.inkDim)
            if let effective = revealHourEffectiveFrom,
               let date = GroupCalendar(timezone: group.timezone).shareDate(localDate: effective) {
                Text(verbatim: Copy.format("group.revealhour.effective", date)).typeStyle(.bodyM).foregroundStyle(Palette.inkDim)
            }
        }
    }

    private var timezoneSection: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel("group.timezone.label")
            controlRow { Text(verbatim: TimezoneName.readable(group.timezone)) }
            Text("group.timezone.help").typeStyle(.caption).foregroundStyle(Palette.inkDim)
        }
    }

    private func controlRow(chevron: Bool = false, @ViewBuilder content: () -> some View) -> some View {
        HStack {
            content().typeStyle(.bodyL).foregroundStyle(Palette.ink)
            Spacer(minLength: Space.sm)
            if chevron { Image(systemName: "chevron.down").foregroundStyle(Palette.inkDim) }
        }
        .padding(.horizontal, Space.lg).frame(minHeight: Layout.buttonHeight).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).stroke(Palette.edge, lineWidth: Stroke.border))
    }
}

struct MemberStandingRow: View {
    let member: MemberDTO
    let standing: EarStandingDTO
    let readability: ReadabilityStandingDTO?
    let select: () -> Void
    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: Space.xs) {
                StandingRowContent(standing: standing, readability: readability)
                Text(member.isAdmin ? "group.role.admin" : "group.role.member")
                    .typeStyle(.caption).foregroundStyle(Palette.inkDim)
            }
            .frame(maxWidth: .infinity, alignment: .leading).rowSurface()
        }
        .buttonStyle(.plain).accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: StandingRowContent.announcement(standing: standing, readability: readability)))
        .accessibilityHint(Copy.string("a11y.group.row.hint")).accessibilityAddTraits(.isButton)
    }
}

struct MemberRosterRow: View {
    let member: MemberDTO
    let select: () -> Void
    var body: some View {
        Button(action: select) {
            HStack {
                Text(verbatim: member.displayName).typeStyle(.bodyL).foregroundStyle(Palette.ink)
                Spacer(minLength: Space.sm)
                Text(member.isAdmin ? "group.role.admin" : "group.role.member").typeStyle(.bodyM).foregroundStyle(Palette.inkDim)
            }
            .frame(maxWidth: .infinity, alignment: .leading).rowSurface()
        }
        .buttonStyle(.plain).accessibilityHint(Copy.string("a11y.group.row.hint")).accessibilityAddTraits(.isButton)
    }
}

struct MemberProfilePlaceholder: View {
    let member: MemberDTO
    var body: some View {
        Text("group.profile.placeholder").typeStyle(.bodyM).foregroundStyle(Palette.inkDim)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(Layout.screenInset)
            .background(Palette.paper).navigationTitle(Text(verbatim: member.displayName)).navigationBarTitleDisplayMode(.inline)
    }
}
