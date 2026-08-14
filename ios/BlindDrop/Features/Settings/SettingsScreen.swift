import SwiftUI

struct SettingsScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var store: SettingsStore?
    @State private var confirmsDeletion = false
    @FocusState private var nameFocused: Bool

    private let privacyURL = URL(string: "https://kingston-du.github.io/blind-drop-pages/privacy/")!

    var body: some View {
        Group {
            if let store {
                content(store)
            } else {
                RoundSkeleton().padding(Layout.screenInset)
            }
        }
        .background(Palette.paper)
        .navigationTitle(Text("settings.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store == nil {
                store = SettingsStore(
                    api: env.api, session: env.session, router: env.router, push: env.push
                )
            }
        }
        .alert("settings.delete.confirm.title", isPresented: $confirmsDeletion) {
            Button("settings.delete.confirm.action", role: .destructive) {
                guard let store else { return }
                Task { await store.deleteAccount(using: AppleSignIn()) }
            }
            Button("settings.cancel", role: .cancel) {}
        } message: {
            Text("settings.delete.confirm.body")
        }
    }

    private func content(_ store: SettingsStore) -> some View {
        @Bindable var store = store
        return ScrollView {
            VStack(alignment: .leading, spacing: Layout.blockGap) {
                section("settings.profile") {
                    Text("settings.name.help")
                        .typeStyle(.bodyM)
                        .foregroundStyle(Palette.inkDim)
                    InsetField("settings.name.placeholder", text: $store.name, isFocused: nameFocused)
                        .focused($nameFocused)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit { Task { await store.saveName() } }
                    if let key = store.messageKey {
                        Text(LocalizedStringKey(key)).typeStyle(.bodyM).foregroundStyle(Palette.inkDim)
                    }
                    if let key = store.errorKey {
                        Text(LocalizedStringKey(key)).typeStyle(.bodyM).foregroundStyle(Palette.alert)
                    }
                    PrimaryButton("settings.save", fill: .neutral, isEnabled: store.canSave) {
                        nameFocused = false
                        Task { await store.saveName() }
                    }
                }

                section("settings.account") {
                    OutlineButton("settings.signout", isEnabled: !store.isSigningOut) {
                        Task { await store.signOut() }
                    }
                    Button("settings.delete", role: .destructive) { confirmsDeletion = true }
                        .buttonStyle(.plain)
                        .typeStyle(.bodyL)
                        .foregroundStyle(Palette.alert)
                        .minimumTouchTarget()
                        .disabled(store.isDeleting)
                }

                section("settings.about") {
                    Link(destination: privacyURL) {
                        HStack {
                            Text("settings.privacy")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                        }
                        .typeStyle(.bodyL)
                        .foregroundStyle(Palette.ink)
                        .minimumTouchTarget()
                    }
                }
            }
            .padding(Layout.screenInset)
        }
    }

    private func section<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel(title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
