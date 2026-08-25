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
                // Unread is somewhere to look, not a tally to answer for —
                // no number rides along with it. The rows below count what
                // exists, which isn't the same thing as what's owed.
                row(.unread)
                row(.all, count: index.totalCount)
                row(.starred, count: index.starredCount)
                row(.archived, count: index.archivedCount)
            }

            if !index.tags.isEmpty {
                Section {
                    ForEach(index.tags) { tag in
                        row(.tag(tag.name), count: tag.count)
                    }
                } header: {
                    header("Tags")
                }
            }

            if !index.sites.isEmpty {
                Section {
                    ForEach(index.sites.prefix(24)) { site in
                        row(.site(site.name), count: site.count)
                    }
                } header: {
                    header("Sites")
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

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(Palette.inkTertiary)
    }

    private func row(_ target: LibraryFilter, count: Int? = nil) -> some View {
        let isSelected = filter == target

        return HStack(spacing: 11) {
            Image(systemName: target.symbol)
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? Palette.accent : Palette.inkTertiary)
                .frame(width: 20)

            Text(target.title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isSelected ? Palette.ink : Palette.inkSecondary)
                .lineLimit(1)

            Spacer(minLength: 6)

            if let count, count > 0 {
                Text("\(count)")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(Palette.inkTertiary)
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 9)
                .fill(isSelected ? Palette.accentSoft : .clear)
                .padding(.horizontal, 6)
        )
        .tag(target)
    }
}
