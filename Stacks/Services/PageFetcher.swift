import Foundation

enum FetchError: LocalizedError {
    case badURL
    case http(Int)
    case notHTML(String)
    case undecodable
    case offline

    var errorDescription: String? {
        switch self {
        case .badURL: "That doesn't look like a web address."
        case .http(let code) where code == 404: "The page couldn't be found (404)."
        case .http(let code) where code == 403: "The site refused the request (403)."
        case .http(let code) where code == 401: "That page needs a login."
        case .http(let code): "The site returned an error (\(code))."
        case .notHTML(let kind): "That link is \(kind), not an article."
        case .undecodable: "The page's text couldn't be read."
        case .offline: "You appear to be offline."
        }
    }
}

/// Fetches a page's HTML. Presents itself as Safari because a fair number of
/// publishers serve a stub or a block page to anything that doesn't.
struct PageFetcher {
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 60
        configuration.httpAdditionalHeaders = [
            "User-Agent": PageFetcher.userAgent,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9",
        ]
        session = URLSession(configuration: configuration)
    }

    struct Page {
        var html: String
        /// The URL after redirects — relative links must resolve against this.
        var finalURL: URL
    }

    /// Fetches a page, following any `<meta http-equiv="refresh">` it lands on.
    /// Moved posts and link shorteners often redirect that way rather than with
    /// a 3xx, and the interstitial holds no article at all.
    func fetch(_ url: URL) async throws -> Page {
        var target = url
        var page = try await fetchOnce(target)

        for _ in 0..<2 {
            guard let next = PageFetcher.metaRefreshTarget(in: page.html, base: page.finalURL),
                  next != target else { break }
            target = next
            page = try await fetchOnce(next)
        }

        return page
    }

    private func fetchOnce(_ url: URL) async throws -> Page {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw FetchError.badURL
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(from: url)
        } catch let error as URLError where error.code == .notConnectedToInternet {
            throw FetchError.offline
        }

        guard let http = response as? HTTPURLResponse else { throw FetchError.undecodable }
        guard (200..<300).contains(http.statusCode) else { throw FetchError.http(http.statusCode) }

        let mime = (http.mimeType ?? "").lowercased()
        if !mime.isEmpty, !mime.contains("html"), !mime.contains("xml"), !mime.contains("text/plain") {
            throw FetchError.notHTML(PageFetcher.describe(mime: mime))
        }

        let finalURL = http.url ?? url
        guard let html = PageFetcher.decode(data, response: http) else { throw FetchError.undecodable }
        return Page(html: html, finalURL: finalURL)
    }

    /// Pulls the destination out of a meta-refresh tag, if the page has one that
    /// fires more or less immediately.
    static func metaRefreshTarget(in html: String, base: URL) -> URL? {
        // Only the head matters, and only the first few KB of it.
        let head = String(html.prefix(6000)).lowercased()
        guard head.contains("http-equiv") else { return nil }

        var cursor = head.startIndex
        while let tagStart = head.range(of: "<meta", range: cursor..<head.endIndex) {
            guard let tagEnd = head.range(of: ">", range: tagStart.upperBound..<head.endIndex) else { break }
            let tag = String(head[tagStart.lowerBound..<tagEnd.upperBound])
            cursor = tagEnd.upperBound

            guard tag.contains("http-equiv"), tag.contains("refresh") else { continue }
            guard let contentRange = tag.range(of: "content=") else { continue }

            let rest = tag[contentRange.upperBound...]
            let quote = rest.first
            let value: Substring
            if quote == "\"" || quote == "'" {
                let body = rest.dropFirst()
                guard let close = body.firstIndex(of: quote!) else { continue }
                value = body[body.startIndex..<close]
            } else {
                value = rest.prefix { !$0.isWhitespace && $0 != ">" }
            }

            // "3; url=..." — a long delay is a notice page, not a redirect.
            let parts = value.split(separator: ";", maxSplits: 1)
            if let delay = parts.first.flatMap({ Double($0.squeezed) }), delay > 5 { continue }
            guard parts.count == 2, let urlRange = parts[1].range(of: "url=") else { continue }

            var destination = String(parts[1][urlRange.upperBound...]).squeezed
            destination = destination.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            guard !destination.isEmpty else { continue }

            // The head was lowercased for scanning; recover the original casing,
            // which matters for path components on case-sensitive servers.
            if let original = PageFetcher.originalCasing(of: destination, in: html) {
                destination = original
            }
            return URL(string: destination, relativeTo: base)?.absoluteURL
        }
        return nil
    }

    private static func originalCasing(of lowercased: String, in html: String) -> String? {
        guard let range = html.range(of: lowercased, options: .caseInsensitive) else { return nil }
        return String(html[range])
    }

    // MARK: - Text decoding

    /// Tries the declared charset, then the `<meta charset>` in the bytes, then
    /// the encodings that cover almost everything else.
    static func decode(_ data: Data, response: HTTPURLResponse?) -> String? {
        if let name = response?.textEncodingName,
           let text = decode(data, charset: name) {
            return text
        }

        // Sniff the first few KB for a declared charset.
        let head = String(decoding: data.prefix(4096), as: UTF8.self).lowercased()
        if let range = head.range(of: "charset=") {
            let tail = head[range.upperBound...]
            let name = tail.prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
            if !name.isEmpty, let text = decode(data, charset: String(name)) {
                return text
            }
        }

        for encoding in [String.Encoding.utf8, .isoLatin1, .windowsCP1252, .utf16] {
            if let text = String(data: data, encoding: encoding), !text.isEmpty { return text }
        }
        return nil
    }

    private static func decode(_ data: Data, charset: String) -> String? {
        let cf = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
        guard cf != kCFStringEncodingInvalidId else { return nil }
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
        return String(data: data, encoding: encoding)
    }

    private static func describe(mime: String) -> String {
        if mime.contains("pdf") { return "a PDF" }
        if mime.hasPrefix("image/") { return "an image" }
        if mime.hasPrefix("video/") { return "a video" }
        if mime.hasPrefix("audio/") { return "audio" }
        if mime.contains("json") { return "raw data" }
        return "a \(mime) file"
    }
}
