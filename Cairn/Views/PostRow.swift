import SwiftUI

/// One entry in the library, drawn as a row — the denser alternative to
/// `PostCard`, for a library that has grown past browsing by cover.
struct PostRow: View {
    let post: Post
    var isSelected: Bool = false
    /// The active search text, squeezed and empty when not searching. Kept as
    /// a plain string rather than a binding: the row only ever reads it, to
    /// decide whether to go find a snippet.
    var searchQuery: String = ""

    /// Fetched on demand, not held as a property of `post` itself — see
    /// `loadSnippet()`.
    @State private var snippet: SearchSnippet?

    // Scales with the initial-letter placeholder it frames, so the thumbnail
    // grows with the glyph instead of clipping it at accessibility sizes.
    @ScaledMetric(relativeTo: .title3) private var thumbnailSize: CGFloat = 52

    private var isSearching: Bool { !searchQuery.isEmpty }

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            // A fixed gutter for the unread marker. Keeping it out of the text
            // flow is what lets every headline share one left edge, whether or
            // not the post is unread.
            Circle()
                .fill(post.isUnread && post.state == .ready ? Palette.accent : .clear)
                .frame(width: 6, height: 6)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 5) {
                Text(post.title)
                    .font(.scaled(17, weight: .medium, design: .serif, relativeTo: .body))
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(2)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                PostMetaLine(post: post)

                // Gated on `isSearching`, not just `snippet != nil`: clearing the
                // query updates this synchronously, while the `.task` below
                // that nils out a stale `snippet` only catches up on its next
                // run. Without the extra check a cleared search would still
                // show the old snippet for a frame.
                if isSearching, let snippet {
                    SearchSnippetText(snippet: snippet)
                        .padding(.top, 1)
                }

                if post.state == .ready,
                   post.readProgress > 0.02, post.readProgress < 0.99 {
                    ProgressRule(fraction: post.readProgress)
                        .padding(.top, 2)
                }
            }

            thumbnail
        }
        .padding(.vertical, 14)
        .background(isSelected ? Palette.accentSoft.opacity(0.6) : .clear)
        .task(id: SnippetRequest(postID: post.id, query: searchQuery)) {
            snippet = loadSnippet()
        }
    }

    /// Only this call touches `post.searchText` — the one attribute this
    /// row's own fetch left out (see `PostList.descriptor` in `LibraryView`).
    /// Reading it here faults just this post's text back in, and only because
    /// this particular row is on screen; nothing about the rest of the result
    /// set is affected.
    private func loadSnippet() -> SearchSnippet? {
        guard isSearching, post.state == .ready else { return nil }
        return SearchSnippetBuilder.snippet(in: post.searchText, query: searchQuery)
    }

    private var thumbnail: some View {
        Group {
            if let image = post.leadImage {
                ArchivedImageView(image: image, maxPixel: 140)
            } else {
                Palette.tone(for: post.host)
                    .overlay(Hatching(spacing: 7))
                    .overlay(
                        Text(Post.initial(for: post.host))
                            .font(.scaled(20, design: .serif, relativeTo: .title3))
                            .foregroundStyle(Palette.ink.opacity(0.18))
                    )
            }
        }
        .frame(width: thumbnailSize, height: thumbnailSize)
        .clipShape(.rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Palette.rule, lineWidth: 0.5)
        )
        .overlay(alignment: .topTrailing) {
            if post.isStarred {
                Image(systemName: "star.fill")
                    .font(.scaled(9, relativeTo: .caption2))
                    .foregroundStyle(Palette.star)
                    .padding(4)
            }
        }
    }
}

/// Identifies one search-result view's snippet job: which post, under which
/// query. Shared by `PostRow` and `PostCard` — a new keystroke, or a cell
/// recycled onto a different post, is a new id, which is what makes
/// `.task(id:)` cancel a stale extraction instead of letting it finish and
/// overwrite a newer one.
struct SnippetRequest: Equatable {
    var postID: UUID
    var query: String
}

/// The matched phrase picked out of its own surrounding sentence, the phrase
/// itself marked the way a highlighter would. Used by both `PostRow`, under
/// the byline, and `PostCard`, in place of the excerpt — the fixed
/// `lineLimit` below is load-bearing for both: it is what keeps a card's
/// height from changing as a search query changes.
struct SearchSnippetText: View {
    let snippet: SearchSnippet

    var body: some View {
        Text(highlighted)
            .font(.footnote)
            .foregroundStyle(Palette.inkSecondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var highlighted: AttributedString {
        // `leading`/`trailing` were rebuilt word-by-word, which drops the
        // single space that used to sit against the match itself — restore it
        // only where there is a neighbour to separate it from.
        var text = AttributedString(snippet.leading.isEmpty ? "" : snippet.leading + " ")
        var match = AttributedString(snippet.match)
        match.foregroundColor = Palette.ink
        match.backgroundColor = Palette.accentSoft
        // A named text style, not a fixed point size: the highlighted run
        // scales with Dynamic Type exactly as the rest of the line does.
        match.font = Font.footnote.weight(.semibold)
        text.append(match)
        text.append(AttributedString(snippet.trailing.isEmpty ? "" : " " + snippet.trailing))
        return text
    }
}
