import XCTest

/// Scrolling performance against the longest archived article.
///
/// "How to Do Great Work" is ~11,800 words in 233 blocks — the worst case the
/// reader has to handle, and the one where any per-frame work in the view body
/// shows up immediately.
final class ScrollPerformanceTests: XCTestCase {

    /// The suite is seeded by `Tools/seed-simulator.sh` so the long article is
    /// the most recent save, and therefore the first row.
    private func firstRow(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "post.row").firstMatch
    }

    private func openLongestArticle(_ app: XCUIApplication) {
        let row = firstRow(app)
        XCTAssertTrue(row.waitForExistence(timeout: 25), "The long test article should be archived")
        row.tap()
        XCTAssertTrue(app.textViews.element(boundBy: 1).waitForExistence(timeout: 25))
    }

    /// How long it takes to present a 233-block article at all.
    func testTimeToOpenLongArticle() {
        let app = XCUIApplication()
        app.launch()

        let row = firstRow(app)
        XCTAssertTrue(row.waitForExistence(timeout: 25))

        measure(metrics: [XCTClockMetric()]) {
            row.tap()
            _ = app.textViews.element(boundBy: 1).waitForExistence(timeout: 25)
            app.navigationBars.buttons.firstMatch.tap()
            _ = row.waitForExistence(timeout: 10)
        }
    }

    /// Wall-clock and CPU cost of a fixed run of scrolling.
    func testScrollingThroughLongArticle() {
        let app = XCUIApplication()
        app.launch()
        openLongestArticle(app)

        let scroll = app.scrollViews.firstMatch

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(application: app)]) {
            for _ in 0..<8 {
                scroll.swipeUp(velocity: .fast)
            }
        }
    }
}
