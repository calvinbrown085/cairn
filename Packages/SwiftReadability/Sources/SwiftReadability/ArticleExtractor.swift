import Foundation

public struct ExtractedArticle {
    public var title: String
    public var author: String?
    public var siteName: String?
    public var excerpt: String
    public var publishedAt: Date?
    public var publishedOffset: Int?
    public var leadImageSource: String?
    public var content: ArticleContent
}

/// A Readability-style content extractor: strip the furniture, score what's left
/// by how much prose it holds, and keep the winning subtree.
public enum ArticleExtractor {

    public static func extract(html: String, url: URL) -> ExtractedArticle {
        let document = HTMLParser.parse(html)
        let metadata = ArticleMetadata(document: document, url: url)

        let body = document.firstElement(tagged: "body") ?? document
        strip(body)

        let candidate = bestCandidate(in: body) ?? body
        var content = BlockBuilder.content(from: candidate, baseURL: url)
        content = polish(content, title: metadata.title)

        // A very short result usually means the scorer picked a teaser card.
        // Retry against the whole body before giving up on the page.
        if content.wordCount < 60, candidate !== body {
            let fallback = polish(BlockBuilder.content(from: body, baseURL: url), title: metadata.title)
            if fallback.wordCount > content.wordCount { content = fallback }
        }

        let excerpt = metadata.description
            ?? content.blocks.compactMap { block -> String? in
                if case .paragraph(let text) = block { return text.plain }
                return nil
            }.first
            ?? ""

        return ExtractedArticle(
            title: metadata.title,
            author: metadata.author,
            siteName: metadata.siteName ?? url.host(),
            excerpt: String(excerpt.squeezed.prefix(320)),
            publishedAt: metadata.publishedAt,
            publishedOffset: metadata.publishedOffset,
            leadImageSource: metadata.leadImage ?? content.imageSources.first?.image.source,
            content: content
        )
    }

    // MARK: - Stripping

    private static let strippedTags: Set<String> = [
        "script", "style", "noscript", "iframe", "svg", "canvas", "form", "button",
        "input", "select", "textarea", "template", "link", "meta", "nav", "aside",
        "footer", "object", "embed", "map", "audio", "video", "dialog",
    ]

    /// Class/id fragments that reliably mark page furniture.
    private static let negativeSignals = [
        "comment", "share", "sharing", "social", "sidebar", "side-bar", "footer",
        "footnote-nav", "related", "recommend", "promo", "advert", "advertis",
        "banner", "sponsor", "subscribe", "subscription", "newsletter", "signup",
        "sign-up", "paywall", "popup", "modal", "cookie", "consent", "breadcrumb",
        "pagination", "pager", "menu", "navbar", "nav-", "masthead", "toolbar",
        "widget", "disqus", "livefyre", "author-box", "bio-box", "meta-", "byline-",
        "tags", "tag-list", "categories", "skip-link", "screen-reader", "sr-only",
        "visually-hidden", "hidden", "print-only", "toc", "table-of-contents",
        "editsection", "mw-editsection", "hatnote", "navbox", "infobox-caption",
        "entry-date", "entry-meta", "post-meta", "article-meta", "posted-on",
        "publish-date", "post-date", "article-date", "timestamp", "post-info",
        "post-list", "postlist", "archive-list", "all-posts", "more-posts",
        "read-next", "read-more", "further-reading", "site-footer", "site-header",
    ]

    /// Fragments that mark real content — checked first so "post-comments" loses
    /// but "post-content" wins.
    private static let positiveSignals = [
        "article", "articlebody", "article-body", "post-content", "postcontent",
        "entry-content", "entrycontent", "content-body", "story-body", "storybody",
        "main-content", "maincontent", "blog-post", "blogpost", "markdown-body",
        "post-body", "postbody", "prose", "essay", "text-body", "rich-text",
    ]

    /// Heading names that mark backmatter — support material for the article,
    /// not part of it — when a container is explicitly bound to one via
    /// `aria-labelledby`. See the check in `strip()` for why the binding
    /// matters as much as the name.
    private static let backmatterHeadings: Set<String> = [
        "references", "notes", "external links", "further reading",
    ]

    private static func isBackmatterHeading(_ idOrText: String) -> Bool {
        let normalized = idOrText
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        return backmatterHeadings.contains(normalized)
    }

