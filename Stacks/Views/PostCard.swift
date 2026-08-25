import SwiftUI

/// One entry in the library, drawn as a card: a cover, a serif headline, two
/// lines of the article's own opening, and a hairline of metadata.
///
/// The cover is the post's lead image where there is one. Where there isn't —
/// which is most of the personal blogs this app exists for — it falls back to a
/// tone drawn from the host, so a site is recognisable at a glance without
/// pretending to a picture it never had.
struct PostCard: View {
    let post: Post
    var isSelected: Bool = false
    /// The active search text, squeezed and empty when not searching — see
    /// `PostRow`, which the same convention comes from.
    var searchQuery: String = ""

    /// Fetched on demand; see `loadSnippet()`.
    @State private var snippet: SearchSnippet?

    private var isSearching: Bool { !searchQuery.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cover
            details
        }
        .background(Palette.card)
        .clipShape(.rect(cornerRadius: 15))
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .strokeBorder(isSelected ? Palette.accent : Palette.rule, lineWidth: isSelected ? 1 : 0.5)
        )
        .shadow(
            color: .black.opacity(isSelected ? 0.10 : 0.04),
            radius: isSelected ? 10 : 3,
            y: isSelected ? 5 : 1
        )
        .task(id: SnippetRequest(postID: post.id, query: searchQuery)) {
            snippet = loadSnippet()
        }
    }

    /// Only this call touches `post.searchText` — see `PostRow.loadSnippet()`,
    /// which this mirrors. A card is still one `List` row under the hood (see
    /// `PostList` in `LibraryView`), so the same on-screen-only guarantee
    /// applies here: this runs once per card that is actually built, not once
    /// per match.
    private func loadSnippet() -> SearchSnippet? {
        guard isSearching, post.state == .ready else { return nil }
        return SearchSnippetBuilder.snippet(in: post.searchText, query: searchQuery)
    }

    // MARK: - Cover

    private var cover: some View {
        // A clear sizer sets the 16:9 box; the picture fills it and is cropped
        // to it. Putting the ratio on the image itself would let a tall photo
        // push the card open instead.
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                if let image = post.leadImage {
                    ArchivedImageView(image: image, maxPixel: 900)
                } else {
                    Palette.tone(for: post.host)
                        .overlay(Hatching())
                        .overlay(
                            Text(initial)
                                .font(.system(size: 34, design: .serif))
                                .foregroundStyle(Palette.ink.opacity(0.17))
                        )
                }
            }
            .clipped()
            .overlay(alignment: .topTrailing) {
                if post.isStarred {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.star)
                        .padding(9)
                        .shadow(color: .black.opacity(0.25), radius: 2)
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Palette.rule).frame(height: 0.5)
            }
    }

    private var initial: String { Post.initial(for: post.host) }

    // MARK: - Details

    private var details: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                if post.isUnread && post.state == .ready {
                    Circle()
                        .fill(Palette.accent)
                        .frame(width: 6, height: 6)
                        .padding(.top, 7)
                }

                Text(post.title)
                    .font(.system(size: 18, weight: .medium, design: .serif))
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(2)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // A search snippet takes the excerpt's place rather than sitting
            // alongside it — the same slot, the same two-line clamp, so a card
            // never grows taller because a search is active. Query and result
            // are both live per keystroke; the shape of the card stays fixed.
            if isSearching, let snippet {
                SearchSnippetText(snippet: snippet)
            } else if !post.excerpt.isEmpty {
                Text(post.excerpt)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.inkSecondary)
                    .lineSpacing(2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PostMetaLine(post: post)
                .padding(.top, 2)

            if post.state == .ready,
               post.readProgress > 0.02, post.readProgress < 0.99 {
                ProgressRule(fraction: post.readProgress)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The small-caps line under a headline: where it came from, how long it is,
/// and whether it has been written on.
struct PostMetaLine: View {
    let post: Post

    var body: some View {
        switch post.state {
        case .pending, .fetching:
            HStack(spacing: 7) {
                ProgressView().controlSize(.mini)
                Text(post.state == .pending ? "Queued" : "Fetching…")
                    .modifier(MetaStyle())
            }

        case .failed:
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                Text(post.failureReason ?? "Couldn't be saved")
                    .lineLimit(2)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Palette.accent)

        case .ready:
            HStack(spacing: 7) {
                Text(post.host)
                    .modifier(MetaStyle())
                    .lineLimit(1)

                Circle()
                    .fill(Palette.ruleStrong)
                    .frame(width: 2.5, height: 2.5)

                Text("\(post.readingMinutes) min")
                    .modifier(MetaStyle())
                    .fixedSize()

                Spacer(minLength: 4)

                if post.hasMarkup {
                    Image(systemName: "highlighter")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.inkTertiary)
                        .accessibilityLabel("Marked up")
                }
            }
        }
    }
}

/// The thread of read progress under a card.
struct ProgressRule: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.rule)
                Capsule()
                    .fill(Palette.accent.opacity(0.7))
                    .frame(width: geometry.size.width * fraction.clamped(to: 0...1))
            }
        }
        .frame(height: 2)
        .accessibilityLabel("\(Int(fraction * 100))% read")
    }
}

/// The diagonal rule that stands in for a picture the post never had. Drawn
/// rather than tiled so it stays crisp at any card width.
struct Hatching: View {
    var spacing: CGFloat = 9

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            context.stroke(path, with: .color(.white.opacity(0.28)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

/// Small caps with generous tracking — the byline voice used throughout.
struct MetaStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 10.5, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.7)
            .foregroundStyle(Palette.inkTertiary)
    }
}
