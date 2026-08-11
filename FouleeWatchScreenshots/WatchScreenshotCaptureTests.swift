import XCTest

/// Drives the watch app in capture mode and photographs the four screens of
/// the App Store watch set (issues #239, #276). Names match the composer's
/// `shots` table — `watch-01-today`, `watch-02-hydration`, `watch-03-session`,
/// `watch-04-jambes`.
///
/// One launch, one pass: the home, the same home scrolled to the hydration
/// card, then the live session, then the session's own « Jambes » page. The
/// session steps are last because they are the only ones that leave the home,
/// and they run in page order so nothing has to swipe backwards.
///
/// Determinism does not depend on that order. Every number on screen comes from
/// `ScreenshotSeed`, served by `WatchScreenshotMode`; nothing here reads Santé,
/// and the session's elapsed clock is a seeded constant rather than a running
/// timer, so the shutter can fire whenever it likes.
final class WatchScreenshotCaptureTests: XCTestCase {
    /// Enough swipes to reach the bottom of the home's scroll view on any watch
    /// in the set. Overshooting is free — the end clamps, and a clamped
    /// position is identical on every run whatever the swipe momentum did.
    private static let scrollSwipes = 4

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testCaptureWatchScreens() {
        let app = launchWatchInCaptureMode()
        waitForWatchScreen(app.staticTexts["série"], "Watch home")

        captureToday(app)
        captureHydration(app)
        captureSession(app)
        captureLegs(app)
    }

    // MARK: - Steps

    private func captureToday(_ app: XCUIApplication) {
        captureWatch("watch-01-today")
    }

    /// The hydration card sits below the stats grid, so this one is the home
    /// scrolled down — the same framing the iPhone's `07_hydration` uses.
    ///
    /// It lands mid-tile at the top: the clamped bottom of this home puts the
    /// last sliver of the stats grid on screen, so the board opens on two
    /// orphan « km » and « kcal » labels. Stated rather than stumbled into —
    /// the only alternative is parking the scroll partway up, and a partial
    /// scroll is the one thing here that would not be reproducible. See the
    /// scrolling rule in docs/RELEASE.md § 9.1.
    private func captureHydration(_ app: XCUIApplication) {
        for _ in 0..<Self.scrollSwipes { app.swipeUp() }
        waitForWatchScreen(app.buttons["J'ai bu"], "Hydration card")
        settleWatchScrolling()
        captureWatch("watch-02-hydration")
    }

    /// Starting a session records nothing: capture mode returns before
    /// `WatchWorkoutStore` opens an `HKWorkoutSession`, and this run never
    /// stops the session anyway.
    ///
    /// « Démarrer » starts straight away rather than asking which activity,
    /// because the watch resolves the question from the payload the phone
    /// synced and a freshly installed simulator has none — the capture script
    /// uninstalls first for exactly that reason. If it ever did ask, this step
    /// fails loudly on the missing sentinel instead of photographing the wrong
    /// screen.
    ///
    /// The sentinel is a tile of the « Séance » page — it used to be
    /// « Arrêter », which issue #274 moved to its own page.
    ///
    /// **Verified by inverting it**, because a sentinel nobody has watched fail
    /// is a sentinel nobody should trust: with the pager's initial page set to
    /// `.controls`, this step fails. It fails at `waitForExistence`, which is
    /// the useful finding — a paged `TabView` does *not* keep the page it is
    /// not showing in the query hierarchy, so existence alone is already a
    /// framing check here and not merely a spelling one.
    ///
    /// `isHittable` stays anyway. It costs one line, it does not depend on that
    /// hierarchy behaviour holding in a future watchOS, and the failure it
    /// guards against — photographing the wrong page and shipping it to the App
    /// Store — is only ever noticed on release day.
    private func captureSession(_ app: XCUIApplication) {
        tapWatchElement(app.buttons["Démarrer"], "Démarrer")
        let sentinel = app.staticTexts["bpm"]
        waitForWatchScreen(sentinel, "Session in progress")
        XCTAssertTrue(sentinel.isHittable, "Session page is not the page on screen")
        captureWatch("watch-03-session")
    }

    /// The fourth board: the same outing, split (issue #276).
    ///
    /// **Two swipes**, not one — « Contrôles » sits between « Séance » and
    /// « Jambes », which is deliberate (see `WatchSessionPage`). If that order
    /// ever changes, this step fails on a sentinel rather than photographing
    /// the wrong page.
    ///
    /// **One page at a time, each confirmed before the next**, rather than two
    /// swipes fired back to back — the second would land during the first
    /// transition. Waiting on « Arrêter » in between costs nothing and makes the
    /// step depend on the page order rather than on gesture momentum.
    ///
    /// This step is also what caught the pager's axis being wrong. With
    /// `.verticalPage`, these swipes moved a 46 mm and did nothing at all on a
    /// 40 mm: the page's own scroll view took the gesture. A wearer could not
    /// have reached « Arrêter » by swiping either — see `WatchSessionPager`.
    ///
    /// The page exists at all because the seed carries two legs, and both are
    /// closed: a leg still in flight measures itself against the instant it is
    /// drawn, which would make this board depend on when the shutter fired.
    private func captureLegs(_ app: XCUIApplication) {
        app.swipeLeft()
        waitForWatchScreen(app.buttons["Arrêter"], "Controls page")
        app.swipeLeft()
        // The row is one combined accessibility element, so it is matched by
        // the label `WatchSessionLegsPage` builds rather than by a bare word.
        let sentinel = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Marche :"))
            .firstMatch
        waitForWatchScreen(sentinel, "Legs page")
        XCTAssertTrue(sentinel.isHittable, "Legs page is not the page on screen")
        settleWatchScrolling()
        captureWatch("watch-04-jambes")
    }
}
