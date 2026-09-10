import SwiftUI
import UIKit

/// A circle is a leaderboard first and a settings screen second. Admin-only controls are absent
/// for members; the server remains the authority for every mutation.
struct GroupScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var store: GroupStore?
    @State private var selectedMember: MemberDTO?
    /// `E38-03`. Built once and held, so an invitation already sent survives a refresh of the
    /// group underneath it — a row that reverted from *Share invite* back to *Invite* would be
    /// telling somebody to do again what they have already done.
    @State private var inviteStore: InviteStore?

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
            if store == nil {
                store = env.routeStores.groupStore(for: await env.circles.resolveActiveID())
            }
            inviteStore = inviteStore ?? InviteStore(api: env.api)
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
                // `E28-06`'s rule, which the loading line above already applies, applied to the
                // failing one as well: a refresh that fails over standings we are **holding**
                // is `LoadState.stale`, and `stale` is shown *with* the data, never instead of
                // it. Passing the error through unconditionally meant walking out of signal on
                // The Group replaced a leaderboard that was on screen a second ago with *You're
                // offline* and a Retry button — the circle's own settings still rendering below
                // it, so it read as half the screen having crashed.
                standingsErrorKey: store.standings.value == nil ? store.standings.error?.copyKey : nil,
                isThinHistory: store.isThinHistory,
                isSaving: store.isSaving,
                isLeaving: store.isLeaving,
                isManagingMember: store.isManagingMember,
                errorKey: store.errorKey,
                cueEffectiveFrom: store.cueEffectiveFrom,
                serverNow: env.clock.now,
                currentUserID: env.session.user?.userID,
                select: { selectedMember = $0 },
                onRetryStandings: { await store.load() },
                onSaveName: { await store.rename(to: $0) },
                onPickRevealHour: { await store.setRevealHour($0) },
                onPickCueCadence: { await store.setCueCadence($0) },
                onSetNextCue: { await store.setNextCue($0) },
                onClearNextCue: { await store.clearNextCue() },
                onSetRole: { member, role in await store.setRole(role, for: member.userID) },
                onRemove: { member in await store.remove(member.userID) },
                onLeave: {
                    guard await store.leave() else { return false }
                    env.router.path = []
                    return true
                },
                onOpenRecord: { env.router.path.append(.record) },
                invites: inviteStore
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
    var cueEffectiveFrom: String?
    /// `ServerClock`'s reading, not `Date()` (`CLAUDE.md` §2.2). The next-cue row turns
    /// read-only at an instant the server owns, so deciding it against the device's wall clock
    /// would let a skewed phone offer an edit the server refuses — or withhold one it would
    /// have allowed. `nil` while the clock is unanchored, which the row treats as "cannot say
    /// yet" and reads as locked rather than inviting a write that may already be too late.
    var serverNow: Date?
    var currentUserID: String?
    var select: (MemberDTO) -> Void = { _ in }
    var onRetryStandings: () async -> Void = {}
    var onSaveName: (String) async -> Bool = { _ in true }
    var onPickRevealHour: (Int) async -> Bool = { _ in true }
    var onPickCueCadence: (Int) async -> Bool = { _ in true }
    var onSetNextCue: (String) async -> Bool = { _ in true }
    var onClearNextCue: () async -> Bool = { true }
    var onSetRole: (MemberDTO, String) async -> Bool = { _, _ in true }
    var onRemove: (MemberDTO) async -> Bool = { _ in true }
    var onLeave: () async -> Bool = { true }
    /// The Record's entry point, moved here from the header menu (`E28-06`, amendment A3) — a
    /// list of songs sits with the leaderboard it complements rather than beside the three
    /// screens the menu is otherwise for, and in the header rather than at the foot so it is
    /// next to the fact that introduces the standings. `Route.record` and its deep link are
    /// unchanged.
    var onOpenRecord: () -> Void = {}
    /// The invite panel's store (`E38-03`). Optional so the snapshot suite can render the screen
    /// without one — the panel is a live network surface, and a golden of it belongs to the panel
    /// rather than to every group golden.
    var invites: InviteStore?
    /// Test-only construction path. It keeps snapshots on the same hierarchy while omitting the
    /// `ScrollView` and UIKit-backed controls `ImageRenderer` cannot draw.
    var rendersForSnapshot = false

    @State private var nameField = ""
    @State private var didSaveName = false
    /// Whether `nameField` has been seeded from the circle yet. See the `onAppear` below.
    @State private var hasSeededName = false
    @State private var confirmsLeaving = false
    @State private var editsNextCue = false
    @State private var memberToRemove: MemberDTO?
    @FocusState private var nameFocused: Bool

    var body: some View {
        Group {
            if rendersForSnapshot {
                content(isSnapshot: true)
            } else {
                ScrollView {
                    content(isSnapshot: false)
                        .padding(Layout.screenInset)
                        .background(ScrollViewTouchesProbe().frame(width: .zero, height: .zero))
                }
            }
        }
        // **Seeded once, not on every appearance.** `onAppear` fires again when a pushed
        // destination is popped, and this used to overwrite unconditionally: an admin who typed
        // a new circle name, tapped a member row to check something and came back found the
        // field silently reverted and **Save** disabled again. The server's own updates already
        // have a route in — the guarded `onChange` below, which is careful *not* to do this to a
        // field somebody is editing.
        .onAppear {
            guard !hasSeededName else { return }
            hasSeededName = true
            nameField = group.name
        }
        // Only follows the server when the field still shows what the server last said —
        // `E28-06` dropped the separate `nameDirty` flag in favour of comparing `nameField`
        // against `group.name` directly, and this is the one place that still needs to tell "the
        // caller is mid-edit" apart from "nothing has changed here yet": `old` is what `nameField`
        // was set from the last time this ran, so a field that still matches it is untouched.
        .onChange(of: group.name) { old, new in if nameField == old { nameField = new } }
        .sheet(isPresented: $editsNextCue) {
            NextCueSheet(
                cue: group.nextCue,
                isSaving: isSaving,
                // The screen's own error line is *behind* this sheet, so a refused write would
                // otherwise read as the button doing nothing at all — which is exactly how it
                // read the first time it was exercised against a server that said no.
                errorKey: errorKey,
                onSave: onSetNextCue,
                onReset: onClearNextCue
            )
        }
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

    // **Order** (`E28-06`, `E28-08`): the meta fact and The Record's entry point share the header
    // row, then the leaderboard — what a circle is for — then the name a person can change, then
    // the reveal hour and timezone that describe when the game happens, then Leave, which stays
    // last as the one destructive action on the screen.
    @ViewBuilder private func content(isSnapshot: Bool) -> some View {
        VStack(alignment: .leading, spacing: Layout.blockGap) {
            SheetMeta(text: meta) { recordButton }
            leaderboard(isSnapshot: isSnapshot)
            inviteSection
            nameSection(isSnapshot: isSnapshot)
            details(isSnapshot: isSnapshot)
            if let errorKey {
                Text(LocalizedStringKey(errorKey)).typeStyle(.bodyM).foregroundStyle(Palette.alert)
            }
            Button("group.leave", role: .destructive) { confirmsLeaving = true }
                .buttonStyle(.plain).typeStyle(.bodyL).foregroundStyle(Palette.alert)
                .minimumTouchTarget().disabled(isLeaving)
        }
    }

    /// **How the circle grows** (`E38-03`). Directly under the leaderboard, because the
    /// leaderboard is who is here and this is how somebody else gets to be: the two are one
    /// subject, and the name, reveal hour and timezone below them are a different one.
    ///
    /// `docs/08` §9 said this screen *"still carries no submitted state, join date, or invite
    /// code"*. The invite code half of that is amended here — and it costs no new data, because
    /// `GET /groups/{group_id}` has always returned `invite_code` and `GroupDTO` has always
    /// decoded it. Nothing leaked by drawing it: a code is not a member's state, carries no
    /// count, and is safe in every round phase, which is what made the original sentence about
    /// the *data source* rather than about this one field.
    ///
    /// Quiet emphasis: this screen's subject is the standings above it, and a full-weight black
    /// button for an errand would outrank them.
    @ViewBuilder private var inviteSection: some View {
        if let invites {
            InvitePanel(
                groupID: group.id,
                inviteCode: group.inviteCode,
                store: invites,
                emphasis: .quiet
            )
            .task { await invites.load(excluding: Set(group.members.map(\.userID)), in: group.id) }
        }
    }

    /// `12 MEMBERS · 144 ROUNDS` — `SheetMeta`'s fact, standing in for the sentence a subtitle
    /// used to be (`E28-08`). Member count is always known; the round count waits for standings.
    private var meta: String {
        let members = Copy.format("group.meta.members", group.members.count)
        guard let roundsPlayed else { return members.uppercased() }
        return "\(members) · \(Copy.format("group.meta.rounds", roundsPlayed))".uppercased()
    }

    /// The Record's entry point, in the header's top-right corner beside the meta fact. A pill
    /// chip rather than a bare link: `surface` + `edge` is the app's only elevation, so the chip
    /// reads as a raised control, and the `music.note.list` glyph is the archive itself — a list
    /// of every song dropped. The chevron keeps the app's "this pushes a screen" affordance.
    private var recordButton: some View {
        Button(action: onOpenRecord) {
            HStack(spacing: Space.xs) {
                Image(systemName: "music.note.list")
                    .font(Font(Typography.uiFont(.bodyM)))
                    .foregroundStyle(Palette.inkDim)
                Text("record.title")
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.ink)
                Image(systemName: "chevron.right")
                    .font(Font(Typography.uiFont(.bodyM)))
                    .foregroundStyle(Palette.inkDim)
            }
            .padding(.horizontal, Space.md)
            .frame(minHeight: Layout.chipHeight)
            .background(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous).fill(Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous).stroke(Palette.edge, lineWidth: Stroke.border))
            // 38pt drawn, 44pt tapped — the chip's breathing room is part of its hit region, the
            // same contract `NameChip` keeps so a row of targets has no dead gaps (`docs/12` §5).
            .frame(minHeight: Layout.minimumTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
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
                                          isCurrentUser: member.userID == currentUserID,
                                          reservesActionSlot: group.isAdmin,
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
            cueSection(isSnapshot: isSnapshot)
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
            // The circle's own answer, on every read — not a field that only existed in the reply
            // to the change and was gone the next time this screen opened (`docs/04` §3). `nil` is
            // the ordinary case: the hour on the row above is the hour tonight will use, and there
            // is nothing to wait for, so the line is absent rather than reassuring.
            if let effective = group.revealEffectiveFrom,
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

    /// The cue cadence row (`docs/18-CUES.md` §10): admin-editable like the reveal hour, but —
    /// unlike the reveal hour — **visible to members as static text**, because the cue's cadence
    /// is a fact about what a member can expect on any given night, not a scheduling control only
    /// the admin operates. The "Starts %@" line stays admin-only, since only an admin can change
    /// the cadence and therefore only they have a change to date.
    private func cueSection(isSnapshot: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel("settings.cue.title")
            if group.isAdmin {
                if isSnapshot {
                    controlRow(chevron: true) { Text(CueCadence.label(group.cueCadence)) }
                } else {
                    Menu {
                        Picker("settings.cue.title", selection: Binding(get: { group.cueCadence }, set: { cadence in
                            Task { await onPickCueCadence(cadence) }
                        })) {
                            ForEach(CueCadence.options, id: \.self) { Text(CueCadence.label($0)).tag($0) }
                        }
                    } label: { controlRow(chevron: true) { Text(CueCadence.label(group.cueCadence)) } }
                    .disabled(isSaving).accessibilityLabel(Text("settings.cue.title"))
                }
            } else {
                controlRow { Text(CueCadence.label(group.cueCadence)) }
            }
            if group.isAdmin, let effective = cueEffectiveFrom,
               let date = GroupCalendar(timezone: group.timezone).shareDate(localDate: effective) {
                Text(verbatim: Copy.format("settings.cue.effective", date)).typeStyle(.bodyM).foregroundStyle(Palette.inkDim)
            }
            if group.isAdmin, let next = group.nextCue { nextCueRow(next, isSnapshot: isSnapshot) }
        }
    }

    /// The next round's cue, and the way in to changing it (`docs/18-CUES.md` §11.6).
    ///
    /// **Labelled with the round's date, never "tomorrow."** Between local midnight and the
    /// round's own `opens_at` the next unopened round is *today's* — the same window the drop
    /// screen spends showing last night's cue — so the date is the only label that is always
    /// true. Neutral throughout: §2's amber carve-out is `CueCard` on the drop screen, argued
    /// from that card being the brief for the field directly below it, and a settings row
    /// inherits nothing from it.
    @ViewBuilder private func nextCueRow(_ next: NextCueDTO, isSnapshot: Bool) -> some View {
        let date = GroupCalendar(timezone: group.timezone).shareDate(localDate: next.localDate)
        // `nil` clock → locked. The alternative is offering Save against an instant nobody has
        // established yet, and the failure mode of guessing wrong here is an admin typing a
        // brief for a round that already opened.
        let isOpen = (serverNow.map { $0 < next.editableUntil }) ?? false
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel("settings.cue.next.label")
            if isOpen && !isSnapshot {
                Button { editsNextCue = true } label: {
                    controlRow(chevron: true) { nextCueText(next) }
                }
                .buttonStyle(.plain).disabled(isSaving)
                .accessibilityLabel(Text("settings.cue.next.edit"))
            } else {
                controlRow(chevron: isOpen) { nextCueText(next) }
            }
            // **Under the cue, not over it.** The date is which night this line is for — a
            // footnote on the row, the way `group.revealhour.effective` sits under the hour it
            // qualifies, rather than a heading the cue hangs off.
            if let date {
                Text(verbatim: Copy.format("settings.cue.next.date", date))
                    .typeStyle(.caption).foregroundStyle(Palette.inkDim)
            }
            // Not a disabled button with no explanation: the round has opened, somebody may
            // already have sealed a song against the brief it carries, and that is the whole
            // reason the server refuses the write too.
            if !isOpen {
                Text("settings.cue.next.locked").typeStyle(.caption).foregroundStyle(Palette.inkDim)
            }
        }
        // The cadence picker above is a different question about the same subject, and at the
        // section's own `Space.sm` the two read as one four-row control. This is the gap that
        // separates them.
        .padding(.top, Space.md)
    }

    /// The line itself, or the fact that there isn't one. A night the cadence skips is not an
    /// error and not an invitation — absence is stated once, quietly, and writing a cue onto
    /// that night is still allowed.
    @ViewBuilder private func nextCueText(_ next: NextCueDTO) -> some View {
        if let text = next.text {
            Text(verbatim: text)
        } else {
            Text("settings.cue.next.empty").foregroundStyle(Palette.inkDim)
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

/// Writing the next round's cue by hand (`docs/18-CUES.md` §11.6, owner amendment 2026-09-09).
///
/// One field, because that is the whole feature: free text, no catalog picker. The admin
/// already has the line in mind — browsing forty of them is a different screen for a different
/// need, and a custom line is never promoted into the catalog anyway, so there is nothing here
/// that has to reconcile with it.
private struct NextCueSheet: View {
    let cue: NextCueDTO?
    var isSaving = false
    var errorKey: String?
    var onSave: (String) async -> Bool = { _ in true }
    var onReset: () async -> Bool = { true }

    @Environment(\.dismiss) private var dismiss
    @State private var field = ""
    @State private var hasSeeded = false
    /// The sheet is exactly as tall as its own column, the same trick `CircleSwitcherSheet`
    /// uses. Seeded at roughly the field plus the button so the first frame is not a flash of
    /// nothing, and so the sheet does not visibly grow into place on open.
    @State private var measuredHeight: CGFloat = Layout.fieldHeight + Layout.buttonHeight
        + Layout.blockGap * 2
    @FocusState private var focused: Bool

    private var trimmed: String { field.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var remaining: Int { GroupStore.cueLimit - trimmed.count }
    /// **Unchanged is not savable.** The sheet opens on the line that is already set, so an
    /// enabled button there offers to write what is already written — a request that would
    /// succeed, flip `is_custom` to true on a cue nobody edited, and teach the admin nothing.
    private var canSave: Bool {
        !trimmed.isEmpty && remaining >= 0 && !isSaving && trimmed != (cue?.text ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            SectionLabel("settings.cue.next.field")
            TextField("settings.cue.next.field", text: $field, axis: .vertical)
                .typeStyle(.bodyL).foregroundStyle(Palette.ink)
                .textInputAutocapitalization(.sentences)
                .lineLimit(1...3)
                .focused($focused)
                .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
                .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).stroke(Palette.edge, lineWidth: Stroke.border))
            // Counts down against the same 56 the catalog's own check constraint carries, and
            // the same trimmed string the server will be handed — a counter measuring something
            // other than what gets saved is worse than no counter.
            Text(verbatim: Copy.format("settings.cue.next.remaining", "\(remaining)"))
                .typeStyle(.caption)
                .foregroundStyle(remaining < 0 ? Palette.alert : Palette.inkDim)
            if let errorKey {
                Text(LocalizedStringKey(errorKey)).typeStyle(.bodyM).foregroundStyle(Palette.alert)
            }
            PrimaryButton("settings.cue.next.save", fill: .neutral, isEnabled: canSave) {
                Task { if await onSave(trimmed) { dismiss() } }
            }
            // Only when there is something to revert *to*: a derived cue is already the
            // automatic one, and offering to restore it would be offering to do nothing.
            if cue?.isCustom == true {
                Button("settings.cue.next.reset") {
                    Task { if await onReset() { dismiss() } }
                }
                .buttonStyle(.plain).typeStyle(.bodyM).foregroundStyle(Palette.inkDim)
                .disabled(isSaving)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Layout.screenInset)
        .padding(.top, Layout.blockGap)
        .padding(.bottom, Space.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Width fills the sheet; height is the column's own, so the sheet is the size of what
        // is in it rather than a fraction of the screen somebody guessed.
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { measuredHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, height in measuredHeight = height }
            }
        }
        .background(Palette.paper)
        .presentationBackground(Palette.paper)
        .presentationDetents([.height(measuredHeight)])
        .presentationCornerRadius(Radius.sheet)
        .presentationDragIndicator(.visible)
        // **Focus in `task`, not `onAppear`.** `onAppear` lands after the presentation
        // animation has committed, so the sheet slid to its detent and *then* the keyboard
        // pushed it further — two motions for one gesture. `task` runs early enough that the
        // keyboard is part of the same transition.
        .task {
            guard !hasSeeded else { return }
            hasSeeded = true
            field = cue?.text ?? ""
            focused = true
        }
    }
}

/// The four cue cadences, in display order (`docs/18-CUES.md` §4, `docs/11` `settings.cue.cadence.*`).
///
/// The raw values are `cue_cadence` on the wire — `0` off, `3` now and then, `2` every other
/// night, `1` every night — but the picker lists them in the order a person thinks about them,
/// not in numeric order, the same way `RevealHour.allowed` is an ordered set rather than a range
/// of values.
enum CueCadence {
    static let options: [Int] = [0, 3, 2, 1]

    static func label(_ cadence: Int) -> LocalizedStringKey {
        switch cadence {
        case 0: "settings.cue.cadence.off"
        case 3: "settings.cue.cadence.rare"
        case 1: "settings.cue.cadence.daily"
        default: "settings.cue.cadence.alternate"
        }
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
    var isCurrentUser = false
    /// Whether the trailing action slot is reserved even when this row has no actions, so the ear
    /// figure and the readability bar share one right edge with every other row.
    var reservesActionSlot = false
    var actions: [MemberManagementAction] = []
    var rendersForSnapshot = false
    var managementDisabled = false
    let select: () -> Void
    var manage: (MemberManagementAction) -> Void = { _ in }
    /// True from the instant a finger touches down — reported by a zero-duration long press, which
    /// still yields to the scroll view when the finger moves.
    @State private var isTouching = false
    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(spacing: Space.sm) {
                    GroupMemberRowContent(
                        standing: standing,
                        isAdmin: member.isAdmin,
                        isCurrentUser: isCurrentUser
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Reserve the ⋯ slot so the ear figure ends where every other row's does.
                    if reservesActionSlot {
                        Color.clear.frame(width: Layout.minimumTouchTarget)
                    }
                }
                readabilityBar
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: StandingRowContent.announcement(standing: standing, readability: readability)))
        .accessibilityHint(Copy.string("a11y.group.row.hint"))
        .accessibilityAddTraits(.isButton)
        .onLongPressGesture(minimumDuration: 0, perform: {}) { pressing in
            isTouching = pressing
        }
        // The "more" menu stays a separate control overlaid at the top-right, so tapping it never
        // triggers the card.
        .overlay(alignment: .topTrailing) {
            if !actions.isEmpty {
                MemberActionMenu(actions: actions, disabled: managementDisabled,
                                 rendersForSnapshot: rendersForSnapshot, manage: manage)
            }
        }
        // The caller's own row wears the revealed-data wash so "you" reads without a second line.
        .rowSurface(fill: isCurrentUser ? Palette.ultramarineWashLight : Palette.surface,
                    border: isCurrentUser ? Palette.ultramarineEdge : Palette.edge)
        // The press wash sits on the whole card — padding, content and border — and never hits,
        // so it cannot swallow the card tap or the "more" menu.
        .overlay(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(Palette.ink.opacity(isTouching ? 0.06 : 0))
                .allowsHitTesting(false)
        )
    }

    /// Readability is a trait, not a rank — the marker draws a position on a scale with no good
    /// end, and the figure sits *under* the bar so the bar runs the card's full width. A member who
    /// has never dropped gets an honest "Read —".
    @ViewBuilder private var readabilityBar: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if let readability {
                StatMeter(value: readability.readabilityAllTime, band: readability.band, showsBand: false)
            }
            SectionLabel(verbatim: Copy.format("results.standings.read.row", ScoringFormat.percent(readability?.readabilityAllTime)))
        }
        .accessibilityHidden(true)
    }
}



