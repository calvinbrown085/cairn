import Foundation

/// Converts the winning DOM subtree into the flat block list the reader renders.
struct BlockBuilder {
    let baseURL: URL

    private var blocks: [ArticleBlock] = []
    private var seenImageSources: Set<String> = []

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    static func content(from element: HTMLElement, baseURL: URL) -> ArticleContent {
        var builder = BlockBuilder(baseURL: baseURL)
        return builder.build(from: element)
    }

    mutating func build(from root: HTMLElement) -> ArticleContent {
        blocks = []
        seenImageSources = []
        // `descend` only recognizes a block producer among an element's
        // *children* — it never asks whether the element handed to it is one.
        // That is right for the ordinary case (root is a wrapping <div> or
        // <article>, and `emit` falls through those to `descend` anyway), but
        // when `ArticleExtractor.bestCandidate` legitimately picks something
        // atomic as the winning candidate — most dangerously a <table>, whose
        // <tbody>/<tr>/<td> children are not block producers — going straight
        // to `descend` flattens every cell into one inline run and silently
        // drops every image and row boundary inside it. Routing the root
        // through `emit` first gives it the same dedicated handling any
        // identical element would get if found a level lower.
        emit(root)
        return ArticleContent(blocks: blocks)
    }

    // MARK: - Block level

    private static let headings: Set<String> = ["h1", "h2", "h3", "h4", "h5", "h6"]

    /// Tags that end the current paragraph and produce their own block.
    private static let blockProducers: Set<String> = [
        "h1", "h2", "h3", "h4", "h5", "h6", "p", "pre", "blockquote", "ul", "ol",
        "dl", "figure", "img", "picture", "hr", "table", "thead", "tbody", "tfoot",
        "div", "section", "article", "main", "header", "footer", "aside", "details",
        "li", "figcaption", "center",
    ]

    private mutating func descend(_ element: HTMLElement) {
        var pending: [InlineRun] = []

        func flushParagraph() {
            let text = RichText(runs: pending).normalized()
            pending = []
            appendParagraphs(text)
        }

        for node in element.children {
            switch node {
            case .text(let value):
                let text = value.collapsingInlineWhitespace()
                if !text.isEmpty { pending.append(InlineRun(text: text)) }

            case .element(let child):
                guard !HTMLTag.invisible.contains(child.tag) else { continue }

                if Self.blockProducers.contains(child.tag) {
                    flushParagraph()
                    emit(child)
                } else {
                    pending.append(contentsOf: inlineRuns(of: child, inheriting: InlineTraits()))
                }
            }
        }

        flushParagraph()
    }

    private mutating func emit(_ element: HTMLElement) {
        switch element.tag {
        case _ where Self.headings.contains(element.tag):
            // A heading that is entirely one outbound link belongs to a post
            // index, not to this article.
            guard !isIndexHeading(element) else { return }
            let level = Int(String(element.tag.dropFirst())) ?? 2
            let text = richText(of: element)
            if !text.isEmpty { blocks.append(.heading(level: min(max(level, 1), 6), text: text)) }

        case "p", "figcaption", "center":
            // A paragraph wrapping nothing but an image is really a figure.
            if let image = soleImage(in: element) {
                appendImage(image)
            } else {
                appendParagraphs(richText(of: element))
            }

        case "pre":
            let source = element.verbatimText.trimmingCharacters(in: .newlines)
            if !source.squeezed.isEmpty { blocks.append(.code(source)) }

        case "blockquote":
            for part in richText(of: element).splitOnBlankLines() {
                blocks.append(.quote(part))
            }

        case "ul", "ol":
            appendList(element, ordered: element.tag == "ol")

        case "dl":
            for child in element.childElements where child.tag == "dt" || child.tag == "dd" {
                let text = richText(of: child)
                guard !text.isEmpty else { continue }
                blocks.append(child.tag == "dt" ? .heading(level: 4, text: text) : .paragraph(text))
            }

        case "img":
            appendImage(element)

        case "picture":
            if let image = element.firstElement(tagged: "img") {
                appendImage(image)
            } else if let source = element.firstElement(tagged: "source") {
                appendImage(source)
            }

        case "figure":
            appendFigure(element)

        case "hr":
            blocks.append(.divider)

        case "table", "thead", "tbody", "tfoot":
            // `bestCandidate`'s climb up from a scored cell can rest on the
            // row-group instead of the enclosing `<table>` — the table itself
            // sometimes has a link density its `<tbody>` alone doesn't share
            // — so a "table" fixed up here needs to handle winning candidates
            // shaped like a bare `<tbody>` too. `appendTable` only ever asks
            // `directRows` for descendant `<tr>`s, which works identically
            // whichever of these wraps them.
            appendTable(element)

        case "li":
            // A stray <li> outside a list — keep the prose, drop the bullet.
            // But if the item's image sits in its own block wrapper (a
            // gallery thumbnail, say) rather than stitched inline into a run
            // of prose, pull it out instead of losing it to flattening.
            if let image = blockWrappedImage(in: element) {
                let caption = richText(of: element)
                appendImage(image, caption: caption.isEmpty ? nil : caption)
                return
            }
            let text = richText(of: element)
            if !text.isEmpty { blocks.append(.paragraph(text)) }

        default:
            descend(element)
        }
    }

