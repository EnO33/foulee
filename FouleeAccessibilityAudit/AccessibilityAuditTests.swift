import XCTest

/// Xcode's accessibility audit on every main screen of the iPhone app (issue
/// #602): labels, traits, contrast, hit regions, clipped text, Dynamic Type.
///
/// The app runs in capture mode (`ScreenshotCapture`), so each screen shows the
/// same seeded day on every run and a finding cannot come and go with the data.
/// A finding fails the test unless `AccessibilityAuditBaseline` already knows
/// it.
@MainActor
final class AccessibilityAuditTests: XCTestCase {
    /// One audit per test, last: a failed audit ends its test, and nothing
    /// after it would be checked.
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testOnboarding() throws {
        let app = launchInCaptureMode(onboarding: true)
        waitForScreen(app.buttons.labeled(ScreenshotCapture.label.start), "Onboarding welcome step")
        try audit(app, "Onboarding")
    }

    func testHome() throws {
        let app = launchHome()
        try audit(app, "Home")
    }

    func testStreak() throws {
        let app = launchHome()
        tapWhenReady(app.buttons[ScreenshotCapture.Card.streak], "Streak badge")
        waitForScreen(app.buttons.labeled(ScreenshotCapture.label.seeInHealth), "Bilan month")
        try audit(app, "Bilan, month")
    }

    func testStatistics() throws {
        let app = launchHome()
        tapWhenReady(app.buttons[ScreenshotCapture.Card.metric("steps")], "Steps card")
        waitForScreen(app.staticTexts.labeled(ScreenshotCapture.label.statistics), "Steps statistics")
        try audit(app, "Steps statistics")
    }

    func testHydration() throws {
        let app = launchHome()
        tapWhenReady(app.buttons.labeled(ScreenshotCapture.label.hydration).firstMatch, "Hydration card title")
        waitForScreen(app.staticTexts.labeled(ScreenshotCapture.label.glassByGlass), "Hydration screen")
        try audit(app, "Hydration")
    }

    func testSummary() throws {
        let app = openSummary()
        try audit(app, "Bilan, week")
    }

    func testOuting() throws {
        let app = openSummary()
        tapWhenReady(app.staticTexts.labeled(ScreenshotCapture.label.walkAndRun).firstMatch, "Today's outing")
        waitForScreen(app.staticTexts.labeled(ScreenshotCapture.label.portions), "Outing detail")
        try audit(app, "Outing detail")
    }

    func testSettings() throws {
        let app = launchHome()
        tapWhenReady(app.buttons.labeled(ScreenshotCapture.label.settings), "Settings button")
        waitForScreen(app.staticTexts.labeled(ScreenshotCapture.label.settings), "Settings")
        try audit(app, "Settings")
    }

    func testWeather() throws {
        let app = launchHome()
        tapWhenReady(app.buttons[ScreenshotCapture.Card.weather], "Weather card")
        let forecast = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", ScreenshotCapture.label.forecastAtNoon))
            .firstMatch
        waitForScreen(forecast, "Weather sheet")
        try audit(app, "Weather")
    }

    func testSession() throws {
        let app = launchHome()
        tapWhenReady(app.buttons.labeled(ScreenshotCapture.label.goAgain), "Repartir")
        waitForScreen(app.staticTexts.labeled(ScreenshotCapture.label.inProgress), "Session in progress")
        try audit(app, "Session")
    }

    func testWatchOuting() throws {
        let app = launchInCaptureMode(wrist: .watch)
        tapWhenReady(app.buttons.labeled(ScreenshotCapture.Wrist.watch.heroButton), "Hero outing button")
        waitForScreen(app.buttons.labeled(ScreenshotCapture.label.stopSession), "Mirrored outing")
        try audit(app, "Mirrored outing")
    }

    // MARK: - Plumbing

    private func launchHome() -> XCUIApplication {
        let app = launchInCaptureMode()
        waitForScreen(app.buttons[ScreenshotCapture.Card.streak], "Home")
        return app
    }

    private func openSummary() -> XCUIApplication {
        let app = launchHome()
        tapWhenReady(app.buttons.labeled(ScreenshotCapture.label.seeSummary), "Voir le bilan")
        // The link only shows once the Bilan has loaded (issues #348, #350).
        waitForScreen(app.buttons.labeled(ScreenshotCapture.label.seeInHealth), "Bilan")
        return app
    }

    /// Audits what is on screen, and fails once with every finding the
    /// baseline does not know — all of them, not just the first, so one CI run
    /// says everything there is to fix on that screen.
    ///
    /// Every finding, known or not, is also attached to the result as
    /// `a11y-<screen>.json`: `tools/accessibility_audit.sh --record` rebuilds the
    /// baseline from those.
    private func audit(_ app: XCUIApplication, _ screen: String) throws {
        let accepted = try AccessibilityAuditBaseline.accepted(on: screen)
        var findings: [String] = []
        try app.performAccessibilityAudit { issue in
            findings.append(AccessibilityAuditBaseline.finding(issue))
            return true
        }
        let report = XCTAttachment(data: try JSONEncoder().encode([screen: Set(findings).sorted()]))
        report.name = "a11y-\(screen).json"
        report.lifetime = .keepAlways
        add(report)

        let new = findings.filter { !accepted.contains($0) }
        XCTAssertTrue(
            new.isEmpty,
            "\(screen), \(new.count) new finding(s):\n" + new.map { "- \($0)" }.joined(separator: "\n")
        )
    }
}
