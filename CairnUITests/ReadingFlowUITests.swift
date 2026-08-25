import XCTest

/// Drives the app the way a reader would: open the library, pick a post, read
/// it, change the typography. Screenshots are attached to the result bundle so
/// the visual result of a change can be reviewed, not just its exit code.
final class ReadingFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = launchIntoLibrary()
    }

    /// The library opens on Unread, and reading a post empties it — so a test
    /// that has run before finds nothing there. Everything is the filter that
    /// is always populated, so that is where these tests start.
    /// Opens the first post in the library. Tapped by coordinate: a card is one
    /// combined accessibility element, so its centre is the honest target.
    private func openReader() {
        firstPost(in: app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// The first prose block that is actually on screen. Blocks are lazy, so
    /// indexing into `textViews` can land on one the reader has not laid out
    /// yet — which has no frame and cannot be tapped.
    private func bodyTextView() -> XCUIElement {
        let views = app.textViews
        XCTAssertTrue(views.firstMatch.waitForExistence(timeout: 15), "The reader should show article text")

        for element in views.allElementsBoundByIndex
        where element.exists && element.isHittable && element.frame.height > 20 {
            return element
        }
        return views.firstMatch
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testReadingAPost() {
        capture("01-library")
        openReader()
        capture("01b-after-tap")

        // The reader renders each prose block as its own text view.
        let body = app.textViews.firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 15), "The reader should show article text")
        capture("02-reader")

        app.swipeUp()
        app.swipeUp()
        capture("03-reader-scrolled")

        app.buttons["reader.typography"].tap()
        let sepia = app.buttons["Sepia"]
        let paper = app.buttons["Paper"]
        XCTAssertTrue(sepia.waitForExistence(timeout: 5))
        capture("04-typography")

        sepia.tap()
        XCTAssertTrue(sepia.isSelected, "Selecting Sepia should make it the reader's active theme")
        capture("05-reader-sepia")

        paper.tap()
        XCTAssertTrue(paper.isSelected, "Selecting Paper should make it the reader's active theme")
        XCTAssertFalse(sepia.isSelected, "Only one theme should read as active at a time")
        app.buttons["Done"].tap()
        capture("06-reader-paper")
    }

    /// The reader remembers where you left off, and hands you back to it
    /// rather than the top of the article — the thing that makes a long essay
    /// safe to put down mid-paragraph.
    func testPositionRestoreAcrossReopen() {
        let target = firstPost(in: app)
        let marker = String(target.label.prefix(40))
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        _ = bodyTextView()
        // Scroll well past the opening so the restored position is
        // unambiguous — the title header will not read as "further down".
        for _ in 0..<6 { app.swipeUp() }
        let scrolledPassage = bodyTextView().label
        capture("19-scrolled-before-leaving")

        // Progress is written on a debounce; give it time to land before the
        // view that would write it goes away.
        _ = app.staticTexts["nothing"].waitForExistence(timeout: 2)

        app.returnToLibrary()
        app.showEverything()

        let row = app.descendants(matching: .any)
            .matching(identifier: "post.row")
            .matching(NSPredicate(format: "label BEGINSWITH %@", marker))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "The post should still be in the library")
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let reopenedPassage = bodyTextView()
        XCTAssertTrue(reopenedPassage.waitForExistence(timeout: 15))
        capture("20-reopened-at-position")

        XCTAssertEqual(
            reopenedPassage.label, scrolledPassage,
            "Reopening the post should resume where reading left off, not at the top"
        )
    }

    /// Highlighting is the one reader feature that depends on UIKit text
    /// selection, so it is worth driving rather than assuming.
    func testHighlightingAPassage() {
        openReader()

        let body = bodyTextView()

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

    /// Markup mode is the design's headline interaction: no selection handles,
    /// no menu — put the pen out, tap a sentence, and it is marked.
    func testMarkingUpASentence() {
        openReader()

        let body = bodyTextView()

        let markup = app.buttons["reader.markup"]
        XCTAssertTrue(markup.waitForExistence(timeout: 5), "The dock should offer markup")
        markup.tap()
        capture("10-markup-dock")

        // The dock has become the pen tray, and a plain tap now marks text.
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5), "Markup should be leavable")
        // Near the top of the block rather than its centre: a paragraph can be
        // taller than the screen, and its centre can sit under the dock.
        body.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        capture("11-markup-highlighted")

        app.buttons["Done"].tap()

        let highlights = app.buttons["reader.highlights"]
        XCTAssertTrue(highlights.waitForExistence(timeout: 5))
        highlights.tap()
        _ = app.buttons["Delete"].firstMatch.waitForExistence(timeout: 5)
        capture("12-markup-highlights-list")

        XCTAssertTrue(
            app.buttons["Delete"].firstMatch.exists,
            "Tapping a sentence in markup should have recorded a highlight"
        )
    }

    /// Ink is the one part of markup that is not text: a stroke has to land on
    /// the page instead of scrolling it, and has to still be there afterwards.
    func testDrawingWithThePen() {
        let target = firstPost(in: app)
        // Reading takes the post out of Unread, so remember which one it was.
        let marker = String(target.label.prefix(40))
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let body = bodyTextView()

        app.buttons["reader.markup"].tap()
        let pen = app.buttons["Graphite ink"]
        XCTAssertTrue(pen.waitForExistence(timeout: 5), "The pen tray should offer ink")
        pen.tap()

        // A stroke and a scroll are the same gesture; with the pen out the
        // page must hold still under it.
        let before = body.frame.origin.y
        body.swipeUp(velocity: .fast)
        XCTAssertEqual(body.frame.origin.y, before, accuracy: 1, "The pen should lock scrolling")
        capture("15-pen-stroke")

        app.buttons["Done"].tap()
        app.returnToLibrary()
        app.showEverything()

        // The post now reads as marked up, which means the stroke was saved
        // rather than merely drawn.
        let marked = app.descendants(matching: .any)
            .matching(identifier: "post.row")
            .matching(NSPredicate(format: "label BEGINSWITH %@", marker))
            .firstMatch
        XCTAssertTrue(marked.waitForExistence(timeout: 10), "The post should still be in the library")
        XCTAssertTrue(
            marked.label.contains("Marked up"),
            "A drawn stroke should be recorded on the post — got \(marked.label)"
        )
        capture("16-marked-up-card")
    }

    /// Full screen takes the chrome away and has to hand it back without the
    /// reader having to remember a gesture.
    func testFullScreenReading() {
        openReader()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["reader.star"].waitForExistence(timeout: 5))

        let fullScreen = app.buttons["reader.fullscreen"]
        XCTAssertTrue(fullScreen.waitForExistence(timeout: 5), "The dock should offer full screen")
        fullScreen.tap()
        // Let the chrome finish animating out before looking.
        _ = app.staticTexts["nothing"].waitForExistence(timeout: 1.5)
        capture("13-full-screen")

        XCTAssertFalse(app.buttons["reader.star"].exists, "Full screen should put the toolbar away")

        // The dock stays: it is the way back out.
        XCTAssertTrue(fullScreen.waitForExistence(timeout: 5))
        fullScreen.tap()

        XCTAssertTrue(
            app.buttons["reader.star"].waitForExistence(timeout: 5),
            "Leaving full screen should bring the toolbar back"
        )
        capture("14-full-screen-exited")
    }

    /// The two sheets that hang off the library: how it is ordered and drawn,
    /// and how a link gets in.
    func testBrowsingControls() {
        _ = firstPost(in: app)

        app.buttons["Sort & group…"].tap()
        XCTAssertTrue(app.buttons["Cards"].waitForExistence(timeout: 5), "Sort & group should offer a layout")
        XCTAssertTrue(app.switches["Group by site"].exists, "Sort & group should offer grouping")
        capture("17-sort-sheet")
        app.buttons["Done"].tap()

        app.buttons["Save a link"].tap()
        XCTAssertTrue(
            app.staticTexts["Paste or type a web address."].waitForExistence(timeout: 5),
            "The link sheet should prompt for a URL"
        )
        capture("18-add-sheet")
        app.buttons["Cancel"].tap()

        XCTAssertTrue(app.firstPostRow.waitForExistence(timeout: 5), "Both sheets should dismiss")
    }

    func testSidebarAndSearch() {
        // Back out of the post list to the sidebar of filters.
        let back = app.navigationBars.buttons.firstMatch
        if back.exists { back.tap() }
        capture("06-sidebar")
    }
}
