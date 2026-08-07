import XCTest

/// Drives the watch app in capture mode and photographs the three screens of
/// the App Store watch set (issue #239). Names match the composer's `shots`
/// table — `watch-01-today`, `watch-02-hydration`, `watch-03-session`.
///
/// One launch, one pass: the home, the same home scrolled to the hydration
/// card, then the live session. The session is last because it is the only step
/// that leaves the home, so nothing after it has to be reasoned about.
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
    /// fails loudly on the missing « Arrêter » instead of photographing the
    /// wrong screen.
    private func captureSession(_ app: XCUIApplication) {
        tapWatchElement(app.buttons["Démarrer"], "Démarrer")
        waitForWatchScreen(app.buttons["Arrêter"], "Session in progress")
        captureWatch("watch-03-session")
    }
}
