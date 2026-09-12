import SwiftUI

/// The second-group path (`E20-02`). It deliberately does not reuse `OnboardingStore`: that
/// store's job is to move a person with *no* group through the root routing state, whereas this
/// sheet starts from a live round and must leave it there until the person chooses the new group.
@Observable @MainActor
final class StartGroupStore {
    enum Step: Equatable { case form, invite(GroupDTO) }

    private let api: APIClient
    private let circles: CircleStore

    var step: Step = .form
    var name = "" { didSet { if name != oldValue { failure = nil } } }
    var revealHour = RevealHour.default
    let timezone = TimeZone.current.identifier
    private(set) var isCreating = false
    private(set) var failure: String?

    /// The invite half, which `E38-03` lifted out of here into `InvitePanel` so `GroupScreen`
    /// could have it too. This sheet owns one and hands it to the panel.
    let invites: InviteStore

    init(api: APIClient, circles: CircleStore) {
        self.api = api
        self.circles = circles
        self.invites = InviteStore(api: api)
    }

    var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isCreating
    }

    func create() async {
        guard canCreate else { return }
        isCreating = true
        failure = nil
        defer { isCreating = false }
        do {
            let group = try await api.send(.createGroup(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                timezone: timezone,
                revealHour: revealHour
            ))
            // The new group is now a real membership. Refresh, then select it before the sheet
            // closes so **Go to the group** means the round behind this flow is actually theirs.
            await circles.load()
            circles.select(group.id)
            step = .invite(group)
            // A brand-new circle's only member is the creator, so the shortlist excludes exactly
            // them — the same filter `GroupScreen` applies against a circle of eleven.
            await invites.load(excluding: Set(group.members.map(\.userID)), in: group.id)
        } catch let error as APIError {
            failure = error.copyKey
        } catch {
            failure = APIError.unreadable.copyKey
        }
    }
}

/// Presented after the switcher closes. A separate sheet keeps the switcher a short, selectable
/// list rather than turning it into a navigation stack with a form hidden underneath it.
struct StartGroupSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var store: StartGroupStore?

    var body: some View {
        Group {
            if let store {
                switch store.step {
                case .form:
                    StartGroupForm(store: store, close: { dismiss() })
                case let .invite(group):
                    StartGroupInvites(store: store, group: group, close: { dismiss() })
                }
            } else {
                Color.clear
            }
        }
        .background(Palette.paper)
        .presentationBackground(Palette.paper)
        .task {
            store = store ?? StartGroupStore(api: env.api, circles: env.circles)
        }
    }
}

struct StartGroupForm: View {
    let store: StartGroupStore
    let close: () -> Void
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.none) {
            header
            ScrollView {
                fields
                    .padding(.horizontal, Layout.screenInset)
                    .padding(.top, Layout.itemGap)
                    .padding(.bottom, Layout.blockGap)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: Space.none) {
            action
                .padding(.horizontal, Layout.screenInset)
                .padding(.vertical, Layout.itemGap)
                .background(Palette.paper)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .onAppear { nameFocused = true }
        // The way down, which a dragged-away sheet has no other hook for. See
        // `resigningFocus(_:)`.
        .resigningFocus($nameFocused)
    }

    /// The form without its screen inset or scroll container, for the snapshot suite.
    /// `SnapshotRenderer` owns the outer padding and cannot draw a `ScrollView`'s content
    /// (`ios/BlindDropTests/Snapshot/SnapshotRenderer.swift` documents why), so this renders
    /// the same header, fields and action as one flat column instead.
    var snapshotContent: some View {
        VStack(alignment: .leading, spacing: Layout.blockGap) {
            header
            fields
            action
        }
    }

    private var header: some View {
        HStack {
            Text("group.start.title").typeStyle(.displayM).foregroundStyle(Palette.ink)
            Spacer(minLength: Space.sm)
            // Resigned before the dismissal, so the keyboard travels with the sheet.
            CloseButton {
                nameFocused = false
                close()
            }
        }
        .padding(.horizontal, Layout.screenInset)
        .padding(.top, Layout.blockGap)
        .padding(.bottom, Layout.itemGap)
    }

    @ViewBuilder private var fields: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: Layout.itemGap) {
            InsetField("group.start.name.placeholder", text: $store.name, isFocused: nameFocused)
                .focused($nameFocused)
                // `.never`, matching the rename field in circle settings (owner, 2026-09-11).
                // This is where a circle's name is typed for the first time, so it is the one
                // that matters most: a name the keyboard capitalised on the way in is a name the
                // owner has to go and fix afterwards.
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .onSubmit { nameFocused = false }

            labeled("group.start.timezone", help: "group.start.timezone.help") {
                Text(verbatim: TimezoneName.readable(store.timezone))
                    .typeStyle(.bodyL)
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .rowSurface()
            }

            labeled("group.start.hour", help: "group.start.hour.help") {
                Menu {
                    Picker("group.start.hour", selection: $store.revealHour) {
                        ForEach(Array(RevealHour.allowed), id: \.self) { hour in
                            Text(verbatim: RevealHour.formatted(hour)).tag(hour)
                        }
                    }
                } label: {
                    HStack {
                        Text(verbatim: RevealHour.formatted(store.revealHour))
                            .typeStyle(.bodyL).foregroundStyle(Palette.ink)
                        Spacer(minLength: Space.sm)
                        Image(systemName: "chevron.down").foregroundStyle(Palette.inkDim)
                    }
                    .rowSurface()
                }
                .accessibilityLabel(Text("group.start.hour"))
                .accessibilityValue(Text(verbatim: RevealHour.formatted(store.revealHour)))
            }

            if let failure = store.failure {
                Text(LocalizedStringKey(failure)).typeStyle(.bodyM).foregroundStyle(Palette.alert)
            }
        }
    }

    private var action: some View {
        PrimaryButton("group.start.action", fill: .neutral, isEnabled: store.canCreate) {
            nameFocused = false
            Task { await store.create() }
        }
    }

    @ViewBuilder private func labeled(
        _ title: LocalizedStringKey,
        help: LocalizedStringKey,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel(title)
            content()
            Text(help).typeStyle(.caption).foregroundStyle(Palette.inkDim).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct StartGroupInvites: View {
    let store: StartGroupStore
    let group: GroupDTO
    let close: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.blockGap) {
                HStack {
                    Text("group.invite.title").typeStyle(.displayM).foregroundStyle(Palette.ink)
                    Spacer(minLength: Space.sm)
                    CloseButton(action: close)
                }
                Text("group.invite.help").typeStyle(.bodyM).foregroundStyle(Palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)

                InvitePanel(
                    groupID: group.id,
                    inviteCode: group.inviteCode,
                    store: store.invites,
                    emphasis: .primary
                )

                if let failure = store.failure {
                    Text(LocalizedStringKey(failure)).typeStyle(.bodyM).foregroundStyle(Palette.alert)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SecondaryButton("group.invite.done", action: close)
            }
            .padding(.horizontal, Layout.screenInset)
            .padding(.vertical, Layout.blockGap)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.paper)
    }
}
