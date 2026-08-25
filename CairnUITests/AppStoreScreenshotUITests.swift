import XCTest

/// Captures the shots App Store Connect asks for: the library, an article
/// read full screen, a highlighted passage, and a search result with its
/// matched phrase picked out. One test, one pass through the app, in the
/// order that reads best as a set of marketing screenshots — browse, read,
/// annotate, find.
///
/// Nothing here builds new navigation: every step reuses the helpers in
/// `LibraryNavigation.swift` that `ReadingFlowUITests` already relies on.
/// `Tools/screenshots.sh` seeds the library through the share-extension
/// inbox before this test ever launches the app — see that script for why —
/// so `firstPost(in:)` below finds the seeded article immediately rather
/// than needing its own conditional seeding fallback. `Tools/screenshots.sh`
/// turns the `XCTAttachment`s captured here into named PNG files — the
/// numeric prefixes are the upload order, so keep them in sync with that
/// script's naming scheme if a step is added or reordered.
final class AppStoreScreenshotUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = launchIntoLibrary()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The first prose block actually laid out on screen — see
    /// `ReadingFlowUITests.bodyTextView()`, which this mirrors. Blocks render
    /// lazily, so indexing straight into `textViews` can land on one with no
    /// frame yet, and a press on that never raises the selection menu.
    private func bodyTextView() -> XCUIElement {
        let views = app.textViews
        XCTAssertTrue(views.firstMatch.waitForExistence(timeout: 30), "The reader should show article text")

        for element in views.allElementsBoundByIndex
        where element.exists && element.isHittable && element.frame.height > 20 {
            return element
        }
        return views.firstMatch
    }

    /// A word long enough to be distinctive, pulled out of a library row's
    /// combined accessibility label. The label starts with the post's title
    /// (see `LibraryView.row`'s `.accessibilityElement(children: .combine)`),
    /// and `Post.searchText` always includes the title — so this word is
    /// guaranteed to bring the row itself back as a search result, whatever
    /// the seeded article's actual title turns out to be.
    private func searchTerm(from label: String) -> String {
        let word = label.split(whereSeparator: { !$0.isLetter })
            .first(where: { $0.count >= 5 })
        if let word { return String(word) }
        return String(label.prefix(6))
    }

    func testCaptureAppStoreScreenshots() {
        let target = firstPost(in: app)
        let query = searchTerm(from: target.label)
        capture("01-library")

        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 30), "The reader should show article text")
        capture("02-full-screen-article")

        // A long press starts a selection and raises the edit menu — the
        // same gesture `ReadingFlowUITests.testHighlightingAPassage` drives.
        let body = bodyTextView()
        body.press(forDuration: 1.2)
        let highlight = app.menuItems["Highlight"].firstMatch
        let fallback = app.buttons["Highlight"].firstMatch
        XCTAssertTrue(
            highlight.waitForExistence(timeout: 10) || fallback.waitForExistence(timeout: 5),
            "The selection menu should offer Highlight"
        )
        (highlight.exists ? highlight : fallback).tap()
        capture("03-highlighted-passage")

        app.returnToLibrary()
        app.showEverything()

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "The library should offer a search field")
        field.tap()
        field.typeText(query)

        // Dismiss the keyboard so the filtered row isn't hidden behind it —
        // tapping the keyboard's own search key commits the search rather
        // than adding a newline.
        let searchKey = app.keyboards.buttons["Search"]
        if searchKey.waitForExistence(timeout: 3) { searchKey.tap() }

        XCTAssertTrue(app.firstPostRow.waitForExistence(timeout: 20), "Searching should still find the seeded post")
        capture("04-search-snippet")
    }
}
