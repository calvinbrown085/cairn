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
    ///
    /// Only call this from inside the reader. With no full screen to leave,
    /// `exit` correctly doesn't exist, and this falls through to a bare
    /// navigation-bar tap that pops past whatever screen is actually showing
    /// — the library's own back arrow, not a no-op. Seeding used to call
    /// this straight after "Save", which does not open a reader; that
    /// leftover call, not fetch or extraction speed, was the real cause of
    /// this suite's seeding failures (see `seedArchive`).
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
            // A clean simulator has nothing in it. Back-to-back `xcodebuild
            // test` invocations do NOT reinstall the app — the container
            // persists, so a post saved by an earlier invocation (or by an
            // earlier test in this same run) is usually still here, and this
            // branch is only reached after a genuinely fresh install. Rather
            // than depend on an external seeding step, add one real article
            // through the same "Save a link" flow a reader would use, then
            // look again.
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

        // Saving dismisses the sheet and lands back on the list the post was
        // added to directly — there is no reader here to leave first. A
        // stale assumption that there was one used to send this through
        // `returnToLibrary()` regardless; with no full screen actually up,
        // that fell through to a bare navigation-bar tap that popped past
        // the list itself. That — not fetch or extraction speed — was the
        // real cause of this suite's reported seeding failures: the row
        // this test went on to wait for was never on screen to find, no
        // matter how long the wait.
        //
        // The post is inserted locally — and so into the list — before any
        // network call is even made, so the row itself shows up right away.
        // What is genuinely slow is what happens behind it: a real HTTP
        // fetch, then extraction, then (for a post with images) a few image
        // downloads, all before the post leaves `.pending`/`.fetching`.
        let row = app.firstPostRow
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Saving a link should add it to the library")

        guard waitForSeedingToFinish(row, in: app) else { return }

        // Extraction has already finished by this point — this opens a
        // reader on content that already exists, not a second network wait.
        app.firstPostRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(
            app.textViews.firstMatch.waitForExistence(timeout: 10),
            "The seeded article should open once extraction has finished"
        )
        app.returnToLibrary()
        app.showEverything()
    }

    /// Waits for a just-saved post's row to leave the in-flight state,
    /// polling the row's own status text — the same "Queued"/"Fetching…" a
    /// reader sees, via `PostMetaLine` — rather than assuming any fixed
    /// duration for a real fetch and extraction.
    ///
    /// The budget below is not a bigger guess: `PageFetcher` gives its own
    /// network fetch up to 60 seconds before giving up, and extraction plus
    /// any image downloads run after that succeeds — a real run of this same
    /// seed while fixing T-0053 needed up to 90 seconds end to end. That
    /// replaces what used to be two separate, inconsistent guesses (15
    /// seconds for the row, 30 for extraction) about the same underlying
    /// operation with one wait against what the row is actually reporting.
    ///
    /// A seed can also fail for reasons no amount of waiting fixes — no
    /// network, the URL 404ing, or extraction landing under the app's
    /// 40-word floor, any of which marks the post `.failed`. A failed row
    /// does not open into the reader when tapped; tapping it retries
    /// instead — so pressing on regardless would hang out the reader wait
    /// above and report a misleading "extraction didn't finish." Recognizing
    /// the row's own failure text here reports that as the specific, real
    /// failure it is. Returns `false` (having already failed the test) in
    /// either the timeout or the failure case; `true` once the row is ready.
    @discardableResult
    private func waitForSeedingToFinish(_ row: XCUIElement, in app: XCUIApplication) -> Bool {
        let deadline = Date().addingTimeInterval(90)
        var status = row.label

        while Date() < deadline {
            status = row.label
            if !status.contains("Queued"), !status.contains("Fetching") { break }
            _ = app.staticTexts["nothing"].waitForExistence(timeout: 1)
        }

        // Exact wording a `.failed` row shows — see `PostMetaLine`, and the
        // failure reasons `ArchiveService`/`PageFetcher` attach to a post.
        let failureSignals = [
            "doesn't look like a web address",
            "couldn't be found (404)",
            "refused the request (403)",
            "needs a login",
            "returned an error",
            "not an article",
            "text couldn't be read",
            "appear to be offline",
            "No readable article was found",
            "Only a few words could be read",
            "Couldn't be saved",
        ]
        if let reason = failureSignals.first(where: { status.contains($0) }) {
            XCTFail("""
                Seeding failed rather than merely being slow — the row reports \
                "\(reason)". A longer wait will not fix this: check that this \
                simulator can actually reach the seed URL.
                """)
            return false
        }
        if status.contains("Queued") || status.contains("Fetching") {
            XCTFail("""
                Seeding is still \(status.contains("Queued") ? "queued" : "fetching") \
                after 90 seconds — past even the 60-second timeout the fetch \
                itself is given up on. That makes this an environment or \
                network problem, not a feature bug.
                """)
            return false
        }
        return true
    }
}
