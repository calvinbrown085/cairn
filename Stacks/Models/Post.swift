import Foundation
import SwiftData
import SwiftReadability

enum PostState: String, Codable, CaseIterable {
    case pending    // queued, not yet fetched
    case fetching
    case ready
    case failed
}

/// One archived blog post.
///
/// Every stored property carries a default and every relationship is optional —
/// both are hard requirements for a SwiftData model backed by CloudKit.
@Model
final class Post {
    var id: UUID = UUID()
    var urlString: String = ""
    /// The URL with tracking parameters and fragments removed — two links to the
    /// same article should not become two archived posts.
    var canonicalURLString: String = ""
    var title: String = ""
    var author: String?
    var siteName: String = ""
    var host: String = ""
    var excerpt: String = ""

    var publishedAt: Date?
    /// The zone the publication date was written in; see `publishedDisplay`.
    var publishedOffset: Int?
    var savedAt: Date = Date.now
    var openedAt: Date?
    var finishedAt: Date?

    var wordCount: Int = 0
    var isStarred: Bool = false
    var isArchived: Bool = false

    /// 0…1, driven by the topmost visible block in the reader.
    var readProgress: Double = 0
    var lastBlockIndex: Int = 0

    var stateRaw: String = PostState.pending.rawValue
    var failureReason: String?

    var tagNames: [String] = []

    /// The block list, JSON-encoded. External storage keeps the article body out
    /// of the row so list queries stay light.
    @Attribute(.externalStorage) var contentData: Data?

    /// Flattened body text, kept inline so `#Predicate` can search it.
    var searchText: String = ""

    var leadImageID: UUID?

    @Relationship(deleteRule: .cascade, inverse: \StoredImage.post)
    var images: [StoredImage]?

    @Relationship(deleteRule: .cascade, inverse: \Highlight.post)
    var highlights: [Highlight]?

    @Relationship(deleteRule: .cascade, inverse: \InkStroke.post)
    var inkStrokes: [InkStroke]?

    init(url: URL) {
        self.id = UUID()
        self.urlString = url.absoluteString
        self.canonicalURLString = url.canonicalizedForArchive().absoluteString
        self.host = Post.displayHost(for: url)
        self.siteName = self.host
        self.title = self.host
        self.savedAt = .now
        self.stateRaw = PostState.pending.rawValue
        self.images = []
        self.highlights = []
        self.inkStrokes = []
    }

    init() {}

    // MARK: - Derived

    var state: PostState {
        get { PostState(rawValue: stateRaw) ?? .ready }
        set { stateRaw = newValue.rawValue }
    }

    var url: URL? { URL(string: urlString) }

    var content: ArticleContent { ArticleContent.decoded(from: contentData) }

    var isUnread: Bool { openedAt == nil }

    /// 220 wpm is the usual reading-speed constant for prose.
    var readingMinutes: Int { max(1, Int((Double(wordCount) / 220.0).rounded())) }

    /// The publication date as the publisher dated it, not as the reader's
    /// time zone would re-interpret it.
    var publishedDisplay: String? {
        guard let publishedAt else { return nil }
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = TimeZone(secondsFromGMT: publishedOffset ?? 0) ?? .gmt
        formatter.setLocalizedDateFormatFromTemplate("MMMdyyyy")
        return formatter.string(from: publishedAt)
    }

    /// Anything the reader added on top of the text.
    var hasMarkup: Bool {
        !(highlights ?? []).isEmpty || !(inkStrokes ?? []).isEmpty
    }

    var sortedHighlights: [Highlight] {
        (highlights ?? []).sorted {
            ($0.blockIndex, $0.start) < ($1.blockIndex, $1.start)
        }
    }

    func image(id: UUID?) -> StoredImage? {
        guard let id else { return nil }
        return (images ?? []).first { $0.id == id }
    }

    var leadImage: StoredImage? { image(id: leadImageID) }

    /// The single letter a card falls back to when a post has no lead image.
    static func initial(for host: String) -> String {
        guard let first = host.first else { return "·" }
        return String(first).uppercased()
    }

    static func displayHost(for url: URL) -> String {
        guard let host = url.host() else { return url.absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Applies a freshly extracted article, replacing any previous content.
    func apply(_ article: ExtractedArticle, content: ArticleContent) {
        title = article.title.isEmpty ? host : article.title
        author = article.author
        siteName = article.siteName ?? host
        excerpt = article.excerpt
        publishedAt = article.publishedAt
        publishedOffset = article.publishedOffset
        contentData = content.encoded()
        wordCount = content.wordCount
        searchText = Post.buildSearchText(
            title: title, author: author, siteName: siteName,
            host: host, tags: tagNames, body: content.plainText
        )
        state = .ready
        failureReason = nil
    }

    func refreshSearchText() {
        searchText = Post.buildSearchText(
            title: title, author: author, siteName: siteName,
            host: host, tags: tagNames, body: content.plainText
        )
    }

    static func buildSearchText(
        title: String, author: String?, siteName: String,
        host: String, tags: [String], body: String
    ) -> String {
        [title, author ?? "", siteName, host, tags.joined(separator: " "), body]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

/// A downloaded image. Bytes live in external storage so CloudKit ships them as
/// assets rather than inflating the record.
@Model
final class StoredImage {
    var id: UUID = UUID()
    @Attribute(.externalStorage) var data: Data = Data()
    var pixelWidth: Double = 0
    var pixelHeight: Double = 0
    var sourceURL: String = ""
    var post: Post?

    init(id: UUID = UUID(), data: Data, pixelWidth: Double, pixelHeight: Double, sourceURL: String) {
        self.id = id
        self.data = data
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.sourceURL = sourceURL
    }

    init() {}

    var aspectRatio: Double? {
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        return pixelWidth / pixelHeight
    }
}

enum HighlightTint: String, Codable, CaseIterable, Identifiable {
    case butter, rose, sky, sage

    var id: String { rawValue }

    var label: String {
        switch self {
        case .butter: "Butter"
        case .rose: "Rose"
        case .sky: "Sky"
        case .sage: "Sage"
        }
    }
}

/// A highlighted passage, anchored to a block index and a character range within
/// that block's plain text — stable across font, theme, and device changes in a
/// way pixel offsets never are.
@Model
final class Highlight {
    var id: UUID = UUID()
    var blockIndex: Int = 0
    var start: Int = 0
    var length: Int = 0
    var text: String = ""
    var note: String?
    var tintRaw: String = HighlightTint.butter.rawValue
    var createdAt: Date = Date.now
    var post: Post?

    init(blockIndex: Int, start: Int, length: Int, text: String, tint: HighlightTint = .butter) {
        self.id = UUID()
        self.blockIndex = blockIndex
        self.start = start
        self.length = length
        self.text = text
        self.tintRaw = tint.rawValue
        self.createdAt = .now
    }

    init() {}

    var tint: HighlightTint {
        get { HighlightTint(rawValue: tintRaw) ?? .butter }
        set { tintRaw = newValue.rawValue }
    }

    var range: NSRange { NSRange(location: start, length: length) }
}