/// The ranked member's top line — rank, identity, ear — undressed of the readability bar, which
/// lives on the row above so it can span the card's full width. The rank is the game's number,
/// not a settings index; the ear value is a figure in the revealed-data accent.
private struct GroupMemberRowContent: View {
    let standing: EarStandingDTO
    let isAdmin: Bool
    let isCurrentUser: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var isStacked: Bool { dynamicTypeSize >= .accessibility1 }

    var body: some View {
        if isStacked {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                    rank
                    identity
                }
                ear
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                rank
                identity
                Spacer(minLength: Space.sm)
                ear
            }
        }
    }

    /// Zero-padded and tabular so a two-digit rank holds the name column still, set in the
    /// display face and the revealed-data accent rather than neutral ink.
    private var rank: some View {
        Text(verbatim: String(format: "%02lld", standing.rank))
            .typeStyle(.numberM)
            .foregroundStyle(Palette.ultramarine)
            .fixedSize()
            .frame(minWidth: Space.xxl, alignment: .leading)
            .accessibilityHidden(true)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            HStack(spacing: Space.xs) {
                Text(verbatim: standing.displayName)
                    .typeStyle(.bodyLStrong)
                    .foregroundStyle(Palette.ink)
                if isCurrentUser { youMark }
            }
            Text(roleKey).typeStyle(.caption).foregroundStyle(Palette.inkDim)
        }
    }

    private var roleKey: LocalizedStringKey {
        isAdmin ? "group.role.admin" : "group.role.member"
    }

    /// The word for the caller's own row. The wash behind the card carries the same fact for the
    /// eye; this pill names it without adding a line.
    private var youMark: some View {
        Text("results.you.title")
            .typeStyle(.labelSmall)
            .foregroundStyle(Palette.ultramarine)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xxs)
            .background(Capsule().fill(Palette.surface))
            .overlay(Capsule().stroke(Palette.ultramarineEdge, lineWidth: Stroke.border))
    }

    /// The ranked figure: correct guesses over the circle's last fourteen rounds, not a rate.
    /// Unitless on purpose — the `%` on the readability line below is the only mark telling the
    /// two apart, and How to play carries the definition.
    private var ear: some View {
        VStack(alignment: .trailing, spacing: Space.xxs) {
            SectionLabel("results.ear.label")
            Text(verbatim: String(standing.earReads))
                .typeStyle(.numberM)
                .foregroundStyle(Palette.ultramarine)
        }
        .fixedSize()
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
                    // An unranked member gets the rank column's own "no value" dash, not a face —
                    // a mark in this slot reads as *ranked but not shown*, and the honest thing is
                    // the same "—" every other "does not apply" number in the app already prints.
                    Text(verbatim: ScoringFormat.unavailable)
                        .typeStyle(.numberM)
                        .foregroundStyle(Palette.inkDim)
                        .fixedSize()
                        .frame(minWidth: Space.xxl, alignment: .leading)
                        .accessibilityHidden(true)
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

/// A zero-size probe that reaches the enclosing `UIScrollView` and disables `delaysContentTouches`,
/// so a member card under a finger highlights on contact the way a `UITableViewCell` does, rather
/// than waiting for the scroll view to rule out a scroll. The leaderboard is a list; its press wash
/// is only honest if it fires on contact.
private struct ScrollViewTouchesProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let probe = UIView()
        probe.isUserInteractionEnabled = false
        return probe
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // The probe joins the hierarchy after its first layout pass, so the walk runs next runloop.
        DispatchQueue.main.async {
            var view: UIView? = uiView.superview
            while let current = view {
                if let scrollView = current as? UIScrollView {
                    scrollView.delaysContentTouches = false
                    return
                }
                view = current.superview
            }
        }
    }
}
