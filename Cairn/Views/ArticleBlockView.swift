import SwiftUI
import SwiftReadability

/// Everything the reader needs to know about markup while a block is on screen.
/// Nil means markup is off — the block draws its ink but takes no input.
struct MarkupContext {
    var tool: MarkupTool
    var ink: InkColor
    var onSentenceTap: (Int, NSRange, String) -> Void
    var onDrawStroke: (Int, [CGPoint]) -> Void
    var onEraseStroke: (InkStroke) -> Void
}

/// Renders one article block in the reader's current typography.
struct ArticleBlockView: View {
    let block: ArticleBlock
    let index: Int
    let post: Post
    let builder: AttributedTextBuilder
    let highlights: [Highlight]
    var strokes: [InkStroke] = []
    var markup: MarkupContext?
    let onHighlight: (NSRange, String) -> Void
    let onOpenLink: (URL) -> Void

    private var typography: ReaderTypography { builder.typography }
    private var theme: ReaderTheme { builder.theme }

    /// Cache keys for this block. Blocks that hold several text views — a list,
    /// an image with a caption — give each one its own slot.
    private func key(_ part: Int = 0) -> Int { (index << 20) | part }

    private func cachedText(_ part: Int = 0, _ build: () -> NSAttributedString) -> NSAttributedString {
        ReaderRenderCache.shared.string(block: key(part), build: build)
    }

    /// Ink is always drawn — it is part of the page now — but only listens
    /// while the pen or the eraser is out. A block with no ink and no pen over
    /// it gets no layer at all: a long essay is 200+ blocks, and an overlay
    /// each is 200+ containers nothing would ever draw into.
    private var needsInkLayer: Bool {
        !strokes.isEmpty || markup?.tool == .pen || markup?.tool == .erase
    }

    @ViewBuilder
    var body: some View {
        if needsInkLayer {
            content.overlay {
                InkCanvas(
                    strokes: strokes,
                    tool: markup?.tool,
                    ink: markup?.ink ?? .graphite,
                    onFinish: { points in markup?.onDrawStroke(index, points) },
                    onErase: { stroke in markup?.onEraseStroke(stroke) }
                )
                // A stroke is not something VoiceOver can read out.
                .accessibilityHidden(true)
            }
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch block {
        case .heading(let level, let text):
            SelectableTextView(
                attributed: cachedText {
                    builder.paragraph(
                        text,
                        size: typography.headingSize(level: level),
                        weight: level <= 2 ? .bold : .semibold,
                        highlights: highlights
                    )
                },
                measurementKey: key(),
                markupTool: markup?.tool,
                onHighlight: onHighlight,
                onSentenceTap: { markup?.onSentenceTap(index, $0, $1) },
                onOpenLink: onOpenLink
            )
            .padding(.top, level <= 2 ? typography.bodySize * 1.1 : typography.bodySize * 0.7)
            .padding(.bottom, typography.bodySize * 0.1)

        case .paragraph(let text):
            SelectableTextView(
                attributed: cachedText { builder.paragraph(text, highlights: highlights) },
                measurementKey: key(),
                markupTool: markup?.tool,
                onHighlight: onHighlight,
                onSentenceTap: { markup?.onSentenceTap(index, $0, $1) },
                onOpenLink: onOpenLink
            )

        case .quote(let text):
            HStack(alignment: .top, spacing: 16) {
                Rectangle()
                    .fill(theme.accent.opacity(0.45))
                    .frame(width: 2.5)

                SelectableTextView(
                    attributed: cachedText {
                        builder.paragraph(
                            text,
                            size: typography.quoteSize,
                            color: UIColor(theme.inkSecondary),
                            highlights: highlights
                        )
                    },
                    measurementKey: key(),
                    markupTool: markup?.tool,
                    onHighlight: onHighlight,
                    onSentenceTap: { markup?.onSentenceTap(index, $0, $1) },
                    onOpenLink: onOpenLink
                )
            }
            .padding(.vertical, 4)

        case .code(let source):
            ScrollView(.horizontal, showsIndicators: false) {
                SelectableTextView(
                    attributed: cachedText { builder.code(source) },
                    measurementKey: key()
                )
                .padding(14)
            }
            .background(theme.codeBackground, in: .rect(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(theme.rule, lineWidth: 0.5)
            )

        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: typography.bodySize * 0.42) {
                ForEach(Array(items.enumerated()), id: \.offset) { position, item in
                    HStack(alignment: .top, spacing: 10) {
                        Text(ordered ? "\(position + 1)." : "•")
                            .font(typography.font(size: typography.bodySize))
                            .foregroundStyle(theme.inkSecondary)
                            .frame(minWidth: ordered ? 24 : 12, alignment: .trailing)

                        SelectableTextView(
                            attributed: cachedText(position + 1) { builder.paragraph(item) },
                            measurementKey: key(position + 1),
                            onOpenLink: onOpenLink
                        )
                    }
                }
            }
            .padding(.leading, 4)

        case .image(let image):
            if let stored = post.image(id: image.assetID) {
                VStack(alignment: .leading, spacing: 8) {
                    ArchivedImageView(image: stored, contentMode: .fit)
                        .aspectRatio(stored.aspectRatio.map { CGFloat($0) }, contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(theme.rule, lineWidth: 0.5)
                        )

                    if let caption = image.caption, !caption.isEmpty {
                        SelectableTextView(
                            attributed: cachedText {
                                builder.paragraph(
                                    caption,
                                    size: typography.captionSize,
                                    color: UIColor(theme.inkSecondary)
                                )
                            },
                            measurementKey: key(),
                            onOpenLink: onOpenLink
                        )
                    }
                }
                .padding(.vertical, 6)
            }

        case .divider:
            HStack {
                Spacer()
                Text("❋")
                    .font(typography.font(size: typography.bodySize * 0.8))
                    .foregroundStyle(theme.inkSecondary.opacity(0.6))
                Spacer()
            }
            .padding(.vertical, typography.bodySize * 0.7)
        }
    }
}