    private mutating func appendParagraphs(_ text: RichText) {
        for part in text.splitOnBlankLines() where !part.isEmpty {
            blocks.append(.paragraph(part))
        }
    }

    /// True when the heading's text is essentially one link to somewhere else.
    /// Self-referencing `#anchor` links are how headings get permalinks, so those
    /// don't count.
    private func isIndexHeading(_ element: HTMLElement) -> Bool {
        let outbound = element.elements(tagged: ["a"]).filter { anchor in
            guard let href = anchor.attributes["href"]?.squeezed else { return false }
            return !href.isEmpty && !href.hasPrefix("#")
        }
        guard !outbound.isEmpty else { return false }

        let total = element.textContent.count
        guard total > 0 else { return true }
        let linked = outbound.reduce(0) { $0 + $1.textContent.count }
        return Double(linked) / Double(total) > 0.9
    }

    private mutating func appendList(_ element: HTMLElement, ordered: Bool) {
        var items: [RichText] = []

        func flushItems() {
            guard !items.isEmpty else { return }
            blocks.append(.list(ordered: ordered, items: items))
            items = []
        }

        for child in element.childElements where child.tag == "li" {
            // A gallery item — an image in its own wrapper div, a caption in
            // another — needs pulling out as a figure, or the image is
            // silently dropped by the plain-text flattening below. An item
            // with an inline image stitched into running prose (a MathJax
            // fallback glyph, say) has no such wrapper and stays plain text.
            if let image = blockWrappedImage(in: child) {
                flushItems()
                let caption = richText(of: child)
                appendImage(image, caption: caption.isEmpty ? nil : caption)
                continue
            }
            // Nested lists get flattened into their parent item's text.
            let text = richText(of: child)
            if !text.isEmpty { items.append(text) }
        }
        flushItems()
    }

    /// An image sitting inside a block-level wrapper of a list item (its own
    /// `<div>`, `<figure>`, ...) the way a gallery thumbnail does — as opposed
    /// to an image stitched inline into a run of prose, which has no such
    /// wrapper. Reuses `cellHoldsBlockContent`'s block/inline test, the same
    /// signal a table cell is judged by. Checked against the same source
    /// rules any other image needs, so a decorative icon too small or too
    /// generic to count doesn't hijack the item.
    private func blockWrappedImage(in listItem: HTMLElement) -> HTMLElement? {
        guard cellHoldsBlockContent(listItem),
              let image = listItem.firstElement(tagged: "img"),
              imageSource(from: image) != nil
        else { return nil }
        return image
    }

    private mutating func appendFigure(_ element: HTMLElement) {
        let caption = element.firstElement(tagged: "figcaption").map { richText(of: $0) }
        guard let img = element.firstElement(tagged: "img") ?? element.firstElement(tagged: "source") else {
            // A figure with no image is usually a pull quote or a code sample.
            descend(element)
            return
        }
        appendImage(img, caption: caption?.isEmpty == true ? nil : caption)
    }

    /// `blockProducers` minus the tags that are already atomic blocks in
    /// their own right (an image, a divider, a stray list item...). Those
    /// never hide a second paragraph behind them, so their presence in a cell
    /// says nothing about whether the cell is prose. The rest — `<p>`,
    /// `<div>`, headings, lists, nested tables — exist specifically to
    /// segment content into more than one block, and collapsing them to
    /// inline text is exactly the flattening bug this guards against.
    private static let cellBlockContainers: Set<String> =
        blockProducers.subtracting(["img", "picture", "hr", "li", "figcaption", "center"])

    /// True when a cell wraps genuine block content (paragraphs, headings, a
    /// nested table, ...) rather than a bare label or value. This is what
    /// tells a layout table — cells used as columns to hold prose — apart
    /// from a data table, where a cell's content is the data itself.
    private func cellHoldsBlockContent(_ cell: HTMLElement) -> Bool {
        !cell.elements(tagged: Self.cellBlockContainers).isEmpty
    }

    /// The `<tr>` elements that belong to this table directly, not to some
    /// other table nested inside one of its cells. A plain descendant search
    /// would pull a nested table's rows into the outer table's count and
    /// throw off both the layout/data decision and the row-count check below.
    private func directRows(of table: HTMLElement) -> [HTMLElement] {
        var rows: [HTMLElement] = []
        func walk(_ element: HTMLElement) {
            for child in element.childElements {
                if child.tag == "tr" {
                    rows.append(child)
                } else if child.tag != "table" {
                    walk(child)
                }
            }
        }
        walk(table)
        return rows
    }

