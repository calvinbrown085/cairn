import SwiftUI
import SwiftData

struct LibraryView: View {
    let filter: LibraryFilter
    @Binding var selection: Post?
    @Binding var isAddingURL: Bool

    @Environment(ReadingPreferences.self) private var preferences
    @State private var search = ""
    @State private var sort: LibrarySort = .recentlySaved

    var body: some View {
        @Bindable var preferences = preferences

        PostList(
            filter: filter,
            search: search,
            sort: sort,
            groupBySite: preferences.groupBySite,
            selection: $selection,
            isAddingURL: $isAddingURL
        )
        .searchable(
            text: $search,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search titles and full text"
        )
        .navigationTitle(filter.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(LibrarySort.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    Divider()
                    Toggle("Group by site", isOn: $preferences.groupBySite)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingURL = true
                } label: {
                    Image(systemName: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

/// Split out so `@Query` can be rebuilt whenever the filter, search, or sort
/// changes — a Query's predicate is fixed at init.
private struct PostList: View {
    @Query private var posts: [Post]

    private let filter: LibraryFilter
    private let groupBySite: Bool
    private let isSearching: Bool
    @Binding private var selection: Post?
    @Binding private var isAddingURL: Bool

    @Environment(ArchiveService.self) private var archive
    @Environment(\.modelContext) private var context
    @State private var tagEditorTarget: Post?

    init(
        filter: LibraryFilter,
        search: String,
        sort: LibrarySort,
        groupBySite: Bool,
        selection: Binding<Post?>,
        isAddingURL: Binding<Bool>
    ) {
        self.filter = filter
        self.groupBySite = groupBySite
        self.isSearching = !search.squeezed.isEmpty
        self._selection = selection
        self._isAddingURL = isAddingURL
        self._posts = Query(
            filter: filter.predicate(search: search),
            sort: sort.descriptors
        )
    }

    var body: some View {
        Group {
            if posts.isEmpty {
                EmptyLibraryView(filter: filter, isSearching: isSearching) {
                    isAddingURL = true
                }
            } else {
                list
            }
        }
        .background(Palette.paper)
        .sheet(item: $tagEditorTarget) { post in
            TagSheet(post: post)
        }
    }

    private var list: some View {
        List(selection: $selection) {
            if groupBySite {
                ForEach(groupedBySite, id: \.host) { group in
                    Section(group.host) {
                        ForEach(group.posts) { row($0) }
                    }
                }
            } else {
                ForEach(posts) { row($0) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.paper)
    }

    private func row(_ post: Post) -> some View {
        PostRow(post: post)
            .tag(post)
            .listRowBackground(Palette.paper)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: Metrics.gutter, bottom: 4, trailing: Metrics.gutter))
            .contentShape(.rect)
            .accessibilityIdentifier("post.row")
            .onTapGesture { selection = post }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    post.isStarred.toggle()
                    try? context.save()
                } label: {
                    Label(post.isStarred ? "Unstar" : "Star", systemImage: post.isStarred ? "star.slash" : "star")
                }
                .tint(Palette.star)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    if selection == post { selection = nil }
                    archive.delete([post])
                } label: {
                    Label("Delete", systemImage: "trash")
                }

                Button {
                    post.isArchived.toggle()
                    try? context.save()
                } label: {
                    Label(
                        post.isArchived ? "Unarchive" : "Archive",
                        systemImage: post.isArchived ? "tray.and.arrow.up" : "archivebox"
                    )
                }
                .tint(Palette.inkSecondary)
            }
            .contextMenu {
                postMenu(post)
            }
    }

    @ViewBuilder
    private func postMenu(_ post: Post) -> some View {
        Button {
            post.openedAt = post.isUnread ? .now : nil
            try? context.save()
        } label: {
            Label(post.isUnread ? "Mark as read" : "Mark as unread",
                  systemImage: post.isUnread ? "envelope.open" : "envelope")
        }

        Button { tagEditorTarget = post } label: {
            Label("Tags…", systemImage: "tag")
        }

        if post.state == .failed {
            Button { archive.retry(post) } label: {
                Label("Try again", systemImage: "arrow.clockwise")
            }
        }

        Divider()

        if let url = post.url {
            Link(destination: url) {
                Label("Open original", systemImage: "safari")
            }
            ShareLink(item: url) {
                Label("Share link", systemImage: "square.and.arrow.up")
            }
        }

        Divider()

        Button(role: .destructive) {
            if selection == post { selection = nil }
            archive.delete([post])
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private var groupedBySite: [(host: String, posts: [Post])] {
        var order: [String] = []
        var buckets: [String: [Post]] = [:]
        for post in posts {
            let key = post.host.isEmpty ? "Unknown" : post.host
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(post)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }
}

struct EmptyLibraryView: View {
    let filter: LibraryFilter
    let isSearching: Bool
    let add: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isSearching ? "magnifyingglass" : filter.symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Palette.inkTertiary)
                .padding(.bottom, 2)

            Text(isSearching ? "No matches" : filter.emptyHeadline)
                .font(.system(size: 22, weight: .medium, design: .serif))
                .foregroundStyle(Palette.ink)

            Text(isSearching
                 ? "Search covers titles, authors, tags, and the full text of everything you've archived."
                 : filter.emptyDetail)
                .font(.system(size: 14))
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .lineSpacing(3)

            if !isSearching, filter == .unread || filter == .all {
                Button(action: add) {
                    Label("Add a link", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 6)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.paper)
    }
}
