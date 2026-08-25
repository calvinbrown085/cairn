import Foundation

/// A minimal, forgiving HTML tree. Real-world blog HTML is rarely well-formed,
/// so the parser prefers "produce something reasonable" over "reject invalid input".
final class HTMLElement {
    let tag: String
    var attributes: [String: String]
    private(set) var children: [HTMLNode] = []
    weak var parent: HTMLElement?

    init(tag: String, attributes: [String: String] = [:]) {
        self.tag = tag
        self.attributes = attributes
    }

    func append(_ node: HTMLNode) {
        if case .element(let element) = node { element.parent = self }
        children.append(node)
    }

    func removeChild(_ element: HTMLElement) {
        children.removeAll { node in
            if case .element(let candidate) = node { return candidate === element }
            return false
        }
    }

    var id: String { attributes["id"] ?? "" }
    var className: String { attributes["class"] ?? "" }

    /// `class` and `id` concatenated — what the readability heuristics match against.
    var signature: String { "\(className) \(id)".lowercased() }

    var childElements: [HTMLElement] {
        children.compactMap { if case .element(let e) = $0 { return e } else { return nil } }
    }

    /// Depth-first walk including the receiver.
    func walk(_ visit: (HTMLElement) -> Void) {
        visit(self)
        for child in childElements { child.walk(visit) }
    }

    func elements(tagged tags: Set<String>) -> [HTMLElement] {
        var found: [HTMLElement] = []
        walk { if tags.contains($0.tag) { found.append($0) } }
        return found
    }

    func firstElement(tagged tag: String) -> HTMLElement? {
        var found: HTMLElement?
        walk { if found == nil && $0.tag == tag { found = $0 } }
        return found
    }

    /// Visible text with whitespace collapsed.
    var textContent: String {
        var out = ""
        appendText(to: &out)
        return out.collapsingWhitespace()
    }

    private func appendText(to out: inout String) {
        for child in children {
            switch child {
            case .text(let value): out += value
            case .element(let element):
                if HTMLTag.invisible.contains(element.tag) { continue }
                if HTMLTag.blockLevel.contains(element.tag) { out += "\n" }
                element.appendText(to: &out)
                if HTMLTag.blockLevel.contains(element.tag) { out += "\n" }
            }
        }
    }

    /// Fraction of the element's text that sits inside links. High values mean
    /// navigation or a link roundup rather than prose.
    var linkDensity: Double {
        let total = textContent.count
        guard total > 0 else { return 0 }
        let linked = elements(tagged: ["a"]).reduce(0) { $0 + $1.textContent.count }
        return Double(linked) / Double(total)
    }

    func ancestors(limit: Int) -> [HTMLElement] {
        var result: [HTMLElement] = []
        var node = parent
        while let current = node, result.count < limit {
            result.append(current)
            node = current.parent
        }
        return result
    }
}

enum HTMLNode {
    case element(HTMLElement)
    case text(String)
}

enum HTMLTag {
    /// Elements that never have children and never need a closing tag.
    static let void: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "param", "source", "track", "wbr",
    ]

    /// Elements whose contents are raw text, not markup.
    static let rawText: Set<String> = ["script", "style", "textarea", "title"]

    static let blockLevel: Set<String> = [
        "address", "article", "aside", "blockquote", "details", "dialog", "dd", "div",
        "dl", "dt", "fieldset", "figcaption", "figure", "footer", "form", "h1", "h2",
        "h3", "h4", "h5", "h6", "header", "hgroup", "hr", "li", "main", "nav", "ol",
        "p", "pre", "section", "table", "tr", "td", "th", "ul", "br",
    ]

    /// Contributes no readable text.
    static let invisible: Set<String> = ["script", "style", "noscript", "svg", "template", "head"]

    /// Tags that implicitly close an open tag of the same kind.
    static let selfClosingPeers: [String: Set<String>] = [
        "p": ["p"],
        "li": ["li"],
        "dt": ["dt", "dd"],
        "dd": ["dt", "dd"],
        "tr": ["tr", "td", "th"],
        "td": ["td", "th"],
        "th": ["td", "th"],
        "option": ["option"],
        "thead": ["thead", "tbody", "tfoot"],
        "tbody": ["thead", "tbody", "tfoot"],
        "tfoot": ["thead", "tbody", "tfoot"],
    ]
}

