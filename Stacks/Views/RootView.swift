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
            LibraryView(filter: filter, selection: $selectedPost, isAddingURL: $isAddingURL)
                .navigationSplitViewColumnWidth(min: 320, ideal: 400)
        } detail: {
            NavigationStack {
                if let post = selectedPost {
                    ReaderView(post: post)
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
        .safeAreaInset(edge: .bottom) {
            if let url = clipboardOffer {
                ClipboardBanner(url: url) {
                    let post = archive.save(url: url)
                    selectedPost = post
                    clipboardOffer = nil
                } dismiss: {
                    clipboardOffer = nil
                }
            }
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

/// The offer to save a URL found on the clipboard.
private struct ClipboardBanner: View {
    let url: URL
    let save: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
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
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.inkTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Palette.card, in: .rect(cornerRadius: Metrics.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cornerRadius)
                .strokeBorder(Palette.rule, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.10), radius: 14, y: 6)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .transition(.move(edge: .bottom).combined(with: .opacity))
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
