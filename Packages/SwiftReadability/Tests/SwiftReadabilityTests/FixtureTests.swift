import Foundation
import Testing
@testable import SwiftReadability

/// Runs every fixture under `Fixtures/` through the extractor and checks the
/// result against its frozen expectation. These are hand-authored
/// reproductions of real-world page shapes, not captures of live pages — see
/// the fixture HTML files for the shape each one stands in for.
///
/// A regression in `ArticleExtractor` or `HTMLParser` that shifts the title,
/// the word count, or the mix of block types on any fixture fails here.
@Suite("Fixtures")
struct FixtureTests {

    @Test("Extraction matches the frozen fixture", arguments: FixtureLoader.allNames)
    func matchesFrozenExpectation(name: String) {
        let expectation = FixtureLoader.expectation(name)
        let html = FixtureLoader.html(name)
        let article = ArticleExtractor.extract(html: html, url: URL(string: "https://example.com/\(name)")!)

        #expect(article.title == expectation.title, "title changed for fixture '\(name)'")
        #expect(article.content.wordCount == expectation.wordCount, "word count changed for fixture '\(name)'")
        #expect(article.content.blockCounts == expectation.blockCounts, "block-type mix changed for fixture '\(name)'")
    }

    @Test("The fixture set is non-empty")
    func fixturesArePresent() {
        // Guards the harness itself: if resource bundling ever breaks, every
        // fixture test above would silently vanish instead of failing.
        #expect(FixtureLoader.allNames.count >= 3)
    }
}

private extension ArticleContent {
    /// How many blocks of each kind the content holds, keyed by the same
    /// names fixture JSON files use.
    var blockCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for block in blocks {
            counts[block.kind, default: 0] += 1
        }
        return counts
    }
}

private extension ArticleBlock {
    var kind: String {
        switch self {
        case .heading: return "heading"
        case .paragraph: return "paragraph"
        case .quote: return "quote"
        case .code: return "code"
        case .list: return "list"
        case .image: return "image"
        case .divider: return "divider"
        }
    }
}
