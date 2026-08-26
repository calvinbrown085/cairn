import Foundation

/// Pulls the headline, byline, and dates out of a page's metadata, preferring
/// structured sources (Open Graph, JSON-LD) over guesses at the markup.
struct ArticleMetadata {
    var title: String
    var author: String?
    var siteName: String?
    var description: String?
    var publishedAt: Date?
    /// Seconds from GMT that the page's own date carried. A publication date
    /// means "the day it went up where it was written", so rendering it in the
    /// reader's zone can slide it to the wrong day.
    var publishedOffset: Int?
    var leadImage: String?

    init(document: HTMLElement, url: URL) {
        let meta = ArticleMetadata.metaValues(in: document)
        let linkedData = ArticleMetadata.jsonLD(in: document)

        siteName = meta["og:site_name"] ?? meta["application-name"] ?? url.host()

        title = ArticleMetadata.firstNonEmpty([
            meta["og:title"],
            meta["twitter:title"],
            linkedData?["headline"] as? String,
            linkedData?["name"] as? String,
            ArticleMetadata.headingTitle(in: document),
            document.firstElement(tagged: "title")?.textContent,
            ArticleMetadata.styledHeading(in: document),
        ]) ?? url.host() ?? "Untitled"

        // Page titles usually carry a "— Site Name" tail that the headline doesn't.
        title = ArticleMetadata.trimmingSiteSuffix(
            from: title, siteName: siteName, url: url,
            extraNames: ArticleMetadata.bannerNames(in: document)
        )
        title = title.squeezed

        author = ArticleMetadata.firstNonEmpty([
            meta["author"],
            meta["article:author"],
            meta["og:article:author"],
            meta["twitter:creator"],
            ArticleMetadata.linkedDataAuthor(linkedData),
            ArticleMetadata.bylineFromMarkup(document),
        ])
        // twitter:creator arrives as "@handle"; the "@" reads as noise in a byline.
        if let value = author, value.hasPrefix("@") { author = String(value.dropFirst()) }
        if let value = author, value.count > 80 || value.isEmpty { author = nil }

        description = ArticleMetadata.firstNonEmpty([
            meta["og:description"],
            meta["description"],
            meta["twitter:description"],
            linkedData?["description"] as? String,
        ])

        let publishedRaw = ArticleMetadata.firstNonEmpty([
            meta["article:published_time"],
            meta["og:article:published_time"],
            linkedData?["datePublished"] as? String,
            meta["date"],
            meta["dc.date"],
            meta["pubdate"],
            document.elements(tagged: ["time"]).compactMap { $0.attributes["datetime"] }.first,
        ])
        publishedAt = publishedRaw.flatMap(ArticleMetadata.parseDate)
        publishedOffset = publishedRaw.flatMap(ArticleMetadata.parseOffset)

        leadImage = ArticleMetadata.firstNonEmpty([
            meta["og:image"],
            meta["og:image:url"],
            meta["twitter:image"],
            meta["twitter:image:src"],
        ]).flatMap { URL(string: $0, relativeTo: url)?.absoluteString }
    }

    // MARK: - Sources

    private static func metaValues(in document: HTMLElement) -> [String: String] {
        var values: [String: String] = [:]
        for element in document.elements(tagged: ["meta"]) {
            let key = element.attributes["property"] ?? element.attributes["name"] ?? element.attributes["itemprop"]
            guard let key, let content = element.attributes["content"], !content.squeezed.isEmpty else { continue }
            let normalized = key.lowercased()
            if values[normalized] == nil { values[normalized] = content.squeezed }
        }
        return values
    }

    /// Returns the first JSON-LD object that looks like an article.
    private static func jsonLD(in document: HTMLElement) -> [String: Any]? {
        for script in document.elements(tagged: ["script"]) {
            guard script.attributes["type"]?.lowercased().contains("ld+json") == true else { continue }
            guard case .text(let raw)? = script.children.first else { continue }
            guard let data = raw.data(using: .utf8) else { continue }
            guard let parsed = try? JSONSerialization.jsonObject(with: data) else { continue }

            for object in flatten(parsed) {
                let type = (object["@type"] as? String) ?? (object["@type"] as? [String])?.first ?? ""
                if type.contains("Article") || type.contains("BlogPosting") || type.contains("NewsArticle") {
                    return object
                }
            }
        }
        return nil
    }

    /// JSON-LD arrives as an object, an array, or an @graph wrapper.
    private static func flatten(_ value: Any) -> [[String: Any]] {
        if let object = value as? [String: Any] {
            if let graph = object["@graph"] { return flatten(graph) }
            return [object]
        }
        if let array = value as? [Any] { return array.flatMap(flatten) }
        return []
    }

    private static func linkedDataAuthor(_ linkedData: [String: Any]?) -> String? {
        guard let author = linkedData?["author"] else { return nil }
        if let name = author as? String { return name }
        if let object = author as? [String: Any] { return object["name"] as? String }
        if let array = author as? [Any] {
            let names = array.compactMap { entry -> String? in
                if let name = entry as? String { return name }
                return (entry as? [String: Any])?["name"] as? String
            }
            return names.isEmpty ? nil : names.joined(separator: ", ")
        }
        return nil
    }

