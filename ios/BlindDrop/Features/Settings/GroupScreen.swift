import SwiftUI

/// The circle's own screen (`E21-01`, `docs/08` §9): its name, when it reveals, who is in it,
/// its timezone, and how to leave.
///
/// **Admin sees more, not different.** `GroupDetailView` below never disables a control for a
/// member — rename and the reveal-hour picker simply do not exist in that tree unless
/// `group.isAdmin`, because a wall of greyed-out controls tells a member what they cannot have,
/// and the enforcement that matters is server-side (`PATCH /groups/{id}` → `NOT_ADMIN`) rather
/// than this `if`.
struct GroupScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var store: GroupStore?

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
        .task {
            if store == nil { store = GroupStore(api: env.api, circles: env.circles) }
            await store?.load()
        }
    }

    @ViewBuilder
    private func content(_ store: GroupStore) -> some View {
        if store.state.isLoading {
            RoundSkeleton().padding(Layout.screenInset)
        } else if let error = store.state.error, store.group == nil {
            VStack(alignment: .leading, spacing: Layout.blockGap) {
                Text(LocalizedStringKey(error.copyKey))
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.inkDim)
                PrimaryButton("error.retry", fill: .neutral) { Task { await store.load() } }
            }
            .padding(Layout.screenInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if let group = store.group {
            GroupDetailView(
                group: group,
                isSaving: store.isSaving,
                isLeaving: store.isLeaving,
                errorKey: store.errorKey,
                revealHourEffectiveFrom: store.revealHourEffectiveFrom,
                onSaveName: { name in await store.rename(to: name) },
                onPickRevealHour: { hour in await store.setRevealHour(hour) },
                onLeave: {
                    guard await store.leave() else { return false }
                    env.router.path = []
                    return true
                }
            )
        }
    }
}

/// The screen's whole column, taking plain values and callbacks rather than `GroupStore` itself
/// so it can be snapshot-tested without a live network (`GroupScreenSnapshotTests`) — the same
/// split `CircleSwitcherSheet` draws between the sheet and `CircleSwitcher`.
struct GroupDetailView: View {
    let group: GroupDTO
    var isSaving: Bool = false
    var isLeaving: Bool = false
    var errorKey: String? = nil
    var revealHourEffectiveFrom: String? = nil
    var onSaveName: (String) async -> Bool = { _ in true }
    var onPickRevealHour: (Int) async -> Bool = { _ in true }
    var onLeave: () async -> Bool = { true }

