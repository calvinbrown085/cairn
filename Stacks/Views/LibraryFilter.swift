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
