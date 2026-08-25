import Foundation
import SwiftData

/// What the library list is currently showing.
enum LibraryFilter: Hashable, Codable {
    case unread
    case all
    case starred
    case archived
    case tag(String)
    case site(String)

    var title: String {
        switch self {
        case .unread: "Unread"
        case .all: "Everything"
        case .starred: "Starred"
        case .archived: "Archived"
        case .tag(let name): name
        case .site(let host): host
        }
    }

    var symbol: String {
        switch self {
        case .unread: "tray.full"
        case .all: "books.vertical"
        case .starred: "star"
        case .archived: "archivebox"
        case .tag: "tag"
        case .site: "globe"
        }
    }

    var emptyHeadline: String {
        switch self {
        case .unread: "Nothing waiting"
        case .all: "Your stack is empty"
        case .starred: "No stars yet"
        case .archived: "Nothing archived"
        case .tag(let name): "Nothing tagged \(name)"
        case .site(let host): "Nothing from \(host)"
        }
    }

    var emptyDetail: String {
        switch self {
        case .unread: "Nothing waiting to be read. Share a link from Safari, or tap + to paste one."
        case .all: "Share a link from Safari, or tap + to paste a URL. Stacks pulls the article down and keeps it for good."
        case .starred: "Star a post while reading and it will show up here."
        case .archived: "Posts you archive are kept out of the way but stay searchable."
        case .tag: "Add this tag to a post and it will appear here."
        case .site: "Nothing saved from this site yet."
        }
    }

    /// Archived posts are hidden everywhere except their own list, so the
    /// inbox stays a genuine inbox.
    func predicate(search: String) -> Predicate<Post> {
        let query = search.squeezed
        let hasQuery = !query.isEmpty

        switch self {
        case .unread:
            return #Predicate<Post> { post in
                post.isArchived == false && post.openedAt == nil
                    && (!hasQuery || post.searchText.localizedStandardContains(query))
            }
        case .all:
            return #Predicate<Post> { post in
                post.isArchived == false
                    && (!hasQuery || post.searchText.localizedStandardContains(query))
            }
        case .starred:
            return #Predicate<Post> { post in
                post.isStarred
                    && (!hasQuery || post.searchText.localizedStandardContains(query))
            }
        case .archived:
            return #Predicate<Post> { post in
                post.isArchived
                    && (!hasQuery || post.searchText.localizedStandardContains(query))
            }
        case .tag(let name):
            return #Predicate<Post> { post in
                post.tagNames.contains(name)
                    && (!hasQuery || post.searchText.localizedStandardContains(query))
            }
        case .site(let host):
            return #Predicate<Post> { post in
                post.host == host
                    && (!hasQuery || post.searchText.localizedStandardContains(query))
            }
        }
    }
}

/// A window of a post's search text around the occurrence chosen to represent
/// a query match, with the matched phrase split out so it can be drawn in a
/// different style from the words around it.
struct SearchSnippet: Equatable {
    var leading: String
    var match: String
    var trailing: String
}

/// Builds a `SearchSnippet` from a post's full search text.
///
/// This is deliberately never run over a whole result set. `post.searchText`
/// is the one attribute `Post` keeps out of the row a `List` cell is built
/// from (see `PostList` in `LibraryView`), so calling this at all is what
/// faults it back in — and it is only ever called from `PostRow` or
/// `PostCard`, whose bodies only run for the cells a `List` actually puts on
/// screen. Scrolling past a thousand other matches never touches their text.
enum SearchSnippetBuilder {
    /// Characters of context kept on each side of the match.
    private static let contextRadius = 70
    /// However often a phrase repeats in one article, extraction stops
    /// looking after this many hits — enough to choose well without turning a
    /// pathological repeat into an unbounded scan of the whole body.
    private static let maxOccurrencesConsidered = 20

