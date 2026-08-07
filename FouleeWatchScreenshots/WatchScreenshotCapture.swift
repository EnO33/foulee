import XCTest

/// Shared plumbing for the Apple Watch capture run (issue #239) — the wrist
/// twin of `FouleeScreenshots/ScreenshotCapture.swift`.
///
/// This target is a **UI test bundle**: it drives the shipped watch app from
/// another process, so it cannot import app code. The launch argument below is
/// therefore duplicated from `WatchScreenshotMode`, and
/// `FouleeWatchTests/WatchScreenshotModeTests` (which *can* import it) pins the
/// spelling so a rename can't silently detach the two halves — the failure mode
/// being a run that photographs an empty simulator's zeros and calls them a
/// store screenshot.
///
/// That pin reads **this file's text**, not just the constant: nothing else in
/// CI does. This target is absent from the `FouleeWatch` scheme's test action
/// and from `.swiftlint.yml`'s `included:`, so a rename here would otherwise
/// compile and lint clean and only surface on release day.
enum WatchScreenshotCapture {
    /// Must equal `WatchScreenshotMode.launchArgument`.
    static let launchArgument = "-FouleeScreenshotMode"

    /// How long a screen gets to appear before the run is called broken. Wide,
    /// because a capture run is unattended and a cold watch simulator launch is
    /// genuinely slow — not because anything here is racy.
    static let timeout: TimeInterval = 60
}

extension XCTestCase {
    /// Launch the watch app in capture mode.
    @discardableResult
    func launchWatchInCaptureMode() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [WatchScreenshotCapture.launchArgument]
        app.launch()
        return app
    }

    /// Save the whole screen at the device's native pixel size as a PNG
    /// attachment on the test result.
    ///
    /// Attachments rather than a direct file write: the test bundle runs inside
    /// the simulator's sandbox and has no business writing into the developer's
    /// checkout. `tools/capture_screenshots.sh` pulls them out of the result
    /// bundle afterwards.
    func captureWatch(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot, quality: .original)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Wait for `element`, then tap it. Fails the run rather than tapping into
    /// the void — a capture of the wrong screen is worse than no capture.
    func tapWatchElement(_ element: XCUIElement, _ description: String) {
        XCTAssertTrue(
            element.waitForExistence(timeout: WatchScreenshotCapture.timeout),
            "\(description) never appeared"
        )
        element.tap()
    }

    /// Wait for `element` to exist without touching it — used to know a screen
    /// has finished loading before the shutter fires.
    func waitForWatchScreen(_ element: XCUIElement, _ description: String) {
        XCTAssertTrue(
            element.waitForExistence(timeout: WatchScreenshotCapture.timeout),
            "\(description) never appeared"
        )
    }

    /// Let a scroll come to rest and its indicator fade out before the shutter
    /// fires — the same non-reproducible pixel the iPhone run had to wait out.
    func settleWatchScrolling() {
        Thread.sleep(forTimeInterval: 2)
    }
}