/// Hand-rolled tokenizer. Handles the parts of the spec that matter for article
/// extraction: comments, doctypes, raw-text elements, void elements, unquoted
/// attributes, and implicit tag closing.
struct HTMLParser {
    private let scalars: [Character]
    private var index: Int = 0

    private init(html: String) {
        self.scalars = Array(html)
    }

    static func parse(_ html: String) -> HTMLElement {
        var parser = HTMLParser(html: html)
        return parser.run()
    }

    private mutating func run() -> HTMLElement {
        let root = HTMLElement(tag: "#document")
        var stack: [HTMLElement] = [root]

        while index < scalars.count {
            if scalars[index] == "<" {
                if consumeComment() { continue }
                if consumeDoctype() { continue }

                if peek(1) == "/" {
                    if let name = readEndTag() {
                        closeTag(named: name, stack: &stack)
                    }
                    continue
                }

                if let token = readStartTag() {
                    let current = stack.last ?? root

                    // An implicitly-closing tag (a second <p>, a new <li>) pops its peer.
                    if let peers = HTMLTag.selfClosingPeers[token.name],
                       peers.contains(current.tag) {
                        stack.removeLast()
                    }

                    let element = HTMLElement(tag: token.name, attributes: token.attributes)
                    (stack.last ?? root).append(.element(element))

                    if HTMLTag.rawText.contains(token.name) {
                        let raw = readRawText(until: token.name)
                        if !raw.isEmpty { element.append(.text(raw)) }
                    } else if !token.isSelfClosing && !HTMLTag.void.contains(token.name) {
                        stack.append(element)
                    }
                    continue
                }

                // A stray "<" that isn't markup — treat it as text.
                (stack.last ?? root).append(.text("<"))
                index += 1
                continue
            }

            let text = readText()
            if !text.isEmpty {
                (stack.last ?? root).append(.text(HTMLEntities.decode(text)))
            }
        }

        return root
    }

    /// Pops the stack to the nearest matching open element. Unmatched end tags
    /// (very common in the wild) are ignored rather than corrupting the tree.
    private func closeTag(named name: String, stack: inout [HTMLElement]) {
        guard let position = stack.lastIndex(where: { $0.tag == name }), position > 0 else { return }
        stack.removeSubrange(position...)
    }

    // MARK: - Scanning

    private func peek(_ offset: Int) -> Character? {
        let target = index + offset
        return target < scalars.count ? scalars[target] : nil
    }

    private func matches(_ literal: String, at position: Int) -> Bool {
        let characters = Array(literal)
        guard position + characters.count <= scalars.count else { return false }
        for (offset, character) in characters.enumerated() {
            if Character(scalars[position + offset].lowercased()) != character { return false }
        }
        return true
    }

    private mutating func consumeComment() -> Bool {
        guard matches("<!--", at: index) else { return false }
        index += 4
        while index < scalars.count {
            if matches("-->", at: index) { index += 3; return true }
            index += 1
        }
        return true
    }

    private mutating func consumeDoctype() -> Bool {
        guard matches("<!", at: index) || matches("<?", at: index) else { return false }
        while index < scalars.count && scalars[index] != ">" { index += 1 }
        if index < scalars.count { index += 1 }
        return true
    }

    private mutating func readEndTag() -> String? {
        let start = index
        index += 2 // "</"
        var name = ""
        while index < scalars.count, scalars[index].isLetter || scalars[index].isNumber {
            name.append(scalars[index])
            index += 1
        }
        while index < scalars.count && scalars[index] != ">" { index += 1 }
        if index < scalars.count { index += 1 }
        guard !name.isEmpty else { index = start + 1; return nil }
        return name.lowercased()
    }

    private struct StartTag {
        var name: String
        var attributes: [String: String]
        var isSelfClosing: Bool
    }

