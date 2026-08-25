import SwiftUI
import SwiftData

struct LibraryView: View {
    let filter: LibraryFilter
    @Binding var selection: Post?
    @Binding var isAddingURL: Bool
    @Binding var clipboardOffer: URL?

    @Environment(ReadingPreferences.self) private var preferences
    @Environment(\.modelContext) private var context
    @State private var search = ""
    @State private var sort: LibrarySort = .recentlySaved
    @State private var timeFilter: LibraryTimeFilter = .any
    @State private var neverOpenedOnly = false
    @State private var isShowingSortSheet = false

    // Bulk archive by selection: platform edit mode, not an invented picker.
    // Both live here rather than inside `PostList` because the toolbar that
    // acts on them is built here.
    @State private var editMode: EditMode = .inactive
    @State private var selectedIDs: Set<Post.ID> = []

    var body: some View {
        PostList(
            filter: filter,
            search: search,
            sort: sort,
            timeFilter: timeFilter,
            neverOpened: neverOpenedOnly,
            groupBySite: preferences.groupBySite,
            style: preferences.libraryStyle,
            selection: $selection,
            isAddingURL: $isAddingURL,
            clipboardOffer: $clipboardOffer,
            selectedIDs: $selectedIDs
        )
        .environment(\.editMode, $editMode)
        .safeAreaInset(edge: .top, spacing: 0) { sortChips }
        .searchable(
            text: $search,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search titles and full text"
        )
        .navigationTitle(filter.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                if editMode.isEditing {
                    Button("Archive") {
                        archiveSelection()
                    }
                    .disabled(selectedIDs.isEmpty)
                } else {
                    Button {
                        isAddingURL = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .accessibilityLabel("Save a link")
                }
            }
        }
        .sheet(isPresented: $isShowingSortSheet) {
            SortSheet(sort: $sort)
                .presentationDetents([.height(520), .large])
                .presentationDragIndicator(.visible)
        }
        // A selection made in one filter means nothing in another; leaving it
        // live across a filter switch would archive posts the user never saw
        // checked.
        .onChange(of: filter) { _, _ in
            editMode = .inactive
            selectedIDs.removeAll()
        }
    }

