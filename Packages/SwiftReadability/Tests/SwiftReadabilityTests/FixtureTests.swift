import Foundation
import Testing
@testable import SwiftReadability

/// Runs every fixture under `Fixtures/` through the extractor and checks the
/// result against its frozen expectation. Most fixtures are frozen captures
/// of real pages (see `Fixtures/PROVENANCE.md`); a few are hand-authored
/// shapes for mechanical edge cases the real corpus doesn't cover (see
/// `Fixtures/README.md`).
///
/// A regression in `ArticleExtractor` or `HTMLParser` that shifts the title,
/// the word count, or the mix of block types on any fixture fails here.
@Suite("Fixtures")
struct FixtureTests {

    @Test("Extraction matches the frozen fixture", arguments: FixtureLoader.allNames)
    func matchesFrozenExpectation(name: String) {
        let expectation = FixtureLoader.expectation(name)
        let html = FixtureLoader.html(name)
        let article = ArticleExtractor.extract(html: html, url: FixtureLoader.sourceURL(name))

        #expect(article.title == expectation.title, "title changed for fixture '\(name)'")
        #expect(article.content.wordCount == expectation.wordCount, "word count changed for fixture '\(name)'")
        #expect(article.content.blockCounts == expectation.blockCounts, "block-type mix changed for fixture '\(name)'")

        // A word count alone hides truncation at the tail as readily as it
        // hides truncation anywhere else — T-0027 dropped 89% of a document
        // and no fixture noticed. Named passages near the start, middle, and
        // end of the source close that hole: each one has to actually survive
        // extraction, not just leave the total looking plausible.
        let haystack = article.content.plainText.searchNormalized
        for landmark in expectation.landmarks {
            #expect(
                haystack.contains(landmark.searchNormalized),
                "landmark passage missing from fixture '\(name)': \(landmark)"
            )
        }
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

private extension String {
    /// Collapses whitespace runs (including the block-joining newlines in
    /// `ArticleContent.plainText`) to a single space so a landmark copied from
    /// rendered prose still matches text that wrapped or was rejoined
    /// differently. Case is left alone: landmarks are copied verbatim from the
    /// source, so a case mismatch is itself worth failing on.
    var searchNormalized: String {
        components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
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
