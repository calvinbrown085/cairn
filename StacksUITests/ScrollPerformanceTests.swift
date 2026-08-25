import XCTest

/// Scrolling performance against the longest archived article.
///
/// "How to Do Great Work" is ~11,800 words in 233 blocks — the worst case the
/// reader has to handle, and the one where any per-frame work in the view body
/// shows up immediately.
final class ScrollPerformanceTests: XCTestCase {

    /// The suite is seeded by `Tools/seed-simulator.sh` so the long article is
    /// the most recent save, and therefore the first row.
    private func openLongestArticle(_ app: XCUIApplication) {
        firstPost(in: app).tap()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 25))
    }

    /// How long it takes to present a 233-block article at all.
    ///
    /// Phone only: a split view keeps the article on screen beside the library,
    /// so there is no open-from-cold to time.
    func testTimeToOpenLongArticle() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "Opening is only a distinct event where the reader is a separate screen"
        )

        let app = launchIntoLibrary()
        let row = firstPost(in: app)

        measure(metrics: [XCTClockMetric()]) {
            row.tap()
            _ = app.textViews.firstMatch.waitForExistence(timeout: 25)
            app.returnToLibrary()
            _ = row.waitForExistence(timeout: 10)
        }
    }

    /// Wall-clock and CPU cost of a fixed run of scrolling.
    func testScrollingThroughLongArticle() {
        let app = launchIntoLibrary()
        openLongestArticle(app)

        let scroll = app.scrollViews.firstMatch

        // Three passes, not the default five. Every swipe snapshots a 233-block
        // accessibility tree, and five passes of eight swipes lands within a
        // second or two of the harness's own query timeout — which makes the
        // test fail for its length rather than for a regression.
        let options = XCTMeasureOptions()
        options.iterationCount = 3

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(application: app)], options: options) {
            for _ in 0..<8 {
                scroll.swipeUp(velocity: .fast)
            }
        }
    }
}