    /// Archives every selected post in one save, then drops back out of
    /// selection mode — the same shape as the per-row swipe action, just
    /// batched. This is reached only by first tapping Edit and checking rows,
    /// never surfaced on its own.
    private func archiveSelection() {
        let ids = selectedIDs
        guard !ids.isEmpty else { return }
        let descriptor = FetchDescriptor<Post>(predicate: #Predicate<Post> { ids.contains($0.id) })
        guard let matches = try? context.fetch(descriptor) else { return }
        for post in matches { post.isArchived = true }
        try? context.save()
        selectedIDs.removeAll()
        editMode = .inactive
    }

    /// The three sorts worth reaching without a sheet, then the sheet, then
    /// how long a post takes to read, then whether it's ever been opened —
    /// two independent axes that narrow whatever `filter` and search already
    /// picked rather than replacing it (see
    /// `LibraryFilter.predicate(search:timeFilter:neverOpened:)`). Pinned
    /// under the search field rather than buried in a toolbar menu, because
    /// all of these are browsing moves, not settings. Neither chip carries a
    /// count: this is a way to find something, not a tally of it.
    private var sortChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                ForEach(LibrarySort.quickChoices) { option in
                    chip(option.label, isOn: sort == option) { sort = option }
                }
                chip("Sort & group…", isOn: false) { isShowingSortSheet = true }

                Divider().frame(height: 16)

                ForEach(LibraryTimeFilter.allCases) { option in
                    chip(option.title, isOn: timeFilter == option) { timeFilter = option }
                }

                Divider().frame(height: 16)

                chip("Never opened", isOn: neverOpenedOnly) { neverOpenedOnly.toggle() }
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
                .font(.scaled(12.5, weight: .medium, relativeTo: .caption))
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
    private let searchQuery: String
    @Binding private var selection: Post?
    @Binding private var isAddingURL: Bool
    @Binding private var clipboardOffer: URL?
    /// The rows checked while the platform's edit mode is active — see
    /// `LibraryView`, which owns this alongside the `\.editMode` environment
    /// value and is the only thing that acts on it (the bulk archive
    /// toolbar button). Independent of `selection`: that binding tracks
    /// which single post is open in the reader pane and keeps doing so
    /// whether or not the list is in edit mode.
    @Binding private var selectedIDs: Set<Post.ID>

    @Environment(ArchiveService.self) private var archive
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var tagEditorTarget: Post?

    init(
        filter: LibraryFilter,
        search: String,
        sort: LibrarySort,
        timeFilter: LibraryTimeFilter,
        neverOpened: Bool,
        groupBySite: Bool,
        style: LibraryStyle,
        selection: Binding<Post?>,
        isAddingURL: Binding<Bool>,
        clipboardOffer: Binding<URL?>,
        selectedIDs: Binding<Set<Post.ID>>
    ) {
        self.filter = filter
        self.groupBySite = groupBySite
        self.style = style
        self.isSearching = !search.squeezed.isEmpty
        self.searchQuery = search.squeezed
        self._selection = selection
        self._isAddingURL = isAddingURL
        self._clipboardOffer = clipboardOffer
        self._selectedIDs = selectedIDs
        self._posts = Query(PostList.descriptor(
            filter: filter, search: search, sort: sort, timeFilter: timeFilter, neverOpened: neverOpened
        ))
    }

    /// Neither `PostRow` nor `PostCard` shows a post's body — only its title,
    /// its byline, and a search snippet built on demand for the cells
    /// actually on screen (both are drawn as cells of the one `List` below,
    /// whichever `style` is picked). Leaving `searchText` and `contentData`
    /// out of `propertiesToFetch` means opening a filter with a thousand
    /// matches doesn't pull a thousand articles' worth of text into memory
    /// just to list their titles; each excluded property is faulted back in
    /// individually, only for the one post that ends up needing it.
    private static func descriptor(
        filter: LibraryFilter, search: String, sort: LibrarySort, timeFilter: LibraryTimeFilter, neverOpened: Bool
    ) -> FetchDescriptor<Post> {
        var descriptor = FetchDescriptor<Post>(
            predicate: filter.predicate(search: search, timeFilter: timeFilter, neverOpened: neverOpened),
            sortBy: sort.descriptors
        )
        descriptor.propertiesToFetch = [
            \.id, \.urlString, \.canonicalURLString, \.title, \.author, \.siteName, \.host, \.excerpt,
            \.publishedAt, \.publishedOffset, \.savedAt, \.openedAt, \.finishedAt,
            \.wordCount, \.isStarred, \.isArchived, \.readProgress, \.lastBlockIndex,
            \.stateRaw, \.failureReason, \.tagNames, \.leadImageID,
        ]
        return descriptor
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
        // Bound to the checked-row set rather than `selection` (a single
        // `Post?`): that's what lets `\.editMode` — set active by the
        // `EditButton` in `LibraryView`'s toolbar — turn each row into a
        // checkmark target using nothing but the platform's own multi-select
        // chrome. Reading still goes through `selection`, set directly by
        // each row's own button below.
        List(selection: $selectedIDs) {
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
                            .font(.scaled(11, weight: .semibold, relativeTo: .caption2))
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
        //
        // A failed post has nothing to read — opening the reader just shows
        // the same failure a second time, one screen later. The one useful
        // thing to do with it is try again, so the row's own tap does that
        // directly: "this one didn't work, tap to try again," not a detour
        // through a detail view to find the same button.
        Button {
            if post.state == .failed {
                archive.retry(post)
            } else {
                selection = post
            }
        } label: {
            switch style {
            case .cards: PostCard(post: post, isSelected: isSelected, searchQuery: searchQuery)
            case .rows: PostRow(post: post, isSelected: isSelected, searchQuery: searchQuery)
            }
        }
        .buttonStyle(.plain)
        // One card is one thing: to VoiceOver, and to anything else reading the
        // hierarchy. Left uncombined, the cover's initial is its own element and
        // shadows the row it belongs to.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("post.row")
        .tag(post.id)
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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // A wide accessibility font leaves no room for icon + text + two
        // buttons on one line; stack the actions under the text instead of
        // letting them get pressed together or clipped.
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 11) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.scaled(15, weight: .medium, relativeTo: .subheadline))
                        .foregroundStyle(Palette.accent)
                    labels
                    Spacer(minLength: 0)
                    dismissButton
                }
                saveButton
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(Palette.card, in: .rect(cornerRadius: 13))
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(Palette.rule, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.08), radius: 9, y: 4)
        } else {
            HStack(spacing: 11) {
                Image(systemName: "doc.on.clipboard")
                    .font(.scaled(15, weight: .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.accent)

                labels

                Spacer(minLength: 8)

                saveButton

                dismissButton
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

    private var labels: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Save from clipboard")
                .font(.scaled(13, weight: .semibold, relativeTo: .footnote))
                .foregroundStyle(Palette.ink)
            Text(Post.displayHost(for: url) + url.path())
                .font(.scaled(12, relativeTo: .caption))
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var saveButton: some View {
        Button("Save", action: save)
            .font(.scaled(13, weight: .semibold, relativeTo: .footnote))
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 6)
            .background(Palette.accent, in: .capsule)
            .buttonStyle(.plain)
    }

    private var dismissButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.scaled(12, weight: .bold, relativeTo: .caption))
                .foregroundStyle(Palette.inkTertiary)
                .padding(4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss")
    }
}

