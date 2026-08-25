import SwiftUI
import SwiftData

struct ReaderView: View {
    @Bindable var post: Post
    /// Lets the split view get out of the way when the reader goes full screen.
    var onImmersiveChange: (Bool) -> Void = { _ in }

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

    // Markup
    @State private var isMarkingUp = false
    @State private var tool: MarkupTool = .highlight
    @State private var tint: HighlightTint = .butter
    @State private var ink: InkColor = .graphite
    @State private var hasUsedTool = false
    @State private var noteTarget: Highlight?

    @State private var isImmersive = false

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
        .safeAreaInset(edge: .top, spacing: 0) {
            if post.state == .ready {
                progressRule
                    // Full screen has no navigation bar, so nothing stops the
                    // text sliding up under the clock. The rule's own backing
                    // extends over the status bar and hides it there.
                    .background {
                        if isImmersive {
                            theme.background.ignoresSafeArea(edges: .top)
                        }
                    }
            }
        }
        .overlay(alignment: .bottom) { dockStack }
        .overlay(alignment: .leading) {
            if isImmersive { immersiveGrabber }
        }
        .overlay(alignment: .topTrailing) {
            if isImmersive { immersiveExit }
        }
        .navigationTitle(post.state == .ready ? post.host.uppercased() : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isImmersive ? .hidden : .visible, for: .navigationBar)
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
        .sheet(item: $noteTarget) { highlight in
            NoteSheet(highlight: highlight)
                .presentationDetents([.height(360)])
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
            if isImmersive { onImmersiveChange(false) }
        }
        .onChange(of: topBlock) { _, _ in scheduleProgressWrite() }
        .onChange(of: tool) { _, _ in hasUsedTool = false }
    }

    // MARK: - Article

    private func article(_ document: ReaderDocument) -> some View {
        // Grouped once per pass rather than filtered once per block, which was
        // O(blocks × highlights) on every scroll tick.
        let highlightsByBlock = Dictionary(grouping: post.highlights ?? [], by: \.blockIndex)
        let strokesByBlock = Dictionary(grouping: post.inkStrokes ?? [], by: \.blockIndex)

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
                            strokes: strokesByBlock[entry.id] ?? [],
                            markup: markupContext,
                            onHighlight: { range, text in
                                addHighlight(blockIndex: entry.id, range: range, text: text)
                            },
                            onOpenLink: { openURL($0) }
                        )
                        .id(entry.id)
                    }

                    footer
                        .padding(.top, 30)
                        // Room for the dock to float over paper rather than text.
                        .padding(.bottom, 92)
                }
                .frame(maxWidth: typography.measure, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 20)
                .scrollTargetLayout()
            }
            .scrollPosition(id: $topBlock, anchor: .top)
            // A pen stroke and a scroll are the same gesture; the pen wins
            // while it is out.
            .scrollDisabled(isMarkingUp && tool == .pen)
            .onAppear { restorePosition(using: scroller, in: document) }
        }
    }

    /// Wide screens get roomier margins; the column itself is already capped by
    /// the reader's measure setting. Full screen widens both.
    private var horizontalPadding: CGFloat {
        let regular = sizeClass == .regular
        if isImmersive { return regular ? 56 : 24 }
        return regular ? 40 : Metrics.gutter
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

    // MARK: - Chrome

    /// How far through the article you are, as a hairline. It replaces the
    /// percentage that used to sit in the metadata: a reader wants to feel the
    /// remaining distance, not read a number.
    private var progressRule: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(theme.rule)
            GeometryReader { geometry in
                Rectangle()
                    .fill(theme.accent.opacity(0.75))
                    .frame(width: geometry.size.width * max(0.02, post.readProgress))
            }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var dockStack: some View {
        if post.state == .ready, document != nil {
            VStack(spacing: 10) {
                if isMarkingUp, !hasUsedTool {
                    PencilHint(text: tool.hint)
                }

                ReaderDock(
                    theme: theme,
                    isMarkingUp: isMarkingUp,
                    tool: $tool,
                    tint: $tint,
                    ink: $ink,
                    highlightCount: (post.highlights ?? []).count,
                    isImmersive: isImmersive,
                    beginMarkup: {
                        withAnimation(.snappy) {
                            isMarkingUp = true
                            tool = .highlight
                            hasUsedTool = false
                        }
                    },
                    endMarkup: {
                        withAnimation(.snappy) {
                            isMarkingUp = false
                            tool = .highlight
                        }
                    },
                    openTypography: { isShowingTypography = true },
                    openHighlights: { isShowingHighlights = true },
                    toggleImmersive: { setImmersive(!isImmersive) }
                )
            }
            .padding(.bottom, 22)
            .animation(.snappy(duration: 0.2), value: hasUsedTool)
        }
    }

    /// Full screen has to be leavable without remembering a gesture. The tab on
    /// the leading edge is the same affordance a split view uses, and it points
    /// back at what it will bring: the library.
    private var immersiveGrabber: some View {
        Button {
            setImmersive(false)
        } label: {
            Capsule()
                .fill(theme.inkSecondary.opacity(0.5))
                .frame(width: 3, height: 34)
                .frame(width: 22, height: 76)
                .background(theme.background.opacity(0.92), in: .rect(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Leave full screen")
    }

    private var immersiveExit: some View {
        Button {
            setImmersive(false)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 12))
                Text(sizeClass == .regular ? "Show library" : "Show controls")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(theme.inkSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: .capsule)
            .overlay(Capsule().strokeBorder(theme.rule, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .padding(.trailing, 14)
        .padding(.top, 10)
    }

    private func setImmersive(_ value: Bool) {
        withAnimation(.snappy) { isImmersive = value }
        onImmersiveChange(value)
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
            .accessibilityIdentifier("reader.star")
            .accessibilityLabel(post.isStarred ? "Unstar" : "Star")

            Menu {
                Button { isShowingTags = true } label: {
                    Label("Tags…", systemImage: "tag")
                }

                Button { isShowingHighlights = true } label: {
                    Label("Highlights (\(post.sortedHighlights.count))", systemImage: "highlighter")
                }
                .disabled(post.sortedHighlights.isEmpty)

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

    // MARK: - Markup

    private var markupContext: MarkupContext? {
        guard isMarkingUp else { return nil }
        return MarkupContext(
            tool: tool,
            ink: ink,
            onSentenceTap: handleSentenceTap,
            onDrawStroke: addStroke,
            onEraseStroke: erase
        )
    }

    /// A tap on a sentence, resolved against the current tool. Highlighting the
    /// same sentence twice in the same tint takes it back off again — the
    /// gesture is a toggle, because a mis-tap should undo the way it was made.
    private func handleSentenceTap(blockIndex: Int, range: NSRange, text: String) {
        hasUsedTool = true

        switch tool {
        case .highlight:
            if let existing = highlight(blockIndex: blockIndex, overlapping: range) {
                if existing.tint == tint, (existing.note ?? "").isEmpty {
                    context.delete(existing)
                } else {
                    existing.tint = tint
                }
            } else {
                addHighlight(blockIndex: blockIndex, range: range, text: text, tint: tint)
            }
            try? context.save()

        case .note:
            let mark = highlight(blockIndex: blockIndex, overlapping: range)
                ?? addHighlight(blockIndex: blockIndex, range: range, text: text, tint: tint)
            try? context.save()
            noteTarget = mark

        case .erase:
            if let existing = highlight(blockIndex: blockIndex, overlapping: range) {
                context.delete(existing)
                try? context.save()
            }

        case .pen:
            break
        }
    }

    private func highlight(blockIndex: Int, overlapping range: NSRange) -> Highlight? {
        (post.highlights ?? []).first {
            $0.blockIndex == blockIndex && NSIntersectionRange($0.range, range).length > 0
        }
    }

    private func addStroke(blockIndex: Int, points: [CGPoint]) {
        hasUsedTool = true
        let stroke = InkStroke(blockIndex: blockIndex, points: points, color: ink)
        stroke.post = post
        context.insert(stroke)
        try? context.save()
    }

    private func erase(_ stroke: InkStroke) {
        hasUsedTool = true
        context.delete(stroke)
        try? context.save()
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

    @discardableResult
    private func addHighlight(
        blockIndex: Int,
        range: NSRange,
        text: String,
        tint: HighlightTint = .butter
    ) -> Highlight {
        let highlight = Highlight(
            blockIndex: blockIndex,
            start: range.location,
            length: range.length,
            text: text,
            tint: tint
        )
        highlight.post = post
        context.insert(highlight)
        try? context.save()
        return highlight
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
