import Foundation
@testable import SwiftReadability

/// The frozen shape an extraction is expected to land in. One JSON file per
/// fixture, named identically to its `.html` counterpart.
struct FixtureExpectation: Decodable {
    let title: String
    let wordCount: Int
    /// Block-type name (see `ArticleBlock.kind` in `FixtureTests.swift`) to
    /// how many of that block the extractor is expected to produce.
    let blockCounts: [String: Int]
}

/// Loads frozen fixtures — an HTML capture plus its expected extraction — from
/// the test bundle. Fixtures ship as bundled resources so `swift test` reads
/// them straight off disk with no network access and no simulator.
///
/// Adding a fixture is dropping `name.html` and `name.json` into `Fixtures/`;
/// `allNames` discovers it from the bundle at runtime, so no test file needs
/// editing to pick it up.
enum FixtureLoader {

    /// Every fixture name found in the bundled `Fixtures/` directory, derived
    /// from whichever `.json` expectation files are present.
    static var allNames: [String] {
        guard let directory = fixturesDirectory,
              let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        return entries
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    static func html(_ name: String) -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Fixtures"),
              let contents = try? String(contentsOf: url, encoding: .utf8)
        else {
            fatalError("Missing fixture HTML for '\(name)' — expected Fixtures/\(name).html")
        }
        return contents
    }

    static func expectation(_ name: String) -> FixtureExpectation {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(FixtureExpectation.self, from: data)
        else {
            fatalError("Missing or invalid fixture expectation for '\(name)' — expected Fixtures/\(name).json")
        }
        return decoded
    }

    /// The URL extraction should treat a fixture as having come from.
    ///
    /// A real capture carries its own origin in `<link rel="canonical">` or
    /// `<meta property="og:url">` — reading that back out of the frozen HTML
    /// (never fetched, just parsed) matters because `ArticleMetadata` strips a
    /// page's title suffix by matching it against the request URL's host. Every
    /// fixture handed the same placeholder host would make that matching fail
    /// for every real page, and the fixture would then be "wrong" for a reason
    /// that has nothing to do with the extractor. Hand-authored shapes have no
    /// real origin, so they keep the placeholder.
    static func sourceURL(_ name: String) -> URL {
        let document = HTMLParser.parse(html(name))
        let canonical = document.elements(tagged: ["link"])
            .first { $0.attributes["rel"]?.lowercased() == "canonical" }?
            .attributes["href"]
        let ogURL = document.elements(tagged: ["meta"])
            .first { $0.attributes["property"]?.lowercased() == "og:url" }?
            .attributes["content"]
        if let raw = canonical ?? ogURL, let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://example.com/\(name)")!
    }

    private static var fixturesDirectory: URL? {
        Bundle.module.url(forResource: "Fixtures", withExtension: nil)
    }
}
