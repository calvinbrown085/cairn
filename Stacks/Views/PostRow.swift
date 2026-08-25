import SwiftUI

/// One entry in the library, drawn as a row — the denser alternative to
/// `PostCard`, for a library that has grown past browsing by cover.
struct PostRow: View {
    let post: Post
    var isSelected: Bool = false

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
                    .font(.system(size: 17, weight: .medium, design: .serif))
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(2)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                PostMetaLine(post: post)

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
                            .font(.system(size: 20, design: .serif))
                            .foregroundStyle(Palette.ink.opacity(0.18))
                    )
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(.rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Palette.rule, lineWidth: 0.5)
        )
        .overlay(alignment: .topTrailing) {
            if post.isStarred {
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.star)
                    .padding(4)
            }
        }
    }
}
