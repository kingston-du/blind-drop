import SwiftUI

/// The group's active people, and nothing about what any of them have done tonight.
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
        } else if let error = store.state.error {
            VStack(alignment: .leading, spacing: Layout.blockGap) {
                Text(LocalizedStringKey(error.copyKey))
                    .typeStyle(.bodyM)
                    .foregroundStyle(Palette.inkDim)
                PrimaryButton("error.retry", fill: .neutral) { Task { await store.load() } }
            }
            .padding(Layout.screenInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.sm) {
                    if let name = store.group?.name {
                        Text(verbatim: name)
                            .typeStyle(.displayM)
                            .foregroundStyle(Palette.ink)
                            .padding(.bottom, Space.sm)
                    }
                    SectionLabel("group.members")
                    ForEach(store.members) { member in
                        Text(verbatim: member.displayName)
                            .typeStyle(.bodyL)
                            .foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .rowSurface()
                    }
                }
                .padding(Layout.screenInset)
            }
        }
    }
}
