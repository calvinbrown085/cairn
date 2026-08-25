import Foundation
import Testing
@testable import SwiftReadability

/// Prose long enough to survive content scoring — the extractor is meant to
/// discard short furniture, so a test fixture has to look like a real article.
private let paragraph = """
The archive is the product. A read-later app that optimises the save and \
neglects what happens afterwards turns into a landfill, and a landfill is \
something people delete. Retrieval is what makes an old library worth keeping.
"""

private func extract(_ html: String) -> ExtractedArticle {
    ArticleExtractor.extract(html: html, url: URL(string: "https://example.com/post")!)
}

private func page(_ body: String, title: String = "A Title") -> String {
    "<html><head><title>\(title)</title></head><body>\(body)</body></html>"
}

@Suite("Extractor")
struct ExtractorTests {

    @Test("Reads the document title")
    func title() {
        let article = extract(page("<article><p>\(paragraph)</p><p>\(paragraph)</p></article>"))
        #expect(article.title == "A Title")
    }

    @Test("Keeps prose paragraphs as paragraph blocks")
    func paragraphs() {
        let article = extract(page("<article><p>\(paragraph)</p><p>\(paragraph)</p></article>"))
        let paragraphs = article.content.blocks.filter { if case .paragraph = $0 { return true } else { return false } }
        #expect(paragraphs.count == 2)
    }

    @Test("Drops navigation and footer furniture")
    func furniture() {
        let article = extract(page("""
        <nav><a href="/">Home</a><a href="/about">About</a></nav>
        <article><p>\(paragraph)</p><p>\(paragraph)</p></article>
        <footer>Copyright 2026</footer>
        """))
        #expect(!article.content.plainText.contains("Copyright"))
        #expect(!article.content.plainText.contains("About"))
    }

    @Test("Headings keep their level")
    func headings() {
        let article = extract(page("<article><h2>Section</h2><p>\(paragraph)</p><p>\(paragraph)</p></article>"))
        let heading = article.content.blocks.compactMap { block -> (Int, String)? in
            if case .heading(let level, let text) = block { return (level, text.plain) }
            return nil
        }.first
        #expect(heading?.0 == 2)
        #expect(heading?.1 == "Section")
    }

    @Test("Word count reflects extracted prose, not markup")
    func wordCount() {
        let article = extract(page("<article><p>\(paragraph)</p><p>\(paragraph)</p></article>"))
        #expect(article.content.wordCount > 40)
        #expect(!article.content.plainText.contains("<"))
    }

    @Test("Content survives an encode/decode round trip")
    func roundTrip() {
        let article = extract(page("<article><p>\(paragraph)</p><p>\(paragraph)</p></article>"))
        let restored = ArticleContent.decoded(from: article.content.encoded())
        #expect(restored == article.content)
    }
}

@Suite("Entities")
struct EntityTests {

    @Test("Named and numeric entities are decoded in extracted prose")
    func entities() {
        let article = extract(page("<article><p>Ren&eacute; &amp; Co&nbsp;&#8212; caf&#233;. \(paragraph)</p><p>\(paragraph)</p></article>"))
        let text = article.content.plainText
        #expect(text.contains("René"))
        #expect(text.contains("&") && !text.contains("&amp;"))
        #expect(text.contains("café"))
    }
}