    private mutating func readStartTag() -> StartTag? {
        let start = index
        index += 1 // "<"

        var name = ""
        while index < scalars.count, scalars[index].isLetter || scalars[index].isNumber {
            name.append(scalars[index])
            index += 1
        }
        guard !name.isEmpty else { index = start; return nil }

        var attributes: [String: String] = [:]
        var isSelfClosing = false

        while index < scalars.count {
            skipWhitespace()
            guard index < scalars.count else { break }

            if scalars[index] == ">" { index += 1; break }
            if scalars[index] == "/" {
                isSelfClosing = true
                index += 1
                continue
            }

            guard let attribute = readAttribute() else {
                index += 1
                continue
            }
            if attributes[attribute.0] == nil { attributes[attribute.0] = attribute.1 }
        }

        return StartTag(name: name.lowercased(), attributes: attributes, isSelfClosing: isSelfClosing)
    }

    private mutating func readAttribute() -> (String, String)? {
        var name = ""
        while index < scalars.count {
            let character = scalars[index]
            if character.isWhitespace || character == "=" || character == ">" || character == "/" { break }
            name.append(character)
            index += 1
        }
        guard !name.isEmpty else { return nil }

        skipWhitespace()
        guard index < scalars.count, scalars[index] == "=" else {
            return (name.lowercased(), "")
        }
        index += 1
        skipWhitespace()
        guard index < scalars.count else { return (name.lowercased(), "") }

        var value = ""
        let quote = scalars[index]
        if quote == "\"" || quote == "'" {
            index += 1
            while index < scalars.count, scalars[index] != quote {
                value.append(scalars[index])
                index += 1
            }
            if index < scalars.count { index += 1 }
        } else {
            while index < scalars.count {
                let character = scalars[index]
                if character.isWhitespace || character == ">" { break }
                value.append(character)
                index += 1
            }
        }

        return (name.lowercased(), HTMLEntities.decode(value))
    }

    private mutating func readRawText(until tag: String) -> String {
        var value = ""
        while index < scalars.count {
            if scalars[index] == "<", peek(1) == "/", matches("</\(tag)", at: index) {
                _ = readEndTag()
                return value
            }
            value.append(scalars[index])
            index += 1
        }
        return value
    }

    private mutating func readText() -> String {
        var value = ""
        while index < scalars.count, scalars[index] != "<" {
            value.append(scalars[index])
            index += 1
        }
        return value
    }

    private mutating func skipWhitespace() {
        while index < scalars.count, scalars[index].isWhitespace { index += 1 }
    }
}

extension String {
    func collapsingWhitespace() -> String {
        var out = ""
        var pendingSpace = false
        var pendingNewlines = 0

        for character in self {
            if character == "\n" || character == "\r" {
                pendingNewlines += 1
                continue
            }
            if character.isWhitespace {
                pendingSpace = true
                continue
            }
            if !out.isEmpty {
                if pendingNewlines > 0 {
                    out.append(pendingNewlines > 1 ? "\n" : " ")
                } else if pendingSpace {
                    out.append(" ")
                }
            }
            pendingSpace = false
            pendingNewlines = 0
            out.append(character)
        }
        return out
    }

}

extension String {
    /// Collapses interior whitespace runs to a single space while preserving one
    /// leading and one trailing space. Inline text nodes depend on those edges:
    /// the space in `on <em>your</em> computer` lives at the end of one node and
    /// the start of the next, and dropping it welds the words together.
    func collapsingInlineWhitespace() -> String {
        guard let first, let last else { return self }
        let hasLeading = first.isWhitespace
        let hasTrailing = last.isWhitespace

        var body = ""
        var pendingSpace = false
        for character in self {
            if character.isWhitespace {
                pendingSpace = !body.isEmpty
                continue
            }
            if pendingSpace { body.append(" "); pendingSpace = false }
            body.append(character)
        }

        if body.isEmpty { return hasLeading ? " " : "" }
        return (hasLeading ? " " : "") + body + (hasTrailing ? " " : "")
    }
}

extension StringProtocol {
    /// Trimmed of surrounding whitespace and newlines.
    var squeezed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
