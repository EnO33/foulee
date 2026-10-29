import XCTest

/// How long the iPhone app takes to open, cold, until it answers a touch
/// (issue #613).
///
/// The app runs in capture mode (`ScreenshotCapture`), so every launch opens on
/// the same seeded home rather than on whatever the simulator's Health store
/// holds. XCTest keeps no baseline here: `tools/launch_time.sh` reads the
/// measurements out of the result bundle and compares their median with
/// `LaunchTimeBudget.json`, the same way on a Mac and in CI.
@MainActor
final class LaunchTimeTests: XCTestCase {
    func testLaunch() {
        let options = XCTMeasureOptions()
        options.iterationCount = 7
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options) {
            launchInCaptureMode()
        }
    }
}
