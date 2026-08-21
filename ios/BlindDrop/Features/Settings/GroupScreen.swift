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
            else { GroupSkeleton().padding(Layout.screenInset) }
        }
        .background(Palette.paper)
        .navigationTitle(Text("group.title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedMember) { MemberProfileScreen(member: $0) }
        .task {
            if store == nil { store = GroupStore(api: env.api, circles: env.circles) }
            await store?.load()
        }
    }

    // `E28-06`: the group renders whenever the store has one, `isLoading` or not — a store that
    // refreshes in place has a value on screen through its own refetch, and a skeleton drawn on
    // top of that would be the exact re-flash this fix removes.
    @ViewBuilder private func content(_ store: GroupStore) -> some View {
        if let group = store.group {
            GroupDetailView(
                group: group,
                roundsPlayed: store.roundsPlayed,
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
                },
                onOpenRecord: { env.router.path.append(.record) }
            )
        } else if store.state.isLoading {
            GroupSkeleton().padding(Layout.screenInset)
        } else if let error = store.state.error {
            VStack(alignment: .leading, spacing: Layout.blockGap) {
                Text(LocalizedStringKey(error.copyKey)).typeStyle(.bodyM).foregroundStyle(Palette.inkDim)
                PrimaryButton("error.retry", fill: .neutral) { Task { await store.load() } }
            }
            .padding(Layout.screenInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// Value-driven content keeps the live screen and snapshot coverage on the same layout.
struct GroupDetailView: View {
    let group: GroupDTO
    /// `nil` while standings have not loaded — `SheetMeta` below only prints the round count
    /// once it has something honest to say.
    var roundsPlayed: Int? = nil
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
    /// The Record's entry point, moved here from the header menu (`E28-06`, amendment A3) — a
    /// list of songs sits with the leaderboard it complements rather than beside the three
    /// screens the menu is otherwise for. `Route.record` and its deep link are unchanged.
    var onOpenRecord: () -> Void = {}
    /// Test-only construction path. It keeps snapshots on the same hierarchy while omitting the
    /// `ScrollView` and UIKit-backed controls `ImageRenderer` cannot draw.
    var rendersForSnapshot = false

    @State private var nameField = ""
    @State private var didSaveName = false
    @State private var confirmsLeaving = false
    @State private var memberToRemove: MemberDTO?
    @FocusState private var nameFocused: Bool

    var body: some View {
        Group {
            if rendersForSnapshot {
                content(isSnapshot: true)
            } else {
                ScrollView {
                    content(isSnapshot: false).padding(Layout.screenInset)
                }
            }
        }
        .onAppear { nameField = group.name }
        // Only follows the server when the field still shows what the server last said —
        // `E28-06` dropped the separate `nameDirty` flag in favour of comparing `nameField`
        // against `group.name` directly, and this is the one place that still needs to tell "the
        // caller is mid-edit" apart from "nothing has changed here yet": `old` is what `nameField`
        // was set from the last time this ran, so a field that still matches it is untouched.
        .onChange(of: group.name) { old, new in if nameField == old { nameField = new } }
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

    /// `ImageRenderer` silently omits a `ScrollView`; snapshots render this same column bare.
    /// The outer renderer supplies the screen inset, matching `body` without baking a scroll
    /// container that would turn a meaningful golden into blank paper.
    var snapshotContent: some View { content(isSnapshot: true) }

    // **Order** (`E28-06`): leaderboard first — it is what a circle is for — then the name a
    // person can change, then the reveal hour and timezone that describe when the game happens,
    // then The Record, then Leave, which stays last as the one destructive action on the screen.
    @ViewBuilder private func content(isSnapshot: Bool) -> some View {
        VStack(alignment: .leading, spacing: Layout.blockGap) {
            SheetMeta(text: meta)
            leaderboard(isSnapshot: isSnapshot)
            nameSection(isSnapshot: isSnapshot)
            details(isSnapshot: isSnapshot)
            recordLink
            if let errorKey {
                Text(LocalizedStringKey(errorKey)).typeStyle(.bodyM).foregroundStyle(Palette.alert)
            }
            Button("group.leave", role: .destructive) { confirmsLeaving = true }
                .buttonStyle(.plain).typeStyle(.bodyL).foregroundStyle(Palette.alert)
                .minimumTouchTarget().disabled(isLeaving)
        }
    }

    /// `12 MEMBERS · 144 ROUNDS` — `SheetMeta`'s fact, standing in for the sentence a subtitle
    /// used to be (`E28-08`). Member count is always known; the round count waits for standings.
    private var meta: String {
        let members = Copy.format("group.meta.members", group.members.count)
        guard let roundsPlayed else { return members.uppercased() }
        return "\(members) · \(Copy.format("group.meta.rounds", roundsPlayed))".uppercased()
    }

    private var recordLink: some View {
        Button(action: onOpenRecord) {
            HStack {
                Text("record.title").typeStyle(.bodyL).foregroundStyle(Palette.ink)
                Spacer(minLength: Space.sm)
                Image(systemName: "chevron.right").foregroundStyle(Palette.inkDim)
            }
            .minimumTouchTarget()
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func nameSection(isSnapshot: Bool) -> some View {
        if group.isAdmin {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionLabel("group.name.label")
                if isSnapshot {
                    controlRow { Text(verbatim: group.name) }
                } else {
                    InsetField("group.name.label", text: $nameField, isFocused: nameFocused)
                        .focused($nameFocused).textInputAutocapitalization(.words).submitLabel(.done)
                        .onChange(of: nameField) { _, _ in didSaveName = false }
                        .onSubmit { Task { await saveName() } }
                }
                if didSaveName { Text("group.name.saved").typeStyle(.bodyM).foregroundStyle(Palette.inkDim) }
                PrimaryButton("group.name.save", fill: .neutral, isEnabled: canSaveName) { Task { await saveName() } }
            }
        } else {
            Text(verbatim: group.name).typeStyle(.displayM).foregroundStyle(Palette.ink)
        }
    }

    // `E28-06`: disabled until an actual keystroke changes the field, the same rule Settings'
    // display name save already follows — comparing against `group.name` directly rather than a
    // separate flag means there is nothing to forget to set.
    private var canSaveName: Bool {
        !isSaving && nameField != group.name
            && !nameField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private func saveName() async {
        guard canSaveName else { return }
        nameFocused = false
        if await onSaveName(nameField) { didSaveName = true }
    }

    @ViewBuilder private func leaderboard(isSnapshot: Bool) -> some View {
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
                    MemberRosterRow(member: member, actions: memberActions(for: member), rendersForSnapshot: isSnapshot,
                                    managementDisabled: isManagingMember || isSaving, select: { select(member) },
                                    manage: { manage($0, member: member) })
                }
            } else {
                ForEach(bestEar) { standing in
                    if let member = group.members.first(where: { $0.userID == standing.userID }) {
                        MemberStandingRow(member: member, standing: standing,
                                          readability: readabilityByUserID[standing.userID],
                                          actions: memberActions(for: member), rendersForSnapshot: isSnapshot,
                                          managementDisabled: isManagingMember || isSaving, select: { select(member) },
                                          manage: { manage($0, member: member) })
                    }
                }
                ForEach(rosterMembers) { member in
                    MemberRosterRow(member: member, actions: memberActions(for: member), rendersForSnapshot: isSnapshot,
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

    private func details(isSnapshot: Bool) -> some View {
        VStack(alignment: .leading, spacing: Layout.blockGap) {
            if group.isAdmin { revealHourSection(isSnapshot: isSnapshot) }
            timezoneSection
        }
    }

    private func revealHourSection(isSnapshot: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel("group.revealhour.label")
            if isSnapshot {
                controlRow(chevron: true) { Text(verbatim: RevealHour.formatted(group.revealHour)) }
            } else {
                Menu {
                    Picker("group.revealhour.label", selection: Binding(get: { group.revealHour }, set: { hour in
                        Task { await onPickRevealHour(hour) }
                    })) {
                        ForEach(Array(RevealHour.allowed), id: \.self) { Text(verbatim: RevealHour.formatted($0)).tag($0) }
                    }
                } label: { controlRow(chevron: true) { Text(verbatim: RevealHour.formatted(group.revealHour)) } }
                .disabled(isSaving).accessibilityLabel(Text("group.revealhour.label"))
            }
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
    var rendersForSnapshot = false
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
            if !actions.isEmpty {
                MemberActionMenu(actions: actions, disabled: managementDisabled,
                                 rendersForSnapshot: rendersForSnapshot, manage: manage)
            }
        }
        .rowSurface()
    }
}

struct MemberRosterRow: View {
    let member: MemberDTO
    var actions: [MemberManagementAction] = []
    var rendersForSnapshot = false
    var managementDisabled = false
    let select: () -> Void
    var manage: (MemberManagementAction) -> Void = { _ in }
    var body: some View {
        HStack(spacing: Space.sm) {
            Button(action: select) {
                HStack(spacing: Space.sm) {
                    MonogramMark(name: member.displayName, diameter: MonogramMark.compactDiameter)
                    Text(verbatim: member.displayName).typeStyle(.bodyL).foregroundStyle(Palette.ink)
                    Spacer(minLength: Space.sm)
                    Text(member.isAdmin ? "group.role.admin" : "group.role.member").typeStyle(.bodyM).foregroundStyle(Palette.inkDim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain).accessibilityHint(Copy.string("a11y.group.row.hint")).accessibilityAddTraits(.isButton)
            if !actions.isEmpty {
                MemberActionMenu(actions: actions, disabled: managementDisabled,
                                 rendersForSnapshot: rendersForSnapshot, manage: manage)
            }
        }
        .rowSurface()
    }
}

struct MemberActionMenu: View {
    let actions: [MemberManagementAction]
    let disabled: Bool
    let rendersForSnapshot: Bool
    let manage: (MemberManagementAction) -> Void

    var body: some View {
        Group {
            if rendersForSnapshot {
                glyph
            } else {
                Menu {
                    ForEach(actions) { action in
                        Button(action.titleKey, role: action == .remove ? .destructive : nil) { manage(action) }
                    }
                } label: { glyph }
                .accessibilityLabel(Text("group.member.actions"))
            }
        }
        .disabled(disabled)
    }

    private var glyph: some View {
        Image(systemName: "ellipsis.circle").foregroundStyle(Palette.inkDim).minimumTouchTarget()
    }
}

/// The group's shape in `paperSunk` — a meta line, a stack of ranked rows, a settings block
/// (`E28-08`). `RoundSkeleton` promised a round's three generic blocks, the wrong shape for a
/// leaderboard; with `E28-06`'s in-place refresh this is now seen once per visit, not on return.
struct GroupSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Layout.blockGap) {
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Palette.paperSunk).frame(width: Space.x6 * 2, height: Layout.itemGap)
            RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                .fill(Palette.paperSunk).frame(height: Layout.buttonHeight * 4)
            RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                .fill(Palette.paperSunk).frame(height: Layout.buttonHeight * 2)
        }
        .accessibilityHidden(true)
    }
}
