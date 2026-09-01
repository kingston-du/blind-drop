import SwiftUI

/// `docs/08` §1.4 — the creator's path, and the only screen in the app that sets a group's
/// clock.
///
/// Three fields, and the second of them is permanent. The copy says so out loud
/// (`onboarding.create.timezone.help`) because `timezone` is immutable after creation
/// (`docs/04` §3) and finding that out afterwards, from a settings screen that will not let you
/// change it, is the kind of surprise that ends a group.
///
/// The reveal hour states its consequence rather than its value: *"songs open ten hours before,
/// answers land two hours after"* (`docs/02` §1). A person picking 20 is picking a whole day's
/// shape, and the number on its own does not say that.
struct CreateGroupScreen: View {
    let store: OnboardingStore

    @FocusState private var isNameFocused: Bool
    @State private var isPickingTimezone = false

    var body: some View {
        snapshotContent
            .padding(.horizontal, Layout.screenInset)
            .padding(.vertical, Layout.blockGap)
            .background(Palette.paper)
            .sheet(isPresented: $isPickingTimezone) {
                TimezonePicker(selection: Bindable(store).timezone)
            }
    }

    /// The screen's column, without the screen inset — see `DisplayNameScreen.snapshotContent`.
    var snapshotContent: some View {
        @Bindable var store = store

        return VStack(alignment: .leading, spacing: Layout.blockGap) {
            Text("onboarding.create.title")
                .typeStyle(.displayM)
                .foregroundStyle(Palette.ink)

            InsetField(
                "onboarding.create.name.placeholder",
                text: $store.groupName,
                isFocused: isNameFocused
            )
                .focused($isNameFocused)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .onSubmit { isNameFocused = false }
                .accessibilityLabel(Text("onboarding.create.name.placeholder"))

            timezoneRow
            revealHourRow

            if let error = store.createFailure {
                Text(LocalizedStringKey(error))
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.alert)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            Spacer(minLength: Space.none)

            VStack(spacing: Space.sm) {
                PrimaryButton(
                    "onboarding.create.action",
                    fill: .neutral,
                    isEnabled: store.canCreate,
                    action: create
                )

                OutlineButton("onboarding.create.back") {
                    isNameFocused = false
                    store.cancelCreating()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Defaults to the device's timezone and says, in the help line, that it is the last time
    /// anybody can change it.
    private var timezoneRow: some View {
        field(label: "onboarding.create.timezone", help: "onboarding.create.timezone.help") {
            Button { isPickingTimezone = true } label: {
                sunkRow {
                    Text(verbatim: TimezoneName.readable(store.timezone))
                        .typeStyle(.bodyL)
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("onboarding.create.timezone"))
            .accessibilityValue(Text(verbatim: TimezoneName.readable(store.timezone)))
        }
    }

    /// 18…21, default 20, shown as the hour a person reads on a clock (`docs/08` §1.4).
    ///
    /// A `Menu` and not a segmented `Picker`: four segments reading *"6:00 PM"* fit an SE at
    /// `.large` and nothing above it, and `docs/12` §1 is that nothing truncates at
    /// `.accessibility5`. A menu shows one value at whatever size it needs, and it wears the
    /// same chrome as the timezone row above — the two are the same kind of choice and looking
    /// like two different kinds would be the interface lying about that.
    private var revealHourRow: some View {
        field(label: "onboarding.create.hour", help: "onboarding.create.hour.help") {
            Menu {
                // `Picker` inside a `Menu` is the idiom that gets the checkmark for free.
                Picker("onboarding.create.hour", selection: Bindable(store).revealHour) {
                    ForEach(Array(RevealHour.allowed), id: \.self) { hour in
                        Text(verbatim: RevealHour.formatted(hour)).tag(hour)
                    }
                }
            } label: {
                sunkRow {
                    Text(verbatim: RevealHour.formatted(store.revealHour))
                        .typeStyle(.bodyL)
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                }
            }
            .accessibilityLabel(Text("onboarding.create.hour"))
            .accessibilityValue(Text(verbatim: RevealHour.formatted(store.revealHour)))
        }
    }

    /// The inset-field chrome around something that is not a text field.
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

    /// A labelled row: `label` above, the control, the help line under it. The three parts are
    /// one accessibility element, so VoiceOver reads the consequence with the control rather
    /// than three swipes after it.
    private func field(
        label: LocalizedStringKey,
        help: LocalizedStringKey,
        @ViewBuilder control: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel(label)

            control()

            Text(help)
                .typeStyle(.caption)
                .foregroundStyle(Palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func create() {
        guard store.canCreate else { return }
        isNameFocused = false
        Task { await store.create() }
    }
}

/// `docs/08` §1.4's second half — the code, and the two things to do with it.
///
/// This screen is the reason `OnboardingStore` does not re-read the session when a group is
/// created: the creator is already a member by then, so routing on `has_group` would take them
/// straight to today's round with the code they need nowhere on screen.
///
/// **Share invite** shares the `https://blinddrop-site.vercel.app/j/<CODE>` URL and not the bare code
/// (`docs/05` §5). Six characters in a message are six characters somebody has to be told what
/// to do with; the link opens the app, or the landing page if they do not have it yet.
struct InviteCodeScreen: View {
    let store: OnboardingStore
    let group: GroupDTO

    var body: some View {
        snapshotContent
            .padding(.horizontal, Layout.screenInset)
            .padding(.vertical, Layout.blockGap)
            .background(Palette.paper)
    }

    /// The screen's column, without the screen inset — see `DisplayNameScreen.snapshotContent`.
    var snapshotContent: some View {
        VStack(alignment: .leading, spacing: Layout.blockGap) {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("onboarding.invite.title")
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.inkDim)

                Text(verbatim: group.inviteCode)
                    .typeStyle(.displayL)
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text(verbatim: Copy.format(
                        "a11y.invite.code", JoinOrCreateScreen.spelled(group.inviteCode)
                    )))

                Text("onboarding.invite.help")
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Space.none)

            VStack(spacing: Space.sm) {
                if let url = InviteCode.inviteURL(for: group.inviteCode) {
                    ShareLink(item: url) {
                        PrimaryButtonLabel("onboarding.invite.share")
                            .primaryButtonChrome(fill: .neutral)
                    }
                    .buttonStyle(.plain)
                }

                SecondaryButton("onboarding.invite.done") {
                    Task { await store.finish() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The timezone list, searchable.
///
/// A sheet rather than a wheel because there are several hundred IANA identifiers and a wheel
/// through them is not a control, it is a punishment. The value sent to the server is always the
/// raw identifier — `docs/04` §3 validates it against `pg_timezone_names`, so a prettified
/// string must never leave this screen.
struct TimezonePicker: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""

    private var matches: [String] {
        let identifiers = TimeZone.knownTimeZoneIdentifiers.sorted()
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return identifiers }
        return identifiers.filter { TimezoneName.readable($0).lowercased().contains(needle) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.itemGap) {
            HStack {
                Text("onboarding.create.timezone")
                    .typeStyle(.displayM)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: Space.sm)
                SecondaryButton("onboarding.create.timezone.close") { dismiss() }
            }

            InsetField("onboarding.create.timezone.search", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel(Text("onboarding.create.timezone.search"))

            List(matches, id: \.self) { identifier in
                Button {
                    selection = identifier
                    dismiss()
                } label: {
                    HStack {
                        Text(verbatim: TimezoneName.readable(identifier))
                            .typeStyle(.bodyL)
                            .foregroundStyle(Palette.ink)
                        Spacer(minLength: Space.sm)
                        if identifier == selection {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Palette.ink)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Palette.paper)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .padding(.horizontal, Layout.screenInset)
        .padding(.top, Layout.blockGap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.paper)
    }
}

/// An IANA identifier as a person reads it. `America/New_York` → `America / New York`.
///
/// Presentation only. The identifier itself is what is sent, always — this exists so a list of
/// six hundred underscored strings is scannable, not to invent a second spelling of a timezone.
enum TimezoneName {
    static func readable(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "/", with: " / ")
    }
}