    private static func bylineFromMarkup(_ document: HTMLElement) -> String? {
        var candidates: [String] = []
        document.walk { element in
            let signature = element.signature
            let isByline = element.attributes["rel"] == "author"
                || element.attributes["itemprop"] == "author"
                || signature.contains("byline")
                || signature.contains("author-name")
                || signature.contains("post-author")
            guard isByline else { return }
            guard let name = normalizeByline(element.textContent) else { return }
            candidates.append(name)
        }
        return candidates.first
    }

    /// Byline markup wraps the label as often as the name — `<span class="byline">by</span>`
    /// is a real pattern — so the label has to survive stripping to count.
    private static func normalizeByline(_ raw: String) -> String? {
        var value = raw.squeezed
        for prefix in ["written by ", "words by ", "by: ", "by ", "author: "] {
            if value.lowercased().hasPrefix(prefix) {
                value = String(value.dropFirst(prefix.count)).squeezed
                break
            }
        }

        guard (3...80).contains(value.count) else { return nil }
        guard value.contains(where: { $0.isLetter }) else { return nil }

        let lowered = value.lowercased()
        let labels: Set<String> = ["by", "author", "authors", "staff", "admin", "editor", "guest", "team"]
        guard !labels.contains(lowered) else { return nil }

        return value
    }

    // MARK: - Helpers

    private static func firstNonEmpty(_ values: [String?]) -> String? {
        for value in values {
            if let value, !value.squeezed.isEmpty { return value.squeezed }
        }
        return nil
    }

    /// Strips a trailing "| Site Name". The tail rarely matches the site name
    /// exactly — "overreacted" vs "overreacted.io" — so both sides are reduced to
    /// letters and numbers and compared by containment. `extraNames` gives a page
    /// with no `og:site_name` a second chance: text pulled from its own banner
    /// landmark, where a site conventionally names itself even without the meta
    /// tag to say so.
    private static func trimmingSiteSuffix(from title: String, siteName: String?, url: URL, extraNames: [String] = []) -> String {
        var names: [String] = []
        if let siteName, !siteName.isEmpty { names.append(siteName) }
        names += extraNames
        if let host = url.host() {
            names.append(host)
            let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            names.append(bare)
            // "en.wikipedia.org" should match a "Wikipedia" suffix, so every
            // component counts, minus the ones that name no publication.
            let noise: Set<String> = ["www", "com", "org", "net", "io", "co", "blog", "en"]
            names += bare.split(separator: ".").map(String.init).filter { !noise.contains($0.lowercased()) }
        }

        // Diacritic-folded so a site's own name still matches its ASCII host
        // component — "Wikipédia" against the "wikipedia" pulled out of
        // fr.wikipedia.org, say. Plain-ASCII titles are untouched by folding,
        // so this only ever helps a non-English site match, never hurts one.
        func key(_ value: String) -> String {
            value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
                .filter { $0.isLetter || $0.isNumber }
        }
        let keys = Set(names.map(key)).filter { $0.count >= 3 }
        guard !keys.isEmpty else { return title }

        for separator in [" | ", " – ", " — ", " - ", " · ", " :: ", " » ", " // "] {
            guard let lastRange = title.range(of: separator, options: .backwards) else { continue }
            let rawTail = String(title[lastRange.upperBound...]).squeezed
            let tail = key(rawTail)
            guard !tail.isEmpty, tail.count <= 40 else { continue }

            // "Rust Blog" names the same site as blog.rust-lang.org, so the
            // generic half of the suffix is dropped before comparing.
            var candidates = [tail]
            for suffix in ["blog", "news", "magazine", "journal", "com"] where tail.hasSuffix(suffix) {
                let trimmed = String(tail.dropLast(suffix.count))
                if trimmed.count >= 3 { candidates.append(trimmed) }
            }
            if let firstWord = rawTail.split(separator: " ").first {
                let word = key(String(firstWord))
                if word.count >= 3 { candidates.append(word) }
            }

            let matches = candidates.contains { candidate in
                keys.contains { $0 == candidate || $0.hasPrefix(candidate) || candidate.hasPrefix($0) }
            }
            guard matches else { continue }

            // The trailing segment is confirmed site chrome. A title chained
            // on the same separator more than once ("Article - Section -
            // Site") is a breadcrumb, not prose that happens to use a dash,
            // so every link back to the first occurrence goes — not just the
            // one segment that happened to match.
            let firstRange = title.range(of: separator) ?? lastRange
            let head = String(title[..<firstRange.lowerBound]).squeezed
            guard !head.isEmpty else { continue }
            return head
        }
        return title
    }

