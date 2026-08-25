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

    /// Returns to the library. On iPad it is a column that never went away, and
    /// the navigation bar's first button is the sidebar toggle — tapping it
    /// there hides the library rather than revealing it.
    /// Each query snapshots the whole accessibility tree, and the reader's is
    /// 200+ text views on a long article — so this asks once, not twice.
    func returnToLibrary() {
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
        XCTAssertTrue(post.waitForExistence(timeout: 25), "The library should list saved posts")
        return post
    }
}
