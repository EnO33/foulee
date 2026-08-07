import XCTest

/// Shared plumbing for the App Store capture run (issue #235).
///
/// This target is a **UI test bundle**: it drives the shipped app from another
/// process, so it cannot import app code. The three strings below are therefore
/// duplicated from `ScreenshotMode` / `TodayAccessibility`, and
/// `ScreenshotModeTests` (in `FouleeTests`, which *can* import them) pins the
/// spellings so a rename can't silently detach the two halves.
enum ScreenshotCapture {
    /// Must equal `ScreenshotMode.launchArgument`.
    static let launchArgument = "-FouleeScreenshotMode"
    /// Must equal `ScreenshotMode.onboardingArgument`.
    static let onboardingArgument = "-FouleeScreenshotOnboarding"

    /// Must equal the `TodayAccessibility` constants.
    enum Card {
        static let streak = "today.card.streak"
        static let weather = "today.card.weather"
        static func metric(_ name: String) -> String { "today.card.metric.\(name)" }
    }

    /// How long a screen gets to appear before the run is called broken. Wide,
    /// because a capture run is unattended and a cold simulator launch on a
    /// loaded machine is genuinely slow — not because anything here is racy.
    static let timeout: TimeInterval = 30
}

extension XCTestCase {
    /// Launch the app in capture mode. `onboarding` seeds the preferences as a
    /// fresh install so `RootView` renders the onboarding flow instead of the
    /// home.
    @discardableResult
    func launchInCaptureMode(onboarding: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [ScreenshotCapture.launchArgument]
        if onboarding { app.launchArguments.append(ScreenshotCapture.onboardingArgument) }
        app.launch()
        return app
    }

    /// Save the whole screen — status bar included, at the device's native
    /// pixel size — as a PNG attachment on the test result.
    ///
    /// Attachments rather than a direct file write: the test bundle runs inside
    /// the simulator's sandbox and has no business writing into the developer's
    /// checkout. `tools/capture_screenshots.sh` pulls them out of the result
    /// bundle afterwards, which is also what makes a CI run able to publish
    /// them as an artefact.
    func capture(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot, quality: .original)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Wait for `element`, then tap it. Fails the run rather than tapping into
    /// the void — a capture of the wrong screen is worse than no capture.
    func tapWhenReady(_ element: XCUIElement, _ description: String) {
        XCTAssertTrue(
            element.waitForExistence(timeout: ScreenshotCapture.timeout),
            "\(description) never appeared"
        )
        element.tap()
    }

    /// Let a scroll come to rest and its indicator fade out before the shutter
    /// fires. Without it the only non-reproducible pixel in the whole set is
    /// the grey scroll bar on the hydration capture, which is still fading when
    /// the swipes return — verified: two runs differ on that file alone.
    func settleAfterScrolling() {
        Thread.sleep(forTimeInterval: 2)
    }

    /// Wait for `element` to exist without touching it — used to know a screen
    /// has finished loading before the shutter fires.
    func waitForScreen(_ element: XCUIElement, _ description: String) {
        XCTAssertTrue(
            element.waitForExistence(timeout: ScreenshotCapture.timeout),
            "\(description) never appeared"
        )
    }
}
