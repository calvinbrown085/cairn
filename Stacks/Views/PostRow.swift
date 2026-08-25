import SwiftUI

/// One entry in the library. Editorial rather than utilitarian: the headline
/// leads at a readable size, and the metadata sits quietly beneath a hairline.
struct PostRow: View {
    let post: Post

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // A fixed gutter for the unread marker. Keeping it out of the text
            // flow is what lets every headline share one left edge, whether or
            // not the post is unread.
            ZStack(alignment: .topLeading) {
                Color.clear.frame(width: 14)
                if post.isUnread && post.state == .ready {
                    Circle()
                        .fill(Palette.accent)
                        .frame(width: 6, height: 6)
                        .offset(y: 8)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(post.title)
                    .font(.system(size: 18, weight: .medium, design: .serif))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // The hairline between headline and byline is the row's
                // signature; the list's own separators are hidden so the two
                // don't compete.
                Rectangle()
                    .fill(Palette.rule)
                    .frame(height: 0.5)

                metadata
            }

            // Sits alongside the whole text block, not just the headline, so a
            // one-line title doesn't open a gap beneath the rule.
            if post.leadImage != nil {
                ArchivedImageView(image: post.leadImage, maxPixel: 140)
                    .frame(width: 58, height: 58)
                    .clipShape(.rect(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Palette.rule, lineWidth: 0.5)
                    )
                    .padding(.leading, 14)
            }
        }
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private var metadata: some View {
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
            HStack(spacing: 6) {
                Text(post.host)
                    .modifier(MetaStyle())
                    .lineLimit(1)
                    .layoutPriority(1)

                Text("·").modifier(MetaStyle())

                Text("\(post.readingMinutes) min")
                    .modifier(MetaStyle())
                    .fixedSize()

                if post.readProgress > 0.02 && post.readProgress < 0.98 {
                    Text("·").modifier(MetaStyle())
                    Text("\(Int(post.readProgress * 100))%")
                        .modifier(MetaStyle())
                        .foregroundStyle(Palette.accent)
                        .fixedSize()
                }

                if post.isStarred {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.star)
                }

                if !(post.highlights ?? []).isEmpty {
                    Image(systemName: "highlighter")
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.inkTertiary)
                }

                Spacer(minLength: 0)
            }
        }
    }
}

/// Small caps with generous tracking — the byline voice used throughout.
private struct MetaStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 11, weight: .medium))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(Palette.inkSecondary)
    }
}
