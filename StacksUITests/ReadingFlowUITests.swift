import XCTest

/// Drives the app the way a reader would: open the library, pick a post, read
/// it, change the typography. Screenshots are attached to the result bundle so
/// the visual result of a change can be reviewed, not just its exit code.
final class ReadingFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testReadingAPost() {
        // Addressed by identifier rather than position: on iPad the sidebar's
        // own cells come first in the query order.
        let firstPost = app.descendants(matching: .any)
            .matching(identifier: "post.row")
            .firstMatch
        XCTAssertTrue(firstPost.waitForExistence(timeout: 20), "The library should list saved posts")
        capture("01-library")

        firstPost.tap()

        // The reader renders each prose block as its own text view.
        let body = app.textViews.firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 15), "The reader should show article text")
        capture("02-reader")

        app.swipeUp()
        app.swipeUp()
        capture("03-reader-scrolled")

        app.buttons["reader.typography"].tap()
        XCTAssertTrue(app.buttons["Sepia"].waitForExistence(timeout: 5))
        capture("04-typography")

        app.buttons["Sepia"].tap()
        capture("05-reader-sepia")

        app.buttons["Paper"].tap()
        app.buttons["Done"].tap()
        capture("06-reader-paper")
    }

    /// Highlighting is the one reader feature that depends on UIKit text
    /// selection, so it is worth driving rather than assuming.
    func testHighlightingAPassage() {
        let firstPost = app.descendants(matching: .any)
            .matching(identifier: "post.row")
            .firstMatch
        XCTAssertTrue(firstPost.waitForExistence(timeout: 20))
        firstPost.tap()

        let body = app.textViews.element(boundBy: 1)
        XCTAssertTrue(body.waitForExistence(timeout: 15))

        // A long press starts a selection and raises the edit menu.
        body.press(forDuration: 1.2)

        let highlight = app.menuItems["Highlight"].firstMatch
        let fallback = app.buttons["Highlight"].firstMatch
        let appeared = highlight.waitForExistence(timeout: 6) || fallback.waitForExistence(timeout: 3)
        capture("07-selection-menu")
        XCTAssertTrue(appeared, "The selection menu should offer Highlight")

        (highlight.exists ? highlight : fallback).tap()
        capture("08-highlighted")

        // The highlight should now be listed under the reader's overflow menu.
        app.buttons["reader.overflow"].tap()
        let entry = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Highlights'")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "The highlight should be recorded on the post")
        entry.tap()
        capture("09-highlights-list")
    }

    func testSidebarAndSearch() {
        // Back out of the post list to the sidebar of filters.
        let back = app.navigationBars.buttons.firstMatch
        if back.exists { back.tap() }
        capture("06-sidebar")
    }
}