    private mutating func appendTable(_ element: HTMLElement) {
        let rows = directRows(of: element)
        guard !rows.isEmpty else { descend(element); return }

        let cells = rows.flatMap { row in row.childElements.filter { $0.tag == "td" || $0.tag == "th" } }

        // A cell that itself wraps block content is a layout cell, not
        // tabular data — regardless of how many rows or columns surround it.
        // Recurse into each cell at block granularity so the paragraphs (or
        // headings, or lists) inside come out as their own blocks instead of
        // being glued into one flattened run of text. This is what lets a
        // single-row 2000s layout table, a multi-row one, and a table
        // nested inside another all fall out of the same rule.
        if cells.contains(where: cellHoldsBlockContent) {
            for cell in cells { descend(cell) }
            return
        }

        // No cell holds block content: this reads as a genuine data table
        // (or a layout table with nothing worth extracting). A single row
        // falls back to the old inline flattening — some legacy pages keep
        // an image and `<br>`-separated prose in one cell with no block tags
        // at all, and that content still deserves a chance to become prose.
        guard rows.count > 1 else { descend(element); return }

        var lines: [RichText] = []
        func flushLines() {
            guard !lines.isEmpty else { return }
            blocks.append(.list(ordered: false, items: lines))
            lines = []
        }

        for row in rows {
            let rowCells = row.childElements.filter { $0.tag == "td" || $0.tag == "th" }
            let text = rowCells.map { $0.textContent.squeezed }.filter { !$0.isEmpty }.joined(separator: "  ·  ")

            // A data row that also carries an image — a flag, a headshot, a
            // thumbnail column — gets the same rescue `appendList` already
            // gives a gallery `<li>`: pull the image out as its own block
            // with the row's text riding along as a caption, instead of
            // losing every photo to the row's plain-text flattening below.
            if let image = rowCells.lazy.compactMap({ $0.firstElement(tagged: "img") }).first(where: { imageSource(from: $0) != nil }) {
                flushLines()
                appendImage(image, caption: text.isEmpty ? nil : RichText(text))
                continue
            }

            if !text.isEmpty { lines.append(RichText(text)) }
        }
        flushLines()
    }

    private mutating func appendImage(_ element: HTMLElement, caption: RichText? = nil) {
        guard let source = imageSource(from: element) else { return }
        guard !seenImageSources.contains(source) else { return }
        seenImageSources.insert(source)

        let alt = element.attributes["alt"]?.squeezed
        blocks.append(.image(ArticleImage(
            source: source,
            alt: (alt?.isEmpty == true) ? nil : alt,
            caption: caption,
            assetID: nil,
            width: element.attributes["width"].flatMap(Double.init),
            height: element.attributes["height"].flatMap(Double.init)
        )))
    }

    private func soleImage(in element: HTMLElement) -> HTMLElement? {
        guard element.textContent.squeezed.isEmpty else { return nil }
        let images = element.elements(tagged: ["img"])
        return images.count == 1 ? images[0] : nil
    }

    // MARK: - Image sources

    /// Lazy-loading sites hide the real URL in a data attribute and leave `src`
    /// pointing at a placeholder, so the data attributes are checked first.
    private static let lazyAttributes = [
        "data-src", "data-original", "data-lazy-src", "data-actual-src",
        "data-hi-res-src", "data-full-src", "data-image", "data-url",
    ]

    private func imageSource(from element: HTMLElement) -> String? {
        var raw: String?

        for attribute in Self.lazyAttributes {
            if let value = element.attributes[attribute]?.squeezed, !value.isEmpty, !isPlaceholder(value) {
                raw = value
                break
            }
        }

        if raw == nil, let srcset = element.attributes["srcset"] ?? element.attributes["data-srcset"] {
            raw = largestCandidate(inSrcset: srcset)
        }

        if raw == nil, let value = element.attributes["src"]?.squeezed, !value.isEmpty, !isPlaceholder(value) {
            raw = value
        }

        guard let candidate = raw, !isPlaceholder(candidate) else { return nil }
        guard let resolved = URL(string: candidate, relativeTo: baseURL)?.absoluteURL else { return nil }
        guard ["http", "https"].contains(resolved.scheme ?? "") else { return nil }

        // 1×1 tracking pixels and spacer gifs declare their size in the markup.
        if let width = element.attributes["width"].flatMap(Double.init), width > 0, width < 24 { return nil }
        if let height = element.attributes["height"].flatMap(Double.init), height > 0, height < 24 { return nil }

        return resolved.absoluteString
    }

