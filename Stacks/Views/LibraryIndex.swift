import Foundation
import SwiftData
import Observation

/// Counts and groupings for the sidebar.
///
/// Computed with targeted fetches rather than a `@Query` over every post, so
/// showing the sidebar never pulls whole article bodies into memory.
@MainActor
@Observable
final class LibraryIndex {
    struct Group: Identifiable, Hashable {
        var name: String
        var count: Int
        var id: String { name }
    }

    private(set) var unreadCount = 0
    private(set) var totalCount = 0
    private(set) var starredCount = 0
    private(set) var archivedCount = 0
    private(set) var tags: [Group] = []
    private(set) var sites: [Group] = []

    func refresh(context: ModelContext) {
        unreadCount = count(context, #Predicate { !$0.isArchived && $0.openedAt == nil })
        totalCount = count(context, #Predicate { !$0.isArchived })
        starredCount = count(context, #Predicate { $0.isStarred })
        archivedCount = count(context, #Predicate { $0.isArchived })

        var descriptor = FetchDescriptor<Post>(predicate: #Predicate { !$0.isArchived })
        // Only the grouping columns — not the article text.
        descriptor.propertiesToFetch = [\.tagNames, \.host]

        guard let posts = try? context.fetch(descriptor) else {
            tags = []
            sites = []
            return
        }

        var tagCounts: [String: Int] = [:]
        var siteCounts: [String: Int] = [:]
        // Tags match case-insensitively but display with the casing first used.
        var tagDisplay: [String: String] = [:]

        for post in posts {
            for tag in post.tagNames {
                let key = tag.lowercased()
                tagCounts[key, default: 0] += 1
                if tagDisplay[key] == nil { tagDisplay[key] = tag }
            }
            let host = post.host
            if !host.isEmpty { siteCounts[host, default: 0] += 1 }
        }

        tags = tagCounts
            .map { Group(name: tagDisplay[$0.key] ?? $0.key, count: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        sites = siteCounts
            .map { Group(name: $0.key, count: $0.value) }
            .sorted {
                $0.count == $1.count
                    ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    : $0.count > $1.count
            }
    }

    private func count(_ context: ModelContext, _ predicate: Predicate<Post>) -> Int {
        (try? context.fetchCount(FetchDescriptor<Post>(predicate: predicate))) ?? 0
    }
}