    @State private var nameField: String = ""
    @State private var nameDirty = false
    @State private var didSaveName = false
    @State private var confirmsLeaving = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.blockGap) {
                nameSection

                if group.isAdmin {
                    revealHourSection
                }

                timezoneSection

                VStack(alignment: .leading, spacing: Space.sm) {
                    SectionLabel("group.members")
                    ForEach(group.members) { member in
                        memberRow(member)
                    }
                }

                if let errorKey {
                    Text(LocalizedStringKey(errorKey))
                        .typeStyle(.bodyM)
                        .foregroundStyle(Palette.alert)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("group.leave", role: .destructive) { confirmsLeaving = true }
                    .buttonStyle(.plain)
                    .typeStyle(.bodyL)
                    .foregroundStyle(Palette.alert)
                    .minimumTouchTarget()
                    .disabled(isLeaving)
            }
            .padding(Layout.screenInset)
        }
        .onAppear { nameField = group.name }
        .onChange(of: group.name) { _, new in
            guard !nameDirty else { return }
            nameField = new
        }
        .alert("group.leave.confirm.title", isPresented: $confirmsLeaving) {
            Button("group.leave.confirm.action", role: .destructive) {
                Task { _ = await onLeave() }
            }
            Button("settings.cancel", role: .cancel) {}
        } message: {
            Text("group.leave.confirm.body")
        }
    }

    // MARK: - Name

    @ViewBuilder
    private var nameSection: some View {
        if group.isAdmin {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionLabel("group.name.label")
                InsetField("group.name.label", text: $nameField, isFocused: nameFocused)
                    .focused($nameFocused)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onChange(of: nameField) { _, _ in
                        nameDirty = true
                        didSaveName = false
                    }
                    .onSubmit { Task { await saveName() } }
                Text("group.name.help")
                    .typeStyle(.caption)
                    .foregroundStyle(Palette.inkDim)
                if didSaveName {
                    Text("group.name.saved")
                        .typeStyle(.bodyM)
                        .foregroundStyle(Palette.inkDim)
                }
                PrimaryButton(
                    "group.name.save",
                    fill: .neutral,
                    isEnabled: canSaveName,
                    action: { Task { await saveName() } }
                )
            }
        } else {
            Text(verbatim: group.name)
                .typeStyle(.displayM)
                .foregroundStyle(Palette.ink)
                .padding(.bottom, Space.sm)
        }
    }

    private var canSaveName: Bool {
        !isSaving && nameDirty
            && !nameField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveName() async {
        guard canSaveName else { return }
        nameFocused = false
        if await onSaveName(nameField) {
            nameDirty = false
            didSaveName = true
        }
    }

    // MARK: - Reveal hour

    /// Admin only (`docs/08` §9). A `Menu`/`Picker` pair, the same idiom
    /// `CreateGroupScreen.revealHourRow` uses, so a person who has already seen this control once
    /// (at circle creation) meets it again unchanged.
    private var revealHourSection: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel("group.revealhour.label")
            Menu {
                Picker("group.revealhour.label", selection: revealHourBinding) {
                    ForEach(Array(RevealHour.allowed), id: \.self) { hour in
                        Text(verbatim: RevealHour.formatted(hour)).tag(hour)
                    }
                }
            } label: {
                sunkRow {
                    Text(verbatim: RevealHour.formatted(group.revealHour))
                        .typeStyle(.bodyL)
                        .foregroundStyle(Palette.ink)
                }
            }
            .disabled(isSaving)
            .accessibilityLabel(Text("group.revealhour.label"))
            .accessibilityValue(Text(verbatim: RevealHour.formatted(group.revealHour)))

            Text("group.revealhour.help")
                .typeStyle(.caption)
                .foregroundStyle(Palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)

            if let effectiveFrom = revealHourEffectiveFrom,
               let stated = GroupCalendar(timezone: group.timezone).shareDate(localDate: effectiveFrom) {
                Text(verbatim: Copy.format("group.revealhour.effective", stated))
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.inkDim)
            }
        }
    }

    private var revealHourBinding: Binding<Int> {
        Binding(
            get: { group.revealHour },
            set: { hour in Task { await onPickRevealHour(hour) } }
        )
    }

    // MARK: - Timezone

    /// Everyone — shown, never editable, with the reason (`docs/04` §3: `timezone` is immutable
    /// after creation).
    private var timezoneSection: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel("group.timezone.label")
            staticRow {
                Text(verbatim: TimezoneName.readable(group.timezone))
                    .typeStyle(.bodyL)
                    .foregroundStyle(Palette.ink)
            }
            Text("group.timezone.help")
                .typeStyle(.caption)
                .foregroundStyle(Palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Members

    /// One row: a name, and — only for an admin — the role tag. `E24-01` replaces this list with
    /// a leaderboard; kept structurally simple on purpose (`tasks/E21-circle-settings.md`).
    private func memberRow(_ member: MemberDTO) -> some View {
        HStack(spacing: Space.sm) {
            Text(verbatim: member.displayName)
                .typeStyle(.bodyL)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: Space.sm)
            if member.isAdmin {
                Text("group.role.admin")
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.inkDim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rowSurface()
    }

    /// The inset-field chrome around a control that opens something — `CreateGroupScreen`'s own
    /// `sunkRow`, duplicated rather than shared across features/onboarding for now. The chevron
    /// is the affordance that says "this opens", so it belongs only on an actual control.
    private func sunkRow(@ViewBuilder content: () -> some View) -> some View {
        HStack {
            content()
            Spacer(minLength: Space.sm)
            Image(systemName: "chevron.down")
                .foregroundStyle(Palette.inkDim)
        }
        .padding(.horizontal, Space.lg)
        .frame(minHeight: Layout.buttonHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .stroke(Palette.edge, lineWidth: Stroke.border)
        )
    }

    /// The same chrome, without the chevron — a fact on display, not a control. Used for the
    /// timezone row: `docs/04` §3's `timezone` is immutable, and a control-shaped affordance on
    /// a value nothing can change would be the interface lying about it.
    private func staticRow(@ViewBuilder content: () -> some View) -> some View {
        HStack {
            content()
            Spacer(minLength: Space.sm)
        }
        .padding(.horizontal, Space.lg)
        .frame(minHeight: Layout.buttonHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .stroke(Palette.edge, lineWidth: Stroke.border)
        )
    }
}
