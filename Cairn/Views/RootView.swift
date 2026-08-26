import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(ArchiveService.self) private var archive
    @Environment(\.modelContext) private var context

    @State private var filter: LibraryFilter = .unread
    @State private var selectedPost: Post?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isAddingURL = false
    @State private var clipboardOffer: URL?
    // Bumped on every row tap the library reports, including a tap on the
    // post already selected. `selectedPost` alone can't carry that signal —
    // reselecting the same post is a no-op write as far as `Equatable` and
    // `.onChange` are concerned, so nothing below would otherwise notice a
    // second open of the same article. Folded into the reader's `.id(...)`
    // so a reopen tears down and rebuilds it exactly as a switch to a
    // different post already does, and used directly (not just inferred
    // from `onChange`) to push the compact stack forward below.
    @State private var selectionToken = 0
    // `columnVisibility` only controls which columns share the screen at
    // regular width; on compact width (iPhone) the split view collapses to
    // one stacked column and looks at this instead to decide which one is
    // topmost. Nothing else pushes the stack forward: the library's row
    // button sets `selectedPost` directly rather than going through a
    // `List(selection:)` the split view can watch itself (that binding is
    // already spoken for — see `LibraryView`'s multi-select edit mode) — so
    // without this, selecting a post rebuilds the detail column in place
    // without ever bringing it on screen.
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .content

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $preferredCompactColumn) {
            SidebarView(filter: $filter)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } content: {
            LibraryView(
                filter: filter,
                // Not `$selectedPost` directly: a plain binding only writes
                // through when the new value differs from the old one, so
                // tapping the row that is already selected — the exact
                // reopen this task is about — would otherwise never reach
                // `selectionToken` or `preferredCompactColumn` below.
                selection: Binding(
                    get: { selectedPost },
                    set: { newValue in
                        selectedPost = newValue
                        selectionToken += 1
                        preferredCompactColumn = newValue == nil ? .content : .detail
                    }
                ),
                isAddingURL: $isAddingURL,
                clipboardOffer: $clipboardOffer
            )
            .navigationSplitViewColumnWidth(min: 320, ideal: 400)
        } detail: {
            NavigationStack {
                if let post = selectedPost {
                    Group {
                        switch post.kind {
                        case .article:
                            ReaderView(post: post) { isImmersive in
                                // Full screen means full screen: the sidebar and the
                                // library step aside for the duration.
                                withAnimation(.snappy) {
                                    columnVisibility = isImmersive ? .detailOnly : .all
                                }
                            }
                        case .pdf:
                            // PDFReaderView has no immersive mode of its own,
                            // so there's no `columnVisibility` toggle to wire up.
                            PDFReaderView(post: post)
                        }
                    }
                        // Rebuild the reader on every selection, so scroll
                        // position and typography state don't leak between posts
                        // *and* so reopening the same post gets a fresh reader
                        // rather than the one left behind, still mounted, from
                        // the last time it was open — `post.id` alone doesn't
                        // change on a same-post reopen, so `selectionToken` is
                        // folded in to force the rebuild anyway.
                        .id("\(post.id)#\(selectionToken)")
                } else {
                    ReaderPlaceholder()
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $isAddingURL) {
            AddURLSheet { url, tags in
                let post = archive.save(url: url, tags: tags)
                filter = .unread
                selectedPost = post
            }
        }
        .task { await offerClipboardURL() }
        .onChange(of: filter) { _, _ in selectedPost = nil }
        // The one thing that must push the compact stack to the detail
        // column, and the one thing that must let it fall back — whether
        // `selectedPost` changed because a row was tapped, a filter switch
        // cleared it above, or a post was deleted out from under the reader.
        .onChange(of: selectedPost) { _, post in
            preferredCompactColumn = post == nil ? .content : .detail
        }
    }

    /// Offers whatever URL is on the clipboard, without reading its contents
    /// until the user opts in — `detectPatterns` checks for a URL without
    /// triggering the paste notification banner.
    private func offerClipboardURL() async {
        guard let patterns = try? await UIPasteboard.general.detectedPatterns(
            for: [\.probableWebURL]
        ), patterns.contains(\.probableWebURL) else { return }

        guard let raw = UIPasteboard.general.string,
              let url = URL.fromUserInput(raw) else { return }

        // Don't offer something already in the library.
        let canonical = url.canonicalizedForArchive().absoluteString
        var descriptor = FetchDescriptor<Post>(
            predicate: #Predicate<Post> { $0.canonicalURLString == canonical }
        )
        descriptor.fetchLimit = 1
        guard (try? context.fetch(descriptor).first) == nil else { return }

        withAnimation(.snappy) { clipboardOffer = url }
    }
}

private struct ReaderPlaceholder: View {
    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "books.vertical")
                    .font(.scaled(40, weight: .light, relativeTo: .largeTitle))
                    .foregroundStyle(Palette.inkTertiary)
                Text("Pick something to read")
                    .font(.scaled(19, design: .serif, relativeTo: .title3))
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
    }
}
