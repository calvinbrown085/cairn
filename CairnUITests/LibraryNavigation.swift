import XCTest

/// Getting from launch to a post, reliably.
///
/// The library opens on Unread, and reading a post takes it out of Unread — so
/// a suite that has run before finds that list empty, and a test that assumes
/// the first row is there fails for reasons that have nothing to do with what
/// it is testing. Everything is the filter that is always populated, so these
/// helpers fall back to it.
extension XCUIApplication {
    var firstPostRow: XCUIElement {
        descendants(matching: .any).matching(identifier: "post.row").firstMatch
    }

    /// Returns to the library. A post opens straight into full screen, so the
    /// navigation bar — on iPhone, the way back — isn't there to tap until
    /// full screen is left first; on iPad, leaving full screen is itself what
    /// brings the library column back, so there is nothing further to do.
    /// Each query snapshots the whole accessibility tree, and the reader's is
    /// 200+ text views on a long article — so this asks once, not twice.
    func returnToLibrary() {
        let exit = buttons["reader.exitFullScreen"]
        if exit.exists { exit.tap() }

        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        navigationBars.buttons.firstMatch.tap()
    }

    /// Switches the library to Everything, revealing the filter list first
    /// where it is not already on screen.
    func showEverything() {
        if !staticTexts["Everything"].exists {
            let reveal = navigationBars.buttons.firstMatch
            if reveal.exists { reveal.tap() }
        }

        for candidate in [
            cells.containing(.staticText, identifier: "Everything").firstMatch,
            buttons["Everything"].firstMatch,
            staticTexts["Everything"].firstMatch,
        ] where candidate.waitForExistence(timeout: 4) {
            candidate.tap()
            return
        }
    }
}

extension XCTestCase {
    /// Launches into a library that has posts in it. On iPad this means
    /// landscape, where the split view's sidebar is a real column rather than
    /// an overlay covering the library it filters.
    func launchIntoLibrary() -> XCUIApplication {
        let app = XCUIApplication()
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        app.launch()
        return app
    }

    @discardableResult
    func firstPost(in app: XCUIApplication) -> XCUIElement {
        var post = app.firstPostRow
        if !post.waitForExistence(timeout: 8) {
            app.showEverything()
            post = app.firstPostRow
        }
        if !post.waitForExistence(timeout: 5) {
            // A clean simulator has nothing in it, and `xcodebuild test`
            // reinstalls the app before every run, so nothing placed there by
            // a previous session survives. Rather than depend on an external
            // seeding step, add one real article through the same "Save a
            // link" flow a reader would use, then look again.
            seedArchive(in: app)
            post = app.firstPostRow
        }
        XCTAssertTrue(post.waitForExistence(timeout: 25), "The library should list saved posts")
        return post
    }

    /// Saves one real article so the suite has something to read even when
    /// nothing pre-seeded the archive. Slower than a fixture, but it stays on
    /// the app's own public path instead of reaching into its storage from
    /// outside — which a build with code signing (and so the App Group the
    /// share extension's inbox relies on) disabled can't do anyway.
    ///
    /// A few thousand words, not the 233-block essay `ScrollPerformanceTests`
    /// reaches for: long enough that scrolling six screens down still lands
    /// mid-article, short enough that a text-selection query doesn't time out
    /// walking the accessibility tree.
    private func seedArchive(in app: XCUIApplication) {
        app.buttons["Save a link"].tap()

        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "The link sheet should offer a field to paste into")
        field.tap()
        field.typeText("https://www.paulgraham.com/own.html")
        app.buttons["Save"].tap()

        // Saving jumps straight to the new post rather than back to the list
        // it was added to, and can lose the race with its own row's first
        // render — step back to the list before looking for the row.
        app.returnToLibrary()

        // The row appears right away; wait for the article behind it to
        // finish fetching and extracting before any test tries to read it.
        XCTAssertTrue(app.firstPostRow.waitForExistence(timeout: 15), "Saving a link should add it to the library")
        app.firstPostRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 30), "The seeded article should finish extracting")
        app.returnToLibrary()
        app.showEverything()
    }
}