    private static func strip(_ root: HTMLElement) {
        var doomed: [HTMLElement] = []

        root.walk { element in
            if strippedTags.contains(element.tag) {
                // <aside>/<footer> inside the article body is sometimes a pull
                // quote worth keeping — but a wall of links is a post index.
                if (element.tag == "aside" || element.tag == "footer"),
                   element.ancestors(limit: 4).contains(where: { $0.tag == "article" }),
                   element.textContent.count > 140,
                   element.linkDensity < 0.3 {
                    return
                }
                doomed.append(element)
                return
            }

            if element.attributes["aria-hidden"] == "true" { doomed.append(element); return }
            if element.attributes["hidden"] != nil { doomed.append(element); return }
            if element.attributes["role"].map({ ["navigation", "banner", "complementary", "search"].contains($0) }) == true {
                doomed.append(element)
                return
            }

            // A backmatter section — a citation list, "Notes", "External
            // links", "Further reading" — support material for the article,
            // not part of it. `aria-labelledby` is how MediaWiki's Parsoid
            // output (and any other generator that follows the same ARIA
            // convention) explicitly binds a container to the heading that
            // introduces it, which is exactly the boundary we need: it names
            // the section without our having to guess where it ends by
            // scanning forward through the flat block list, a guess that
            // would just as happily swallow the first plain, unwrapped
            // "References" heading it met on a page with no such binding.
            // This keys on the heading identity and a real accessibility
            // attribute, never on the host — the same markup drops
            // wikipedia_readability's and wikipedia_epub's backmatter
            // identically, because MediaWiki's Cite extension and section
            // renderer produce it identically on both.
            if let labelledBy = element.attributes["aria-labelledby"], isBackmatterHeading(labelledBy) {
                doomed.append(element)
                return
            }

            let signature = element.signature
            guard !signature.squeezed.isEmpty else { return }
            guard !positiveSignals.contains(where: { signature.contains($0) }) else { return }
            guard negativeSignals.contains(where: { signature.contains($0) }) else { return }

            // Only drop container-ish elements, and never something huge that a
            // site happens to have named "content-widget".
            let containers: Set<String> = ["div", "section", "ul", "ol", "span", "p", "header", "figure", "table"]
            if containers.contains(element.tag), element.textContent.count < 2000 {
                doomed.append(element)
            }
        }

        for element in doomed {
            element.parent?.removeChild(element)
        }
    }

    // MARK: - Scoring

    private final class Score {
        var value: Double = 0
        let element: HTMLElement
        init(element: HTMLElement) { self.element = element }
    }

    private static func bestCandidate(in body: HTMLElement) -> HTMLElement? {
        // A page with exactly one <article> almost always means it.
        let articles = body.elements(tagged: ["article"])
        if articles.count == 1, articles[0].textContent.count > 400 {
            return articles[0]
        }

        var scores: [ObjectIdentifier: Score] = [:]

        func score(for element: HTMLElement) -> Score {
            let key = ObjectIdentifier(element)
            if let existing = scores[key] { return existing }
            let created = Score(element: element)
            created.value = baseScore(for: element)
            scores[key] = created
            return created
        }

        let proseTags: Set<String> = ["p", "pre", "blockquote", "td", "h2", "h3", "li"]
        for element in body.elements(tagged: proseTags) {
            let text = element.textContent
            guard text.count >= 25 else { continue }

            // Length, punctuation, and paragraph count are the signal; a list item
            // counts for less because navigation is made of list items.
            var points = 1.0
            points += Double(text.filter { $0 == "," || $0 == "，" }.count)
            points += min(Double(text.count) / 100.0, 3.0)
            if element.tag == "li" { points *= 0.4 }
            if element.tag == "td" { points *= 0.5 }

            score(for: element).value += points

            // Credit flows up: parents hold the article, grandparents hold the page.
            for (depth, ancestor) in element.ancestors(limit: 3).enumerated() {
                guard ancestor.tag != "body", ancestor.tag != "html" else { break }
                let divisor = depth == 0 ? 1.0 : Double(depth) * 2.0
                score(for: ancestor).value += points / divisor
            }
        }

        var best: Score?
        for candidate in scores.values {
            // Link-heavy blocks are menus and roundups, not articles.
            let adjusted = candidate.value * (1.0 - candidate.element.linkDensity)
            candidate.value = adjusted
            if adjusted > (best?.value ?? 0) { best = candidate }
        }

        guard let winner = best else { return nil }

        // The richest score found anywhere in `element`'s subtree, not just on
        // `element` itself. A section's own aggregate score only reflects the
        // credit that reached it within `ancestors(limit: 3)` of each paragraph
        // — for content nested one table row, or one wrapper div, deeper than
        // that (a `<table><tbody><tr><td><p>` chapter, say), the section that
        // actually holds the prose scores near zero even though a descendant a
        // level or two down scored highly on its own. Asking "what's the best
        // candidate inside here" instead of "how much credit collected here"
        // makes sibling comparison immune to how many wrapper levels separate
        // the prose from the element being compared.
        func richestDescendantScore(_ element: HTMLElement) -> Double {
            var best = scores[ObjectIdentifier(element)]?.value ?? -Double.infinity
            for child in element.childElements {
                best = max(best, richestDescendantScore(child))
            }
            return best
        }

        // Climb toward whichever ancestor holds the winner's real siblings.
        // Three independent reasons to climb a level:
        //
        //  - `current` is pure scaffolding — its only child is the one we just
        //    climbed from (a table row around a single cell, a div wrapping a
        //    single div). There is no decision to make here: nothing else
        //    lives at this level, so climbing costs nothing and may be needed
        //    to reach the real fork further up.
        //  - the parent itself scores nearly as well as the winner — this
        //    recovers a wrapper holding intro paragraphs the winner excluded.
        //  - more than one of `current`'s children holds content within the
        //    same order of magnitude as the winner, somewhere in its own
        //    subtree — this recovers a document whose content lives in
        //    several coequal siblings (book chapters, doc sections, wiki
        //    `<h2>` sections) where no single sibling scores high enough
        //    alone to make the previous case fire, but the shared parent
        //    holds all of them. A stray intro paragraph or caption sitting
        //    next to the real content scores nowhere near the winner, so it
        //    doesn't count as a peer.
        var chosen = winner.element
        var chosenScore = winner.value
        var parent = chosen.parent
        while let current = parent, current.tag != "html" {
            // Climbing into a wrapper that is mostly links means swallowing the
            // site's navigation along with the article.
            guard current.linkDensity < 0.35 else { break }

            if current.childElements.count == 1 {
                chosen = current
                parent = current.parent
                continue
            }

            let parentScore = scores[ObjectIdentifier(current)]?.value ?? 0
            let recoversWrapper = parentScore > chosenScore * 0.85
                && current.textContent.count < chosen.textContent.count * 3

            let peerSiblings = current.childElements.filter { richestDescendantScore($0) >= chosenScore * 0.15 }
            let joinsSiblingCluster = peerSiblings.count >= 2

            guard recoversWrapper || joinsSiblingCluster else { break }
            chosen = current
            chosenScore = max(parentScore, peerSiblings.map(richestDescendantScore).max() ?? chosenScore)
            parent = current.parent
        }

        return chosen.textContent.count > 200 ? chosen : nil
    }

