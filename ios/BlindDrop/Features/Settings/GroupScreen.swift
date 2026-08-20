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
                isManagingMember: store.isManagingMember,
                errorKey: store.errorKey,
                revealHourEffectiveFrom: store.revealHourEffectiveFrom,
                currentUserID: env.session.user?.userID,
                select: { selectedMember = $0 },
                onRetryStandings: { await store.load() },
                onSaveName: { await store.rename(to: $0) },
                onPickRevealHour: { await store.setRevealHour($0) },
                onSetRole: { member, role in await store.setRole(role, for: member.userID) },
                onRemove: { member in await store.remove(member.userID) },
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
    var isManagingMember = false
    var errorKey: String?
    var revealHourEffectiveFrom: String?
    var currentUserID: String?
    var select: (MemberDTO) -> Void = { _ in }
    var onRetryStandings: () async -> Void = {}
    var onSaveName: (String) async -> Bool = { _ in true }
    var onPickRevealHour: (Int) async -> Bool = { _ in true }
    var onSetRole: (MemberDTO, String) async -> Bool = { _, _ in true }
    var onRemove: (MemberDTO) async -> Bool = { _ in true }
    var onLeave: () async -> Bool = { true }

    @State private var nameField = ""
    @State private var nameDirty = false
    @State private var didSaveName = false
    @State private var confirmsLeaving = false
    @State private var memberToRemove: MemberDTO?
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
        .alert(Text(verbatim: Copy.format("group.member.remove.confirm.title", memberToRemove?.displayName ?? "")), isPresented: removalConfirmation) {
            Button("group.member.remove.confirm.action", role: .destructive) {
                guard let memberToRemove else { return }
                Task { _ = await onRemove(memberToRemove) }
            }
            Button("settings.cancel", role: .cancel) {}
        } message: {
            Text(verbatim: Copy.format("group.member.remove.confirm.body", memberToRemove?.displayName ?? ""))
        }
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
                    MemberRosterRow(member: member, actions: memberActions(for: member),
                                    managementDisabled: isManagingMember || isSaving, select: { select(member) },
                                    manage: { manage($0, member: member) })
                }
            } else {
                ForEach(bestEar) { standing in
                    if let member = group.members.first(where: { $0.userID == standing.userID }) {
                        MemberStandingRow(member: member, standing: standing,
                                          readability: readabilityByUserID[standing.userID],
                                          actions: memberActions(for: member),
                                          managementDisabled: isManagingMember || isSaving, select: { select(member) },
                                          manage: { manage($0, member: member) })
                    }
                }
                ForEach(rosterMembers) { member in
                    MemberRosterRow(member: member, actions: memberActions(for: member),
                                    managementDisabled: isManagingMember || isSaving, select: { select(member) },
                                    manage: { manage($0, member: member) })
                }
            }
        }
    }

    private var rosterMembers: [MemberDTO] {
        bestEar.isEmpty && unrankedMembers.isEmpty ? group.members : unrankedMembers
    }

    private var removalConfirmation: Binding<Bool> {
        Binding(get: { memberToRemove != nil }, set: { if !$0 { memberToRemove = nil } })
    }

    private func memberActions(for member: MemberDTO) -> [MemberManagementAction] {
        guard group.isAdmin else { return [] }
        let isCurrentUser = member.userID == currentUserID
        let adminCount = group.members.filter(\.isAdmin).count
        var actions: [MemberManagementAction] = []
        if member.isAdmin {
            if adminCount > 1 { actions.append(.demote) }
        } else {
            actions.append(.promote)
        }
        // Leaving is the caller's explicit, already-confirmed removal flow. Every other active
        // member can be removed here; the server enforces the same rule against stale clients.
        if !isCurrentUser { actions.append(.remove) }
        return actions
    }

    private func manage(_ action: MemberManagementAction, member: MemberDTO) {
        switch action {
        case .promote: Task { _ = await onSetRole(member, "admin") }
        case .demote: Task { _ = await onSetRole(member, "member") }
        case .remove: memberToRemove = member
        }
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

enum MemberManagementAction: String, Identifiable {
    case promote, demote, remove

    var id: String { rawValue }
    var titleKey: LocalizedStringKey {
        switch self {
        case .promote: "group.member.promote"
        case .demote: "group.member.demote"
        case .remove: "group.member.remove"
        }
    }
}

struct MemberStandingRow: View {
    let member: MemberDTO
    let standing: EarStandingDTO
    let readability: ReadabilityStandingDTO?
    var actions: [MemberManagementAction] = []
    var managementDisabled = false
    let select: () -> Void
    var manage: (MemberManagementAction) -> Void = { _ in }
    var body: some View {
        HStack(spacing: Space.sm) {
            Button(action: select) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    StandingRowContent(standing: standing, readability: readability)
                    Text(member.isAdmin ? "group.role.admin" : "group.role.member")
                        .typeStyle(.caption).foregroundStyle(Palette.inkDim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain).accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: StandingRowContent.announcement(standing: standing, readability: readability)))
            .accessibilityHint(Copy.string("a11y.group.row.hint")).accessibilityAddTraits(.isButton)
            if !actions.isEmpty { MemberActionMenu(actions: actions, disabled: managementDisabled, manage: manage) }
        }
        .rowSurface()
    }
}

struct MemberRosterRow: View {
    let member: MemberDTO
    var actions: [MemberManagementAction] = []
    var managementDisabled = false
    let select: () -> Void
    var manage: (MemberManagementAction) -> Void = { _ in }
    var body: some View {
        HStack(spacing: Space.sm) {
            Button(action: select) {
                HStack {
                    Text(verbatim: member.displayName).typeStyle(.bodyL).foregroundStyle(Palette.ink)
                    Spacer(minLength: Space.sm)
                    Text(member.isAdmin ? "group.role.admin" : "group.role.member").typeStyle(.bodyM).foregroundStyle(Palette.inkDim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain).accessibilityHint(Copy.string("a11y.group.row.hint")).accessibilityAddTraits(.isButton)
            if !actions.isEmpty { MemberActionMenu(actions: actions, disabled: managementDisabled, manage: manage) }
        }
        .rowSurface()
    }
}

struct MemberActionMenu: View {
    let actions: [MemberManagementAction]
    let disabled: Bool
    let manage: (MemberManagementAction) -> Void

    var body: some View {
        Menu {
            ForEach(actions) { action in
                Button(action.titleKey, role: action == .remove ? .destructive : nil) { manage(action) }
            }
        } label: {
            Image(systemName: "ellipsis.circle").foregroundStyle(Palette.inkDim).minimumTouchTarget()
        }
        .accessibilityLabel(Text("group.member.actions"))
        .disabled(disabled)
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
