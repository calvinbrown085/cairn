import Foundation
import SwiftReadability

/// The reader's prepared, immutable view of a post's body.
///
/// `Post.content` decodes JSON every time it is read. Reading it from a view
/// body means re-decoding the whole article on every scroll tick, so the reader
/// decodes once — off the main actor — and holds the result here.
struct ReaderDocument: Equatable {
    let postID: UUID
    let blocks: [IndexedBlock]

    var count: Int { blocks.count }

    static func load(postID: UUID, contentData: Data?) async -> ReaderDocument {
        let content = await Task.detached(priority: .userInitiated) {
            ArticleContent.decoded(from: contentData)
        }.value
        return ReaderDocument(postID: postID, blocks: content.indexed)
    }
}