    private func isPlaceholder(_ value: String) -> Bool {
        if value.hasPrefix("data:") { return true }
        let lowered = value.lowercased()
        return ["blank.gif", "spacer.gif", "placeholder", "lazy-load", "1x1.", "pixel.gif", "transparent."]
            .contains { lowered.contains($0) }
    }

    /// Picks the widest entry from a `srcset` so the archive keeps the best copy.
    private func largestCandidate(inSrcset srcset: String) -> String? {
        var best: (url: String, weight: Double)?

        for entry in srcset.split(separator: ",") {
            let parts = entry.squeezed.split(whereSeparator: { $0.isWhitespace })
            guard let url = parts.first.map(String.init), !isPlaceholder(url) else { continue }

            var weight = 1.0
            if parts.count > 1 {
                let descriptor = parts[1]
                if descriptor.hasSuffix("w") { weight = Double(descriptor.dropLast()) ?? 1 }
                else if descriptor.hasSuffix("x") { weight = (Double(descriptor.dropLast()) ?? 1) * 1000 }
            }
            if weight > (best?.weight ?? 0) { best = (url, weight) }
        }

        return best?.url
    }

    // MARK: - Inline level

    private static let boldTags: Set<String> = ["b", "strong"]
    private static let italicTags: Set<String> = ["i", "em", "cite", "dfn", "var", "address"]
    private static let codeTags: Set<String> = ["code", "kbd", "samp", "tt"]

    private func richText(of element: HTMLElement) -> RichText {
        RichText(runs: inlineRuns(of: element, inheriting: InlineTraits())).normalized()
    }

    private func inlineRuns(of element: HTMLElement, inheriting inherited: InlineTraits) -> [InlineRun] {
        var traits = inherited
        if Self.boldTags.contains(element.tag) { traits.isBold = true }
        if Self.italicTags.contains(element.tag) { traits.isItalic = true }
        if Self.codeTags.contains(element.tag) { traits.isCode = true }

        if element.tag == "a", let href = element.attributes["href"]?.squeezed, !href.isEmpty,
           !href.hasPrefix("#"), !href.hasPrefix("javascript:") {
            traits.link = URL(string: href, relativeTo: baseURL)?.absoluteString ?? href
        }

        if element.tag == "br" {
            return [InlineRun(text: "\n", isBold: traits.isBold, isItalic: traits.isItalic, isCode: traits.isCode, link: traits.link)]
        }

        // Footnote markers read as stray digits once the styling is gone. A
        // reference marker links out or is bracketed; a bare superscript is
        // usually maths, and "x²" would be wrong without its exponent.
        if element.tag == "sup" {
            let marker = element.textContent.squeezed
            let isReference = element.firstElement(tagged: "a") != nil
                || element.signature.contains("reference")
                || element.signature.contains("footnote")
                || marker.hasPrefix("[")
            if isReference, marker.count <= 10 { return [] }
        }

        if element.tag == "sub", element.textContent.count <= 2, element.firstElement(tagged: "a") != nil {
            return []
        }

        var runs: [InlineRun] = []
        for node in element.children {
            switch node {
            case .text(let value):
                let text = value.collapsingInlineWhitespace()
                guard !text.isEmpty else { continue }
                runs.append(InlineRun(
                    text: text,
                    isBold: traits.isBold,
                    isItalic: traits.isItalic,
                    isCode: traits.isCode,
                    link: traits.link
                ))

            case .element(let child):
                guard !HTMLTag.invisible.contains(child.tag) else { continue }
                guard child.tag != "img" else { continue }

                // A block child inside inline context still needs separating.
                let needsBreak = HTMLTag.blockLevel.contains(child.tag) && child.tag != "br"
                if needsBreak, let last = runs.last, !last.text.hasSuffix(" "), !last.text.hasSuffix("\n") {
                    runs.append(InlineRun(text: " "))
                }
                runs.append(contentsOf: inlineRuns(of: child, inheriting: traits))
            }
        }
        return runs
    }
}

extension HTMLElement {
    /// Text with original whitespace preserved — for `<pre>`, where indentation
    /// and line breaks carry meaning.
    var verbatimText: String {
        var out = ""
        collectVerbatim(into: &out)
        return out
    }

    private func collectVerbatim(into out: inout String) {
        for child in children {
            switch child {
            case .text(let value):
                out += value
            case .element(let element):
                if HTMLTag.invisible.contains(element.tag) { continue }
                if element.tag == "br" { out += "\n"; continue }
                let isLine = element.tag == "div" || element.tag == "p"
                if isLine, !out.isEmpty, !out.hasSuffix("\n") { out += "\n" }
                element.collectVerbatim(into: &out)
                if isLine, !out.hasSuffix("\n") { out += "\n" }
            }
        }
    }
}
