import XCTest

/// How long the iPhone app takes to open, cold, until its home is on screen
/// (issue #613).
///
/// The app runs in capture mode (`ScreenshotCapture`), so every launch opens on
/// the same seeded home rather than on whatever the simulator's Health store
/// holds. XCTest keeps no baseline here: `tools/launch_time.sh` reads the
/// measurements out of the result bundle and compares the fastest with
/// `LaunchTimeBudget.json`, the same way on a Mac and in CI.
///
/// A wall clock rather than `XCTApplicationLaunchMetric`: on CI's virtual
/// machines the launch metric launches the app and records nothing. The clock
/// also counts XCUITest setting up its session, the same few seconds on every
/// run, which the budget's tolerance covers.
@MainActor
final class LaunchTimeTests: XCTestCase {
    func testLaunch() {
        let options = XCTMeasureOptions()
        options.iterationCount = 7
        measure(metrics: [XCTClockMetric()], options: options) {
            let app = launchInCaptureMode()
            waitForScreen(app.buttons[ScreenshotCapture.Card.streak], "Home")
        }
    }
}
