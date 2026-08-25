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

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(filter: $filter)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } content: {
            LibraryView(
                filter: filter,
                selection: $selectedPost,
                isAddingURL: $isAddingURL,
                clipboardOffer: $clipboardOffer
            )
            .navigationSplitViewColumnWidth(min: 320, ideal: 400)
        } detail: {
            NavigationStack {
                if let post = selectedPost {
                    ReaderView(post: post) { isImmersive in
                        // Full screen means full screen: the sidebar and the
                        // library step aside for the duration.
                        withAnimation(.snappy) {
                            columnVisibility = isImmersive ? .detailOnly : .all
                        }
                    }
                        // Rebuild the reader when the selection changes, so scroll
                        // position and typography state don't leak between posts.
                        .id(post.id)
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
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Palette.inkTertiary)
                Text("Pick something to read")
                    .font(.system(size: 19, design: .serif))
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
    }
}
