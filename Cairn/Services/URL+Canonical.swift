import Foundation

extension URL {
    /// Campaign parameters that identify where a link was clicked, not what it
    /// points at. Two links differing only in these are the same article.
    private static let trackingParameters: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "utm_id", "utm_name", "utm_reader", "utm_brand", "utm_social",
        "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "twclid",
        "igshid", "mc_cid", "mc_eid", "_hsenc", "_hsmi", "vero_id", "yclid",
        "ref", "referrer", "source", "share", "shared", "at_medium", "at_campaign",
        "s", "__twitter_impression", "guccounter", "guce_referrer",
    ]

    /// A stable identity for an article URL: lowercase host, no `www.`, no
    /// tracking parameters, no fragment, no trailing slash.
    func canonicalizedForArchive() -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self
        }

        components.fragment = nil
        components.scheme = components.scheme?.lowercased()

        if let host = components.host?.lowercased() {
            components.host = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }

        if let items = components.queryItems {
            let kept = items.filter { !URL.trackingParameters.contains($0.name.lowercased()) }
            components.queryItems = kept.isEmpty ? nil : kept
        }

        if components.path.count > 1, components.path.hasSuffix("/") {
            components.path = String(components.path.dropLast())
        }

        return components.url ?? self
    }

    /// Interprets whatever the user typed or shared. Bare domains get an https
    /// scheme so "jvns.ca/blog" resolves instead of failing.
    static func fromUserInput(_ raw: String) -> URL? {
        let trimmed = raw.squeezed
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), url.scheme != nil, url.host() != nil {
            return url
        }
        if let url = URL(string: "https://\(trimmed)"), url.host() != nil {
            return url
        }
        return nil
    }
}
