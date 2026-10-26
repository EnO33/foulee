import XCTest

/// Shared plumbing for the App Store capture run (issue #235).
///
/// This target is a **UI test bundle**: it drives the shipped app from another
/// process, so it cannot import app code. The strings below are therefore
/// duplicated from `ScreenshotMode` / `TodayAccessibility`, and
/// `ScreenshotModeTests` (in `FouleeTests`, which *can* import them) pins the
/// spellings so a rename can't silently detach the two halves.
enum ScreenshotCapture {
    /// Must equal `ScreenshotMode.launchArgument`.
    static let launchArgument = "-FouleeScreenshotMode"
    /// Must equal `ScreenshotMode.onboardingArgument`.
    static let onboardingArgument = "-FouleeScreenshotOnboarding"
    /// Must equal `ScreenshotMode.darkArgument`.
    static let darkArgument = "-FouleeScreenshotDark"

    /// A wrist recording an outing when the app opens.
    enum Wrist {
        case watch, garmin

        /// Must equal `ScreenshotMode.watchOutingArgument` and
        /// `ScreenshotMode.garminOutingArgument`.
        var argument: String {
            switch self {
            case .watch: "-FouleeScreenshotWatchOuting"
            case .garmin: "-FouleeScreenshotGarminOuting"
            }
        }
    }

    /// French, whatever the host runs (issue #408): the boards are French, and
    /// a simulator left in English groups thousands as « 8,240 ». CI runners
    /// are in English; a developer's Mac usually is not, which is why the
    /// difference went unseen until the captures moved to CI.
    static let localeArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"]

    /// Set by `tools/capture_screenshots.sh --dark`. xcodebuild hands the test
    /// runner every `TEST_RUNNER_`-prefixed variable without the prefix, which
    /// is the only channel from the script into this process.
    static var isDark: Bool {
        ProcessInfo.processInfo.environment["FOULEE_CAPTURE_DARK"] == "1"
    }

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
    /// home; `wrist` starts it with an outing running on that watch.
    @discardableResult
    func launchInCaptureMode(onboarding: Bool = false, wrist: ScreenshotCapture.Wrist? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [ScreenshotCapture.launchArgument] + ScreenshotCapture.localeArguments
        if onboarding { app.launchArguments.append(ScreenshotCapture.onboardingArgument) }
        if let wrist { app.launchArguments.append(wrist.argument) }
        if ScreenshotCapture.isDark { app.launchArguments.append(ScreenshotCapture.darkArgument) }
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