    private static func baseScore(for element: HTMLElement) -> Double {
        var value: Double
        switch element.tag {
        case "article", "main": value = 12
        case "div", "section": value = 5
        case "pre", "blockquote", "td": value = 3
        case "p": value = 2
        case "address", "ol", "ul", "dl", "dd", "dt", "li", "form": value = -3
        case "h1", "h2", "h3", "h4", "h5", "h6", "th": value = -5
        default: value = 0
        }

        let signature = element.signature
        if positiveSignals.contains(where: { signature.contains($0) }) { value += 25 }
        if negativeSignals.contains(where: { signature.contains($0) }) { value -= 25 }
        if element.attributes["itemprop"]?.contains("articleBody") == true { value += 30 }
        if element.attributes["role"] == "main" { value += 15 }
        return value
    }

    // MARK: - Post-processing

    /// Drops the leading duplicate title, collapses runs of dividers, and trims
    /// empty blocks the builder may have emitted.
    private static func polish(_ content: ArticleContent, title: String) -> ArticleContent {
        var blocks = content.blocks
        var trimming = true

        while trimming, let first = blocks.first {
            switch first {
            case .divider:
                blocks.removeFirst()
            case .paragraph(let text) where text.isEmpty:
                blocks.removeFirst()
            default:
                trimming = false
            }
        }

        // The page's own <h1> usually sits inside the article container, a block
        // or two below a date line. The reader already shows the title above the
        // body, so a repeat of it reads as a mistake.
        if let position = blocks.prefix(4).firstIndex(where: { block in
            if case .heading(_, let text) = block { return similar(text.plain, title) }
            return false
        }) {
            blocks.remove(at: position)
        }

        // A short opening line that is just a date and a read-time repeats the
        // header the reader already draws. Kept deliberately narrow: only the
        // first block, only if it is short, and only if it carries those marks.
        if case .paragraph(let opening)? = blocks.first, isBylineEcho(opening.plain) {
            blocks.removeFirst()
        }

        return ArticleContent(blocks: tidy(blocks))
    }

    private static func tidy(_ blocks: [ArticleBlock]) -> [ArticleBlock] {
        var out: [ArticleBlock] = []
        for block in blocks {
            if case .divider = block {
                if out.isEmpty { continue }
                if case .divider = out[out.count - 1] { continue }
            }
            out.append(block)
        }
        while case .divider? = out.last { out.removeLast() }
        return out
    }

    private static func isBylineEcho(_ text: String) -> Bool {
        let words = text.split(whereSeparator: { $0.isWhitespace })
        guard (1...12).contains(words.count) else { return false }

        let lowered = text.lowercased()
        if lowered.contains("min read") || lowered.contains("minute read") { return true }

        // A bare date line: a four-digit year and nothing much else.
        let hasYear = words.contains { $0.count == 4 && $0.allSatisfy(\.isNumber) }
        return hasYear && words.count <= 8
    }

    private static func similar(_ lhs: String, _ rhs: String) -> Bool {
        func key(_ value: String) -> String {
            value.lowercased().filter { $0.isLetter || $0.isNumber }
        }
        let left = key(lhs), right = key(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left == right || left.hasPrefix(right) || right.hasPrefix(left)
    }
}