    private static let matchOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]

    static func snippet(in text: String, query: String) -> SearchSnippet? {
        let phrase = query.squeezed
        guard !phrase.isEmpty, !text.isEmpty else { return nil }

        // `Post.searchText` joins its fields — and the paragraphs within
        // them — with newlines. Matching against the raw text would miss any
        // multi-word query whose words straddle one of those breaks (an
        // exact substring search doesn't know "\n\n" and " " are the same
        // gap), so every occurrence, the ranking pass, and the window this
        // returns all operate on one whitespace-collapsed copy instead.
        let normalizedText = normalized(text)
        guard !normalizedText.isEmpty else { return nil }

        var occurrences: [Range<String.Index>] = []
        var cursor = normalizedText.startIndex
        while occurrences.count < maxOccurrencesConsidered,
              let found = normalizedText.range(of: phrase, options: matchOptions, range: cursor..<normalizedText.endIndex) {
            occurrences.append(found)
            cursor = found.upperBound
        }
        guard let chosen = mostRepresentative(of: occurrences, in: normalizedText, phrase: phrase) else { return nil }
        return window(around: chosen, in: normalizedText)
    }

    /// When a phrase turns up more than once, the occurrence whose
    /// surroundings repeat the query's own words most — *outside* the matched
    /// span itself, which trivially contains all of them and so can't be what
    /// discriminates — wins: that passage is the one that actually explains
    /// the match, rather than a glancing mention in a caption or a tag list.
    /// A single-word query has no other words to look for there, so it — and
    /// any tie — falls back to the first occurrence, which is the one a
    /// reader scanning top to bottom would meet first anyway.
    private static func mostRepresentative(
        of occurrences: [Range<String.Index>], in text: String, phrase: String
    ) -> Range<String.Index>? {
        guard let first = occurrences.first else { return nil }
        let words = phrase.split(separator: " ").map(String.init)
        guard words.count > 1 else { return first }

        var best = first
        var bestScore = -1
        for occurrence in occurrences {
            let start = text.index(occurrence.lowerBound, offsetBy: -contextRadius, limitedBy: text.startIndex) ?? text.startIndex
            let end = text.index(occurrence.upperBound, offsetBy: contextRadius, limitedBy: text.endIndex) ?? text.endIndex
            let before = text[start..<occurrence.lowerBound]
            let after = text[occurrence.upperBound..<end]
            let score = words.reduce(0) { total, word in
                total + occurrenceCount(of: word, in: before) + occurrenceCount(of: word, in: after)
            }
            if score > bestScore {
                bestScore = score
                best = occurrence
            }
        }
        return best
    }

    /// How many times `word` turns up in `text` — always called on a slice
    /// already bounded to `contextRadius`, so this never scans more than a
    /// small neighbourhood.
    private static func occurrenceCount(of word: String, in text: some StringProtocol) -> Int {
        var count = 0
        var cursor = text.startIndex
        while let found = text.range(of: word, options: matchOptions, range: cursor..<text.endIndex) {
            count += 1
            cursor = found.upperBound
        }
        return count
    }

    /// Trims a window to whole words. `text` here is already the
    /// whitespace-collapsed copy `snippet(in:query:)` built, so this only has
    /// to cut cleanly, not normalise again.
    private static func window(around match: Range<String.Index>, in text: String) -> SearchSnippet {
        let start = text.index(match.lowerBound, offsetBy: -contextRadius, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(match.upperBound, offsetBy: contextRadius, limitedBy: text.endIndex) ?? text.endIndex

        var leading = String(text[start..<match.lowerBound])
        var trailing = String(text[match.upperBound..<end])

        if start != text.startIndex {
            if let space = leading.firstIndex(where: \.isWhitespace) {
                leading = String(leading[leading.index(after: space)...])
            }
            leading = "…" + leading
        }
        if end != text.endIndex {
            if let space = trailing.lastIndex(where: \.isWhitespace) {
                trailing = String(trailing[..<space])
            }
            trailing += "…"
        }

        return SearchSnippet(leading: leading, match: String(text[match]), trailing: trailing)
    }

    /// Collapses every run of whitespace — including the newlines
    /// `Post.searchText` is built with — to a single space.
    private static func normalized(_ substring: some StringProtocol) -> String {
        substring.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case recentlySaved, oldestFirst, longestFirst, shortestFirst, title

    var id: String { rawValue }

    /// The orders worth a chip under the search field; the rest live in the
    /// sort sheet.
    static let quickChoices: [LibrarySort] = [.recentlySaved, .oldestFirst, .longestFirst]

    var label: String {
        switch self {
        case .recentlySaved: "Recently saved"
        case .oldestFirst: "Oldest first"
        case .longestFirst: "Longest first"
        case .shortestFirst: "Shortest first"
        case .title: "Title"
        }
    }

    var descriptors: [SortDescriptor<Post>] {
        switch self {
        case .recentlySaved: [SortDescriptor(\.savedAt, order: .reverse)]
        case .oldestFirst: [SortDescriptor(\.savedAt, order: .forward)]
        case .longestFirst: [SortDescriptor(\.wordCount, order: .reverse)]
        case .shortestFirst: [SortDescriptor(\.wordCount, order: .forward)]
        case .title: [SortDescriptor(\.title, comparator: .localizedStandard)]
        }
    }
}
