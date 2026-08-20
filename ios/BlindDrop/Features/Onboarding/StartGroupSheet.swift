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
    private(set) var isLoadingPeople = false
    private(set) var invitingIDs = Set<String>()
    private(set) var people: [KnownPersonDTO] = []
    private(set) var invitations: [String: InvitationDTO] = [:]
    private(set) var failure: String?

    init(api: APIClient, circles: CircleStore) {
        self.api = api
        self.circles = circles
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
            await loadPeople()
        } catch let error as APIError {
            failure = error.copyKey
        } catch {
            failure = APIError.unreadable.copyKey
        }
    }

    func loadPeople() async {
        isLoadingPeople = true
        defer { isLoadingPeople = false }
        do {
            people = try await api.send(Endpoint<KnownPeopleDTO>.peopleYouPlayedWith).people
        } catch let error as APIError {
            failure = error.copyKey
        } catch {
            failure = APIError.unreadable.copyKey
        }
    }

    func invite(_ person: KnownPersonDTO, to group: GroupDTO) async {
        guard !invitingIDs.contains(person.id), invitations[person.id] == nil else { return }
        invitingIDs.insert(person.id)
        failure = nil
        defer { invitingIDs.remove(person.id) }
        do {
            invitations[person.id] = try await api.send(.invitePerson(person.id, to: group.id))
        } catch let error as APIError {
            // A second tap after an interrupted request is still honestly represented as already
            // invited; the button remains available so the next run can show that answer.
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
        content
            .padding(.horizontal, Layout.screenInset)
            .padding(.vertical, Layout.blockGap)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .onAppear { nameFocused = true }
    }

    /// The form without its screen inset, for the snapshot suite. `SnapshotRenderer` owns that
    /// outer padding, just as it does for the existing onboarding forms.
    var snapshotContent: some View { content }

    @ViewBuilder private var content: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: Layout.blockGap) {
            HStack {
                Text("group.start.title").typeStyle(.displayM).foregroundStyle(Palette.ink)
                Spacer(minLength: Space.sm)
                CloseButton(action: close)
            }

            InsetField("group.start.name.placeholder", text: $store.name, isFocused: nameFocused)
                .focused($nameFocused)
                .textInputAutocapitalization(.words)
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

            Spacer(minLength: Space.none)
            PrimaryButton("group.start.action", fill: .neutral, isEnabled: store.canCreate) {
                nameFocused = false
                Task { await store.create() }
            }
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

                if store.isLoadingPeople {
                    ProgressView().tint(Palette.ink)
                } else if store.people.isEmpty {
                    Text("group.invite.empty").typeStyle(.bodyM).foregroundStyle(Palette.inkDim)
                } else {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        SectionLabel("group.invite.people")
                        ForEach(store.people) { person in
                            personRow(person)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Space.sm) {
                    SectionLabel("group.invite.link")
                    if let url = InviteCode.inviteURL(for: group.inviteCode) {
                        ShareLink(item: url) {
                            PrimaryButtonLabel("group.invite.share").primaryButtonChrome(fill: .neutral)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let failure = store.failure {
                    Text(LocalizedStringKey(failure)).typeStyle(.bodyM).foregroundStyle(Palette.alert)
                }

                SecondaryButton("group.invite.done", action: close)
            }
            .padding(.horizontal, Layout.screenInset)
            .padding(.vertical, Layout.blockGap)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.paper)
    }

    @ViewBuilder private func personRow(_ person: KnownPersonDTO) -> some View {
        if let invitation = store.invitations[person.id], let url = InvitationLink.url(for: invitation.id) {
            ShareLink(item: url) {
                HStack {
                    Text(verbatim: person.displayName).typeStyle(.bodyLStrong).foregroundStyle(Palette.ink)
                    Spacer(minLength: Space.sm)
                    Text("group.invite.share").typeStyle(.bodyM).foregroundStyle(Palette.inkDim)
                }
                .rowSurface()
            }
            .buttonStyle(.plain)
        } else {
            Button {
                Task { await store.invite(person, to: group) }
            } label: {
                HStack {
                    Text(verbatim: person.displayName).typeStyle(.bodyLStrong).foregroundStyle(Palette.ink)
                    Spacer(minLength: Space.sm)
                    if store.invitingIDs.contains(person.id) {
                        ProgressView().tint(Palette.ink)
                    } else {
                        Text("group.invite.action").typeStyle(.bodyM).foregroundStyle(Palette.inkDim)
                    }
                }
                .rowSurface()
            }
            .buttonStyle(.plain)
            .disabled(store.invitingIDs.contains(person.id))
        }
    }
}
