import Foundation

/// A run of text sharing one set of inline traits. Paragraphs are stored as runs
/// rather than HTML so the reader can restyle freely and highlights can anchor to
/// plain character offsets.
public struct InlineRun: Codable, Hashable {
    public var text: String
    public var isBold: Bool = false
    public var isItalic: Bool = false
    public var isCode: Bool = false
    public var link: String?

    enum CodingKeys: String, CodingKey {
        case text = "t", isBold = "b", isItalic = "i", isCode = "c", link = "l"
    }

    public init(text: String, isBold: Bool = false, isItalic: Bool = false, isCode: Bool = false, link: String? = nil) {
        self.text = text
        self.isBold = isBold
        self.isItalic = isItalic
        self.isCode = isCode
        self.link = link
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        isBold = try container.decodeIfPresent(Bool.self, forKey: .isBold) ?? false
        isItalic = try container.decodeIfPresent(Bool.self, forKey: .isItalic) ?? false
        isCode = try container.decodeIfPresent(Bool.self, forKey: .isCode) ?? false
        link = try container.decodeIfPresent(String.self, forKey: .link)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        if isBold { try container.encode(true, forKey: .isBold) }
        if isItalic { try container.encode(true, forKey: .isItalic) }
        if isCode { try container.encode(true, forKey: .isCode) }
        try container.encodeIfPresent(link, forKey: .link)
    }

    public var traits: InlineTraits {
        InlineTraits(isBold: isBold, isItalic: isItalic, isCode: isCode, link: link)
    }
}

public struct InlineTraits: Hashable {
    public var isBold = false
    public var isItalic = false
    public var isCode = false
    public var link: String?

    public var isPlain: Bool { !isBold && !isItalic && !isCode && link == nil }
}

public struct RichText: Codable, Hashable {
    public var runs: [InlineRun]

    public init(runs: [InlineRun] = []) { self.runs = runs }
    public init(_ plain: String) { self.runs = plain.isEmpty ? [] : [InlineRun(text: plain)] }

    public var plain: String { runs.map(\.text).joined() }
    public var isEmpty: Bool { plain.squeezed.isEmpty }

    /// Merges adjacent runs with identical traits and trims the outer edges.
    public func normalized() -> RichText {
        var merged: [InlineRun] = []
        for var run in runs where !run.text.isEmpty {
            // A <br> is followed by the source's own indentation, which would
            // otherwise open every line after a break with a space.
            run.text = run.text.replacingOccurrences(of: "\n ", with: "\n")

            if let last = merged.last, last.text.hasSuffix("\n"), run.text.hasPrefix(" ") {
                run.text.removeFirst()
                if run.text.isEmpty { continue }
            }

            // Both sides of a seam can carry a space; keep exactly one.
            if let last = merged.last, last.text.hasSuffix(" "), run.text.hasPrefix(" ") {
                run.text.removeFirst()
                if run.text.isEmpty { continue }
            }
            if var last = merged.last, last.traits == run.traits {
                last.text += run.text
                merged[merged.count - 1] = last
            } else {
                merged.append(run)
            }
        }
        if var first = merged.first {
            first.text = String(first.text.drop(while: { $0 == " " || $0 == "\n" }))
            if first.text.isEmpty { merged.removeFirst() } else { merged[0] = first }
        }
        if var last = merged.last {
            while let final = last.text.last, final == " " || final == "\n" { last.text.removeLast() }
            if last.text.isEmpty { merged.removeLast() } else { merged[merged.count - 1] = last }
        }
        return RichText(runs: merged)
    }
}

public extension RichText {
    /// Splits at blank lines. Sites that predate CSS layout separate paragraphs
    /// with `<br><br>` instead of `<p>`, which would otherwise land the whole
    /// essay in a single block.
    public func splitOnBlankLines() -> [RichText] {
        guard plain.contains("\n\n") else { return [self] }

        var groups: [[InlineRun]] = [[]]
        for run in runs {
            let segments = run.text.components(separatedBy: "\n\n")
            for (offset, segment) in segments.enumerated() {
                if offset > 0 { groups.append([]) }
                guard !segment.isEmpty else { continue }
                var piece = run
                piece.text = segment
                groups[groups.count - 1].append(piece)
            }
        }

        return groups.map { RichText(runs: $0).normalized() }.filter { !$0.isEmpty }
    }
}

public struct ArticleImage: Codable, Hashable {
    public var source: String
    public var alt: String?
    public var caption: RichText?
    /// Set once the bytes are downloaded into a `StoredImage`.
    public var assetID: UUID?
    public var width: Double?
    public var height: Double?

    public var aspectRatio: Double? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return width / height
    }
}

public enum ArticleBlock: Codable, Hashable {
    case heading(level: Int, text: RichText)
    case paragraph(RichText)
    case quote(RichText)
    case code(String)
    case list(ordered: Bool, items: [RichText])
    case image(ArticleImage)
    case divider

    /// The text a highlight can anchor into. Blocks with no anchorable prose
    /// return nil and are skipped by the highlighting UI.
    public var selectableText: String? {
        switch self {
        case .heading(_, let text), .paragraph(let text), .quote(let text):
            return text.plain
        case .code(let source):
            return source
        case .list, .image, .divider:
            return nil
        }
    }

    public var plainText: String {
        switch self {
        case .heading(_, let text), .paragraph(let text), .quote(let text):
            return text.plain
        case .code(let source):
            return source
        case .list(_, let items):
            return items.map(\.plain).joined(separator: "\n")
        case .image(let image):
            return image.caption?.plain ?? image.alt ?? ""
        case .divider:
            return ""
        }
    }
}

/// Blocks are addressed by position, so the reader pairs each one with its index.
public struct IndexedBlock: Identifiable, Hashable {
    public let id: Int
    public let block: ArticleBlock
}

public struct ArticleContent: Codable, Hashable {
    public var blocks: [ArticleBlock] = []

    public var plainText: String {
        blocks.map(\.plainText).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    public var wordCount: Int {
        plainText.split(whereSeparator: { $0.isWhitespace }).count
    }

    public var indexed: [IndexedBlock] {
        blocks.enumerated().map { IndexedBlock(id: $0.offset, block: $0.element) }
    }

    public var imageSources: [(index: Int, image: ArticleImage)] {
        blocks.enumerated().compactMap { offset, block in
            if case .image(let image) = block { return (offset, image) }
            return nil
        }
    }

    public func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    public static func decoded(from data: Data?) -> ArticleContent {
        guard let data, let content = try? JSONDecoder().decode(ArticleContent.self, from: data) else {
            return ArticleContent()
        }
        return content
    }
}