struct EmptyLibraryView: View {
    let filter: LibraryFilter
    let isSearching: Bool
    let add: () -> Void

    // Scales in step with the icon it frames, so a large accessibility size
    // grows the badge along with the glyph instead of clipping it inside a
    // box that stayed 54pt.
    @ScaledMetric(relativeTo: .title2) private var badgeSize: CGFloat = 54
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var showsActions: Bool {
        !isSearching && (filter == .unread || filter == .all)
    }

    var body: some View {
        VStack(spacing: 11) {
            Image(systemName: isSearching ? "magnifyingglass" : filter.symbol)
                .font(.scaled(22, weight: .light, relativeTo: .title2))
                .foregroundStyle(Palette.inkTertiary)
                .frame(width: badgeSize, height: badgeSize)
                .background(Palette.recessed, in: .rect(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Palette.rule, lineWidth: 0.5)
                )
                .padding(.bottom, 4)

            Text(isSearching ? "No matches" : filter.emptyHeadline)
                .font(.scaled(21, weight: .semibold, design: .serif, relativeTo: .title2))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)

            Text(isSearching
                 ? "Search covers titles, authors, tags, and the full text of everything you've archived."
                 : filter.emptyDetail)
                .font(.scaled(14, relativeTo: .subheadline))
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
                // A fixed 300pt cap reads fine at the default size; at
                // accessibility sizes it would force many more line breaks
                // than the available width needs, so let it use the width
                // the empty state already has instead.
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 300)
                .lineSpacing(3)

            if showsActions {
                VStack(spacing: 9) {
                    Button(action: add) {
                        Text("Paste a link")
                            .font(.scaled(15, weight: .semibold, relativeTo: .subheadline))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Palette.accent, in: .rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.scaled(13, relativeTo: .footnote))
                            .foregroundStyle(Palette.accent)
                        Text("Or share from Safari — Cairn appears in the share sheet")
                            .font(.scaled(12.5, relativeTo: .caption))
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
                // 250pt was tuned for the default text size; wider accessibility
                // text needs the full width to avoid squeezing every line.
                .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 250)
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
                .padding(.top, 10)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.paper)
    }
}