    /// Text pulled from the page's own banner landmark — the ARIA role a site
    /// puts on its site-wide header, distinct from an `<header>` scoped to one
    /// article or section — to give the site-suffix trimmer something to match
    /// against when there is no `og:site_name` at all. A banner conventionally
    /// carries a home link and often a supporting credit alongside it (a "GNU"
    /// logo next to "Supported by the Free Software Foundation", say), so every
    /// link's text inside it is offered as a candidate rather than guessing
    /// which one is "the" name.
    private static func bannerNames(in document: HTMLElement) -> [String] {
        var banners: [HTMLElement] = []
        document.walk { if $0.attributes["role"]?.lowercased() == "banner" { banners.append($0) } }
        guard !banners.isEmpty else { return [] }
        return banners.flatMap { $0.elements(tagged: ["a"]) }
            .map { $0.textContent.squeezed }
            .filter { !$0.isEmpty }
    }

    /// The page's own `<h1>` — but some templates split a bare identifier and
    /// the real headline across two separate `<h1>` elements (an RFC's
    /// number next to its actual title, say, each its own `<h1>`). Using
    /// only the first in that case leaves a saved article titled "RFC 9110",
    /// indistinguishable in a library from "RFC 9111". When the first `<h1>`
    /// reads as a short, letter-and-digit identifier (no lowercase prose)
    /// and a second, different `<h1>` follows, the pair together is the
    /// actual headline.
    private static func headingTitle(in document: HTMLElement) -> String? {
        let headings = document.elements(tagged: ["h1"]).map { $0.textContent.squeezed }.filter { !$0.isEmpty }
        guard let first = headings.first else { return nil }
        guard first.count <= 12, !first.contains(where: \.isLowercase),
              let second = headings.dropFirst().first(where: { $0 != first })
        else { return first }
        return "\(first): \(second)"
    }

    /// Some pages fake a heading with CSS instead of a real `<h1>` — a plain
    /// element carrying a `class="h1"` token, styled to read as one. This is
    /// the last resort in the title fallback chain, after `<title>` itself, so
    /// it only ever fires on a page with no `<title>`, `<h1>`, or Open Graph
    /// title at all — a page whose only remaining title signal would otherwise
    /// be the request URL's host.
    private static func styledHeading(in document: HTMLElement) -> String? {
        var found: String?
        document.walk { element in
            guard found == nil else { return }
            let classes = (element.attributes["class"] ?? "").lowercased().split(separator: " ")
            guard classes.contains("h1") else { return }
            let text = element.textContent.squeezed
            guard !text.isEmpty else { return }
            found = text
        }
        return found
    }

    /// Formats that carry no time of day. Parsed at midnight UTC, "2000-04-06"
    /// renders as April 5th anywhere west of Greenwich, so these land at midday
    /// instead — far enough from either boundary to survive any time zone.
    private static let dateOnlyFormats: Set<String> = [
        "yyyy-MM-dd", "MMMM d, yyyy", "MMM d, yyyy", "d MMMM yyyy",
    ]

    private static let isoFormatters: [ISO8601DateFormatter] = {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        let dateOnly = ISO8601DateFormatter()
        dateOnly.formatOptions = [.withFullDate]
        return [plain, withFractional, dateOnly]
    }()

    private static let fallbackFormats = [
        "yyyy-MM-dd'T'HH:mm:ssZZZZZ", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd",
        "MMMM d, yyyy", "MMM d, yyyy", "d MMMM yyyy", "EEE, dd MMM yyyy HH:mm:ss Z",
    ]

    /// Reads the trailing zone designator of an ISO 8601 timestamp: `Z`,
    /// `+02:00`, or `-0700`. Returns nil for values that name no zone.
    static func parseOffset(_ value: String) -> Int? {
        let trimmed = value.squeezed
        guard trimmed.count >= 6 else { return nil }

        if trimmed.hasSuffix("Z") || trimmed.hasSuffix("z") { return 0 }

        let tail = String(trimmed.suffix(6))
        guard let signIndex = tail.firstIndex(where: { $0 == "+" || $0 == "-" }) else { return nil }

        let sign = tail[signIndex] == "-" ? -1 : 1
        let digits = tail[tail.index(after: signIndex)...].filter { $0.isNumber }
        guard digits.count == 4 else { return nil }

        let hours = Int(digits.prefix(2)) ?? 0
        let minutes = Int(digits.suffix(2)) ?? 0
        return sign * (hours * 3600 + minutes * 60)
    }

    static func parseDate(_ value: String) -> Date? {
        let trimmed = value.squeezed
        let middayOffset: TimeInterval = 12 * 60 * 60

        // Full timestamps first, so a real time of day is never overwritten.
        for (index, formatter) in isoFormatters.enumerated() {
            guard let date = formatter.date(from: trimmed) else { continue }
            // The last ISO formatter is the date-only one.
            return index == isoFormatters.count - 1 ? date.addingTimeInterval(middayOffset) : date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in fallbackFormats {
            formatter.dateFormat = format
            guard let date = formatter.date(from: trimmed) else { continue }
            return dateOnlyFormats.contains(format) ? date.addingTimeInterval(middayOffset) : date
        }
        return nil
    }
}
