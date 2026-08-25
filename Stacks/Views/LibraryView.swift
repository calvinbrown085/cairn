import SwiftUI
import SwiftData

struct LibraryView: View {
    let filter: LibraryFilter
    @Binding var selection: Post?
    @Binding var isAddingURL: Bool
    @Binding var clipboardOffer: URL?

    @Environment(ReadingPreferences.self) private var preferences
    @State private var search = ""
    @State private var sort: LibrarySort = .recentlySaved
    @State private var isShowingSortSheet = false

    var body: some View {
        PostList(
            filter: filter,
            search: search,
            sort: sort,
            groupBySite: preferences.groupBySite,
            style: preferences.libraryStyle,
            selection: $selection,
            isAddingURL: $isAddingURL,
            clipboardOffer: $clipboardOffer
        )
        .safeAreaInset(edge: .top, spacing: 0) { sortChips }
        .searchable(
            text: $search,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search titles and full text"
        )
        .navigationTitle(filter.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingURL = true
                } label: {
                    Image(systemName: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityLabel("Save a link")
            }
        }
        .sheet(isPresented: $isShowingSortSheet) {
            SortSheet(sort: $sort)
                .presentationDetents([.height(520), .large])
                .presentationDragIndicator(.visible)
        }
    }

    /// The three sorts worth reaching without a sheet, then the sheet. Pinned
    /// under the search field rather than buried in a toolbar menu, because
    /// changing the order of a library is a browsing move, not a setting.
    private var sortChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                ForEach(LibrarySort.quickChoices) { option in
                    chip(option.label, isOn: sort == option) { sort = option }
                }
                chip("Sort & group…", isOn: false) { isShowingSortSheet = true }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 9)
        }
        .scrollIndicators(.hidden)
        .background(Palette.paper)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.rule).frame(height: 0.5)
        }
    }

    private func chip(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(isOn ? Color.white : Palette.inkSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isOn ? Palette.accent : Palette.card, in: .capsule)
                .overlay(
                    Capsule().strokeBorder(isOn ? Palette.accent : Palette.rule, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

/// Split out so `@Query` can be rebuilt whenever the filter, search, or sort
/// changes — a Query's predicate is fixed at init.
private struct PostList: View {
    @Query private var posts: [Post]

    private let filter: LibraryFilter
    private let groupBySite: Bool
    private let style: LibraryStyle
    private let isSearching: Bool
    @Binding private var selection: Post?
    @Binding private var isAddingURL: Bool
    @Binding private var clipboardOffer: URL?

    @Environment(ArchiveService.self) private var archive
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var tagEditorTarget: Post?

    init(
        filter: LibraryFilter,
        search: String,
        sort: LibrarySort,
        groupBySite: Bool,
        style: LibraryStyle,
        selection: Binding<Post?>,
        isAddingURL: Binding<Bool>,
        clipboardOffer: Binding<URL?>
    ) {
        self.filter = filter
        self.groupBySite = groupBySite
        self.style = style
        self.isSearching = !search.squeezed.isEmpty
        self._selection = selection
        self._isAddingURL = isAddingURL
        self._clipboardOffer = clipboardOffer
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
            // The clipboard offer rides at the top of the list rather than
            // hovering over it: it is one more thing you could read, so it
            // belongs where the things you could read are.
            if let url = clipboardOffer, !isSearching {
                ClipboardCard(url: url) {
                    selection = archive.save(url: url)
                    clipboardOffer = nil
                } dismiss: {
                    clipboardOffer = nil
                }
                .listRowBackground(Palette.paper)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: Metrics.gutter, bottom: 12, trailing: Metrics.gutter))
            }

            if groupBySite {
                ForEach(groupedBySite, id: \.host) { group in
                    Section {
                        ForEach(group.posts) { row($0) }
                    } header: {
                        Text(group.host)
                            .font(.system(size: 11, weight: .semibold))
                            .textCase(.uppercase)
                            .tracking(0.8)
                            .foregroundStyle(Palette.inkTertiary)
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

    @ViewBuilder
    private func row(_ post: Post) -> some View {
        let isSelected = sizeClass == .regular && selection == post

        // A Button rather than `.onTapGesture`: on a regular-width iPad the
        // list row's own selection gesture competes with a bare tap gesture and
        // neither fires. A button is also what a card actually is.
        Button {
            selection = post
        } label: {
            switch style {
            case .cards: PostCard(post: post, isSelected: isSelected)
            case .rows: PostRow(post: post, isSelected: isSelected)
            }
        }
        .buttonStyle(.plain)
        // One card is one thing: to VoiceOver, and to anything else reading the
        // hierarchy. Left uncombined, the cover's initial is its own element and
        // shadows the row it belongs to.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("post.row")
        .tag(post)
        .listRowBackground(Palette.paper)
        .listRowSeparator(style == .cards ? .hidden : .visible)
        .listRowSeparatorTint(Palette.rule)
        .listRowInsets(EdgeInsets(
            top: style == .cards ? 7 : 0,
            leading: Metrics.gutter,
            bottom: style == .cards ? 7 : 0,
            trailing: Metrics.gutter
        ))
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

/// The offer to save a URL found on the clipboard.
struct ClipboardCard: View {
    let url: URL
    let save: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.accent)

            VStack(alignment: .leading, spacing: 1) {
                Text("Save from clipboard")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text(Post.displayHost(for: url) + url.path())
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Button("Save", action: save)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .background(Palette.accent, in: .capsule)
                .buttonStyle(.plain)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.inkTertiary)
                    .padding(4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(Palette.card, in: .rect(cornerRadius: 13))
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(Palette.rule, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 9, y: 4)
    }
}

struct EmptyLibraryView: View {
    let filter: LibraryFilter
    let isSearching: Bool
    let add: () -> Void

    private var showsActions: Bool {
        !isSearching && (filter == .unread || filter == .all)
    }

    var body: some View {
        VStack(spacing: 11) {
            Image(systemName: isSearching ? "magnifyingglass" : filter.symbol)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Palette.inkTertiary)
                .frame(width: 54, height: 54)
                .background(Palette.recessed, in: .rect(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Palette.rule, lineWidth: 0.5)
                )
                .padding(.bottom, 4)

            Text(isSearching ? "No matches" : filter.emptyHeadline)
                .font(.system(size: 21, weight: .semibold, design: .serif))
                .foregroundStyle(Palette.ink)

            Text(isSearching
                 ? "Search covers titles, authors, tags, and the full text of everything you've archived."
                 : filter.emptyDetail)
                .font(.system(size: 14))
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
                .lineSpacing(3)

            if showsActions {
                VStack(spacing: 9) {
                    Button(action: add) {
                        Text("Paste a link")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Palette.accent, in: .rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 9) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.accent)
                        Text("Or share from Safari — Stacks appears in the share sheet")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.card, in: .rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Palette.rule, lineWidth: 0.5)
                    )
                }
                .frame(width: 250)
                .padding(.top, 10)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.paper)
    }
}
