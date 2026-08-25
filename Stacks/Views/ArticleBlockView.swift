import SwiftUI

/// Renders one article block in the reader's current typography.
struct ArticleBlockView: View {
    let block: ArticleBlock
    let index: Int
    let post: Post
    let builder: AttributedTextBuilder
    let highlights: [Highlight]
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

    var body: some View {
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
                onHighlight: onHighlight,
                onOpenLink: onOpenLink
            )
            .padding(.top, level <= 2 ? typography.bodySize * 1.1 : typography.bodySize * 0.7)
            .padding(.bottom, typography.bodySize * 0.1)

        case .paragraph(let text):
            SelectableTextView(
                attributed: cachedText { builder.paragraph(text, highlights: highlights) },
                measurementKey: key(),
                onHighlight: onHighlight,
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
                    onHighlight: onHighlight,
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
                    .font(.system(size: typography.bodySize * 0.8))
                    .foregroundStyle(theme.inkSecondary.opacity(0.6))
                Spacer()
            }
            .padding(.vertical, typography.bodySize * 0.7)
        }
    }
}
