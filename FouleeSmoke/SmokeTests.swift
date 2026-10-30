import XCTest

/// A walk through the iPhone app on the iPhone Duo's inner screen (issue
/// #665): every main screen opens, its way back can be reached, and an outing
/// starts and ends. A rejection under Guideline 2.1(a) comes from a button out
/// of reach in one posture; this test fails on that before a reviewer does.
///
/// The app runs in capture mode (`ScreenshotCapture`), so the home and the
/// Bilan show the same seeded day on every run and nothing is written to
/// Santé. `tools/smoke_test.sh` runs it on the iPhone Duo simulator, unfolded:
/// no tool folds the simulator, so the outer screen is checked by hand.
@MainActor
final class SmokeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testMainScreens() {
        let app = launchInCaptureMode()
        waitForHome(app)

        tapWhenReady(app.buttons.labeled(ScreenshotCapture.label.seeSummary), "Voir le bilan")
        waitForScreen(app.buttons.labeled(ScreenshotCapture.label.seeInHealth), "Bilan")
        close(app)
        waitForHome(app)

        tapWhenReady(app.buttons.labeled(ScreenshotCapture.label.settings), "Settings button")
        waitForScreen(app.staticTexts.labeled(ScreenshotCapture.label.settings), "Settings")
        close(app)
        waitForHome(app)
    }

    /// « Repartir » starts the timer straight away; « Arrêter » ends the outing
    /// without asking, and « Terminer » brings the home back.
    func testOuting() {
        let app = launchInCaptureMode()
        tapWhenReady(app.buttons.labeled(ScreenshotCapture.label.goAgain), "Repartir")
        waitForScreen(app.staticTexts.labeled(ScreenshotCapture.label.inProgress), "Outing in progress")
        tapWhenReady(app.buttons.labeled(ScreenshotCapture.label.stop), "Stop button")
        waitForScreen(app.staticTexts.labeled(ScreenshotCapture.label.outingFinished), "Finished outing")
        tapWhenReady(app.buttons.labeled(ScreenshotCapture.label.finish), "Finish button")
        waitForHome(app)
    }

    private func waitForHome(_ app: XCUIApplication) {
        waitForScreen(app.buttons[ScreenshotCapture.Card.streak], "Home")
    }
}
