import SwiftUI
import SwiftData

struct SidebarView: View {
    @Binding var filter: LibraryFilter

    @Environment(\.modelContext) private var context
    @State private var index = LibraryIndex()

    var body: some View {
        List(selection: Binding(
            get: { filter },
            set: { if let value = $0 { filter = value } }
        )) {
            Section {
                row(.unread, count: index.unreadCount)
                row(.all, count: index.totalCount)
                row(.starred, count: index.starredCount)
                row(.archived, count: index.archivedCount)
            }

            if !index.tags.isEmpty {
                Section("Tags") {
                    ForEach(index.tags) { tag in
                        row(.tag(tag.name), count: tag.count)
                    }
                }
            }

            if !index.sites.isEmpty {
                Section("Sites") {
                    ForEach(index.sites.prefix(24)) { site in
                        row(.site(site.name), count: site.count)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Palette.recessed)
        .navigationTitle("Stacks")
        .onAppear { index.refresh(context: context) }
        // Any save — a new post, a tag edit, a sync from another device —
        // changes what the sidebar should show.
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            index.refresh(context: context)
        }
    }

    private func row(_ target: LibraryFilter, count: Int) -> some View {
        Label {
            HStack {
                Text(target.title)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(Palette.inkTertiary)
                }
            }
        } icon: {
            Image(systemName: target.symbol)
        }
        .tag(target)
    }
}
