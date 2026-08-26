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

    @Test("A document split across sibling sections keeps every section, not just the best-scoring one")
    func siblingSectionsAllSurvive() {
        // Several `<div class="chapter">` elements as direct siblings of
        // `<body>`, nothing wrapping them — the shape that collapsed to a
        // single surviving chapter (see Fixtures/README.md and
        // gutenberg_frankenstein): no shared ancestor closer than `<body>`
        // ever scored highly enough for the old "climb to a nearly-as-good
        // parent" step to reach, so only the single best-scoring sibling
        // survived and the rest of the book was silently dropped.
        let chapters = (1...5).map { index in
            "<div class=\"chapter\"><h2>Chapter \(index)</h2><p>\(paragraph) Chapter marker \(index).</p><p>\(paragraph)</p></div>"
        }.joined()
        let article = extract(page(chapters))
        for index in 1...5 {
            #expect(article.content.plainText.contains("Chapter marker \(index)."), "chapter \(index) was dropped")
        }
    }

    @Test("A bare-identifier <h1> next to the real headline become one title")
    func splitHeadingTitle() {
        // Found on rfc-editor.org's RFC pages, which render the RFC number
        // and its actual title as two separate <h1> elements. Taking only
        // the first (`document.firstElement(tagged: "h1")`) left every RFC
        // titled just "RFC 9110" — indistinguishable from "RFC 9111" in a
        // saved-articles list.
        let article = extract(page("<article><h1>RFC 9999</h1><h1>Testing Split Headings</h1><p>\(paragraph)</p></article>"))
        #expect(article.title == "RFC 9999: Testing Split Headings")
    }

    @Test("A second <h1> identical to the first doesn't get appended")
    func repeatedHeadingTitleUnchanged() {
        let article = extract(page("<article><h1>Same Title</h1><h1>Same Title</h1><p>\(paragraph)</p></article>"))
        #expect(article.title == "Same Title")
    }

    @Test("A non-English site suffix trims even when the site's own name carries a diacritic")
    func diacriticSiteSuffixTrims() {
        // fr.wikipedia.org's <title> reads "Page — Wikipédia"; the host-derived
        // candidate name is the ASCII "wikipedia" pulled out of the domain, so
        // a plain case-insensitive comparison against "wikipédia" never
        // matched and the site suffix was never trimmed.
        let html = "<html><head><title>Tour Eiffel — Wikipédia</title></head><body><article><p>\(paragraph)</p></article></body></html>"
        let article = ArticleExtractor.extract(html: html, url: URL(string: "https://fr.wikipedia.org/wiki/Tour_Eiffel")!)
        #expect(article.title == "Tour Eiffel")
    }
}

@Suite("Tables")
struct TableTests {

    @Test("A multi-row layout table recurses into each cell's paragraphs")
    func multiRowLayoutTable() {
        // Two rows, each a full-width cell wrapping its own paragraph — the
        // same "table as a layout grid" trick as a single-row table, just
        // stacked. Neither row is tabular data, so each cell's <p> should
        // survive as its own block instead of being joined into a row line.
        let article = extract(page("""
        <article><table>
        <tr><td><p>\(paragraph)</p></td></tr>
        <tr><td><p>\(paragraph)</p></td></tr>
        </table></article>
        """))
        let paragraphs = article.content.blocks.filter { if case .paragraph = $0 { return true } else { return false } }
        #expect(paragraphs.count == 2)
    }

    @Test("A table nested inside a layout cell is recursed on its own terms")
    func nestedTable() {
        // The outer table is a layout wrapper for prose; the inner table is
        // genuine key/value data. Recursing into the outer cell should reach
        // the paragraph, and the nested table should still resolve as data
        // (a list), not have its rows mistaken for the outer table's own.
        let article = extract(page("""
        <article><table><tr><td>
        <p>\(paragraph)</p>
        <table><tr><td>Published</td><td>2026</td></tr><tr><td>Author</td><td>M. Alden</td></tr></table>
        </td></tr></table></article>
        """))
        let paragraphs = article.content.blocks.filter { if case .paragraph = $0 { return true } else { return false } }
        let lists = article.content.blocks.filter { if case .list = $0 { return true } else { return false } }
        #expect(paragraphs.count == 1)
        #expect(lists.count == 1)
    }

    @Test("A genuine data table keeps its rows joined, not shredded per cell")
    func dataTableStaysJoined() {
        // Cells hold bare values, not block content, so the rows should still
        // collapse to one list item apiece rather than becoming a paragraph
        // per cell — the failure mode a naive "always recurse" fix would add.
        let article = extract(page("""
        <article><p>\(paragraph)</p>
        <table>
        <tr><td>Author</td><td>M. Alden</td></tr>
        <tr><td>Published</td><td>2026</td></tr>
        <tr><td>Pages</td><td>212</td></tr>
        </table></article>
        """))
        let lists = article.content.blocks.compactMap { block -> [RichText]? in
            if case .list(_, let items) = block { return items }
            return nil
        }
        #expect(lists.count == 1)
        #expect(lists.first?.count == 3)
    }

    @Test("A winning candidate that is itself a <tbody> still finds its rows and images")
    func tbodyCandidateKeepsStructure() {
        // `ArticleExtractor.bestCandidate`'s climb from a scored cell can
        // rest on the <tbody> instead of climbing one more level to the
        // enclosing <table> (a wikitable's overall link density can clear
        // the climb's threshold even though the row-group alone doesn't).
        // `BlockBuilder.build(from:)` used to call `descend` unconditionally,
        // which only recognizes a block producer among an element's
        // *children* — neither "tbody" nor "tr" nor "td" was ever one, so a
        // <tbody> handed in as the root got flattened into one inline run
        // with every image silently dropped (found via a real capture of
        // Wikipedia's flag table, https://en.wikipedia.org/wiki/List_of_national_flags_of_sovereign_states).
        let html = """
        <table><tbody>
        <tr><td><img src="https://example.com/a.jpg" width="80" height="80"></td><td>Alpha</td></tr>
        <tr><td><img src="https://example.com/b.jpg" width="80" height="80"></td><td>Beta</td></tr>
        </tbody></table>
        """
        let document = HTMLParser.parse(html)
        guard let tbody = document.firstElement(tagged: "tbody") else {
            Issue.record("expected the fixture to parse a <tbody>")
            return
        }
        let content = BlockBuilder.content(from: tbody, baseURL: URL(string: "https://example.com/post")!)
        let images = content.blocks.filter { if case .image = $0 { return true } else { return false } }
        #expect(images.count == 2, "a <tbody> passed straight to the block builder should still rescue its row images")
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
