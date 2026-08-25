import SwiftUI
import SwiftData

struct ReaderView: View {
    @Bindable var post: Post

    @Environment(ReadingPreferences.self) private var preferences
    @Environment(ArchiveService.self) private var archive
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var document: ReaderDocument?
    @State private var topBlock: Int?
    @State private var isShowingTypography = false
    @State private var isShowingTags = false
    @State private var isShowingHighlights = false
    @State private var hasRestoredPosition = false
    @State private var progressWriter: Task<Void, Never>?

    private var theme: ReaderTheme { preferences.theme }
    private var typography: ReaderTypography { preferences.typography }

    private var builder: AttributedTextBuilder {
        AttributedTextBuilder(typography: typography, theme: theme)
    }

    var body: some View {
        Group {
            switch post.state {
            case .ready:
                if let document, document.postID == post.id {
                    article(document)
                } else {
                    ReaderStatusView(
                        symbol: "book",
                        headline: "Opening…",
                        detail: post.title,
                        isBusy: true
                    )
                }
            case .pending, .fetching:
                ReaderStatusView(
                    symbol: "arrow.down.circle",
                    headline: "Fetching the article…",
                    detail: post.host,
                    isBusy: true
                )
            case .failed:
                ReaderStatusView(
                    symbol: "exclamationmark.triangle",
                    headline: "Couldn't save this one",
                    detail: post.failureReason ?? "Something went wrong.",
                    isBusy: false
                ) {
                    Button("Try again") { archive.retry(post) }
                        .buttonStyle(.borderedProminent)
                    if let url = post.url {
                        Button("Open in Safari") { openURL(url) }
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
        .background(theme.background.ignoresSafeArea())
        .preferredColorScheme(theme.forcedColorScheme)
        .navigationTitle(post.state == .ready ? post.title : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .toolbarBackground(theme.background, for: .navigationBar)
        .sheet(isPresented: $isShowingTypography) {
            TypographySheet()
                .presentationDetents([.height(560), .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingTags) { TagSheet(post: post) }
        .sheet(isPresented: $isShowingHighlights) {
            HighlightsSheet(post: post) { highlight in
                topBlock = highlight.blockIndex
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: renderGeneration, initial: true) { _, generation in
            ReaderRenderCache.shared.prepare(generation: generation)
        }
        .task(id: post.id) {
            document = await ReaderDocument.load(postID: post.id, contentData: post.contentData)
        }
        .onAppear(perform: markOpened)
        .onDisappear {
            progressWriter?.cancel()
            persistProgress()
        }
        .onChange(of: topBlock) { _, _ in scheduleProgressWrite() }
    }

    // MARK: - Article

    private func article(_ document: ReaderDocument) -> some View {
        // Grouped once per pass rather than filtered once per block, which was
        // O(blocks × highlights) on every scroll tick.
        let highlightsByBlock = Dictionary(grouping: post.highlights ?? [], by: \.blockIndex)

        return ScrollViewReader { scroller in
            ScrollView {
                // Lazy: a long essay is 200+ blocks, and each prose block is a
                // UITextView. Building them all up front cost seconds before the
                // first frame and left every one of them live while scrolling.
                LazyVStack(alignment: .leading, spacing: typography.bodySize * 0.85) {
                    header
                        .id(-1)

                    ForEach(document.blocks) { entry in
                        ArticleBlockView(
                            block: entry.block,
                            index: entry.id,
                            post: post,
                            builder: builder,
                            highlights: highlightsByBlock[entry.id] ?? [],
                            onHighlight: { range, text in
                                addHighlight(blockIndex: entry.id, range: range, text: text)
                            },
                            onOpenLink: { openURL($0) }
                        )
                        .id(entry.id)
                    }

                    footer
                        .padding(.top, 30)
                }
                .frame(maxWidth: typography.measure, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 20)
                .scrollTargetLayout()
            }
            .scrollPosition(id: $topBlock, anchor: .top)
            .onAppear { restorePosition(using: scroller, in: document) }
        }
    }

    /// Wide screens get roomier margins; the column itself is already capped by
    /// the reader's measure setting.
    private var horizontalPadding: CGFloat {
        sizeClass == .regular ? 40 : Metrics.gutter
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(post.title)
                .font(typography.font(size: typography.bodySize * 1.85, weight: .bold))
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(typography.bodySize * 0.12)

            HStack(spacing: 6) {
                if let author = post.author {
                    Text(author)
                    Text("·")
                }
                Text(post.siteName)
                if let published = post.publishedDisplay {
                    Text("·")
                    Text(published)
                }
                Text("·")
                Text("\(post.readingMinutes) min")
            }
            .font(.system(size: 11.5, weight: .medium))
            .textCase(.uppercase)
            .tracking(0.7)
            .foregroundStyle(theme.inkSecondary)
            .lineLimit(2)

            Rectangle()
                .fill(theme.rule)
                .frame(height: 0.5)
        }
        .padding(.bottom, 6)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle()
                .fill(theme.rule)
                .frame(height: 0.5)

            if let url = post.url {
                Button {
                    openURL(url)
                } label: {
                    Label("View the original", systemImage: "safari")
                        .font(.system(size: 13, weight: .medium))
                }
                .tint(theme.accent)
            }

            Text("Archived \(post.savedAt, format: .dateTime.month(.wide).day().year())")
                .font(.system(size: 11.5, weight: .medium))
                .textCase(.uppercase)
                .tracking(0.7)
                .foregroundStyle(theme.inkSecondary.opacity(0.8))
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                post.isStarred.toggle()
                try? context.save()
            } label: {
                Image(systemName: post.isStarred ? "star.fill" : "star")
                    .foregroundStyle(post.isStarred ? Palette.star : theme.inkSecondary)
            }

            Button {
                isShowingTypography = true
            } label: {
                Image(systemName: "textformat.size")
            }
            .accessibilityIdentifier("reader.typography")
            .disabled(post.state != .ready)

            Menu {
                Button { isShowingTags = true } label: {
                    Label("Tags…", systemImage: "tag")
                }

                if !post.sortedHighlights.isEmpty {
                    Button { isShowingHighlights = true } label: {
                        Label("Highlights (\(post.sortedHighlights.count))", systemImage: "highlighter")
                    }
                }

                Button {
                    post.isArchived.toggle()
                    try? context.save()
                } label: {
                    Label(post.isArchived ? "Move to library" : "Archive",
                          systemImage: post.isArchived ? "tray.and.arrow.up" : "archivebox")
                }

                Button {
                    post.openedAt = post.isUnread ? .now : nil
                    try? context.save()
                } label: {
                    Label(post.isUnread ? "Mark as read" : "Mark as unread",
                          systemImage: post.isUnread ? "envelope.open" : "envelope")
                }

                Divider()

                if let url = post.url {
                    Link(destination: url) { Label("Open original", systemImage: "safari") }
                    ShareLink(item: url) { Label("Share link", systemImage: "square.and.arrow.up") }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityIdentifier("reader.overflow")
        }
    }

    // MARK: - Behaviour

    /// Everything that changes what a block should look like. Highlights are
    /// folded in commutatively, since SwiftData gives no order guarantee.
    private var renderGeneration: Int {
        var hasher = Hasher()
        hasher.combine(post.id)
        hasher.combine(builder.styleGeneration)

        var highlightFingerprint = 0
        for highlight in post.highlights ?? [] {
            var inner = Hasher()
            inner.combine(highlight.id)
            inner.combine(highlight.start)
            inner.combine(highlight.length)
            inner.combine(highlight.tintRaw)
            highlightFingerprint ^= inner.finalize()
        }
        hasher.combine(highlightFingerprint)
        return hasher.finalize()
    }

    private func highlights(forBlock index: Int) -> [Highlight] {
        (post.highlights ?? []).filter { $0.blockIndex == index }
    }

    private func addHighlight(blockIndex: Int, range: NSRange, text: String) {
        let highlight = Highlight(
            blockIndex: blockIndex,
            start: range.location,
            length: range.length,
            text: text
        )
        highlight.post = post
        context.insert(highlight)
        try? context.save()
    }

    private func markOpened() {
        guard post.openedAt == nil, post.state == .ready else { return }
        post.openedAt = .now
        try? context.save()
    }

    /// Jumps back to where reading left off. Runs once — re-running it would
    /// fight the reader's own scrolling.
    private func restorePosition(using scroller: ScrollViewProxy, in document: ReaderDocument) {
        guard !hasRestoredPosition else { return }
        hasRestoredPosition = true

        let target = post.lastBlockIndex
        guard target > 0, target < document.count else { return }

        DispatchQueue.main.async {
            scroller.scrollTo(target, anchor: .top)
        }
    }

    /// `scrollPosition` reports every block that crosses the top edge, which for
    /// a long article is hundreds of updates. Saving each one would mean hundreds
    /// of SQLite writes and CloudKit pushes for a single read, so writes are
    /// coalesced and the last one wins.
    private func scheduleProgressWrite() {
        progressWriter?.cancel()
        progressWriter = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            persistProgress()
        }
    }

    private func persistProgress() {
        guard post.state == .ready, let top = topBlock, top >= 0 else { return }
        let total = max((document?.count ?? 1) - 1, 1)

        // Nothing to write if the reader hasn't actually moved.
        guard post.lastBlockIndex != top else { return }

        post.lastBlockIndex = top
        post.readProgress = min(1, Double(top) / Double(total))

        // Reaching the end counts as finishing, which is what "read" should mean.
        if post.readProgress > 0.92, post.finishedAt == nil {
            post.finishedAt = .now
        }
        try? context.save()
    }
}

/// Shared presentation for the reader's non-article states.
struct ReaderStatusView<Actions: View>: View {
    let symbol: String
    let headline: String
    let detail: String
    let isBusy: Bool
    @ViewBuilder var actions: () -> Actions

    init(
        symbol: String,
        headline: String,
        detail: String,
        isBusy: Bool,
        @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }
    ) {
        self.symbol = symbol
        self.headline = headline
        self.detail = detail
        self.isBusy = isBusy
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: 14) {
            if isBusy {
                ProgressView().controlSize(.large)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Palette.inkTertiary)
            }

            Text(headline)
                .font(.system(size: 20, weight: .medium, design: .serif))
                .foregroundStyle(Palette.ink)

            Text(detail)
                .font(.system(size: 14))
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
                .lineSpacing(3)

            HStack(spacing: 10) { actions() }
                .padding(.top, 4)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
