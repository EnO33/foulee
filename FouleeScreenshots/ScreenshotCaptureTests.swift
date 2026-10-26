import XCTest

/// Drives the app in capture mode and photographs every screen of the App Store
/// set (issue #235). Names match `appstore-screenshots/iphone-6.9/`, minus the
/// composition — the marketing frames are the composer's job, not this one's.
///
/// Four tests, so four launches: the onboarding needs an install that has *not*
/// finished it, and the two mirror boards a wrist recording from the start —
/// both launch-time decisions. Everything else is one pass
/// through a single launch, in the cheapest navigation order — the file numbers
/// below are the store's ordering (issue #582), not the capture's.
///
/// Determinism does not depend on that order: every number on screen comes from
/// `ScreenshotSeed`, and the one clock move the run performs (starting a
/// session) is a fixed offset inside the same hour of the same pinned day.
final class ScreenshotCaptureTests: XCTestCase {
    /// Enough swipes to hit either end of the home's scroll view on any iPhone
    /// in the set. Overshooting is free — both ends clamp.
    private static let scrollSwipes = 4

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - Onboarding

    /// Captured for the review sets (issue #408), not boarded for the store:
    /// the composer's `shots` table decides what the listing shows.
    func testCaptureOnboarding() {
        let app = launchInCaptureMode(onboarding: true)
        waitForScreen(app.buttons["Commencer"], "Onboarding welcome step")
        capture("13_onboarding")
    }

    // MARK: - The app itself

    func testCaptureMainScreens() throws {
        let app = launchInCaptureMode()
        let streakCard = app.buttons[ScreenshotCapture.Card.streak]
        waitForScreen(streakCard, "Home")

        capture("01_home")
        captureStreak(app)
        captureMetric(app, metric: "steps", name: "09_stats")
        captureMetric(app, metric: "minutes", name: "11_minutes")
        captureHydration(app)
        captureSummary(app)
        captureSettings(app)
        captureWeather(app)
        // Last on purpose: it is the only step that leaves the home, starts a
        // session and moves the capture clock, so nothing after it has to be
        // reasoned about.
        captureSession(app)
    }

    // MARK: - An outing on the wrist

    /// One launch per watch: once a wrist is recording, the home offers that
    /// outing instead of « Repartir », which the main pass needs.
    func testCaptureWatchOuting() {
        captureWristOuting(.watch, name: "02_watch")
    }

    func testCaptureGarminOuting() {
        captureWristOuting(.garmin, name: "05_garmin")
    }

    // MARK: - Steps

    /// The streak badge opens the Bilan on the month in progress (#445): the
    /// streak at its head, the month's rings below.
    private func captureStreak(_ app: XCUIApplication) {
        tapWhenReady(app.buttons[ScreenshotCapture.Card.streak], "Streak badge")
        waitForScreen(app.staticTexts["SÉRIE ACTUELLE"], "Bilan streak")
        // The link only shows once the month has loaded.
        waitForScreen(app.buttons["Voir dans Santé"], "Bilan month")
        capture("06_streak")
        close(app)
    }

    /// The outing the wrist is recording, as the phone shows it: opened from
    /// the hero, which offers it in place of « Repartir ».
    private func captureWristOuting(_ wrist: ScreenshotCapture.Wrist, name: String) {
        let app = launchInCaptureMode(wrist: wrist)
        tapWhenReady(app.buttons[wrist.heroButton], "Hero outing button")
        waitForScreen(app.buttons["Arrêter la séance"], "Mirrored outing")
        capture(name)
    }

    private func captureMetric(_ app: XCUIApplication, metric: String, name: String) {
        tapWhenReady(app.buttons[ScreenshotCapture.Card.metric(metric)], "\(metric) card")
        waitForScreen(app.staticTexts["STATISTIQUES"], "\(metric) stats screen")
        capture(name)
        close(app)
    }

    /// The hydration screen, opened from its card below the fold: the
    /// drop, the quick servings, the glass-by-glass timeline and the week.
    ///
    /// The card is a tap target, not a button, so the tap lands on its title.
    /// The home is scrolled all the way down first — a clamped position, the
    /// same on every run whatever the swipe momentum did — and back to the top
    /// afterwards, because the next captures start from there.
    private func captureHydration(_ app: XCUIApplication) {
        for _ in 0..<Self.scrollSwipes { app.swipeUp(velocity: .fast) }
        waitForScreen(app.buttons["J'ai bu un verre"], "Hydration card")
        settleAfterScrolling()
        tapWhenReady(app.staticTexts["Hydratation"].firstMatch, "Hydration card title")
        waitForScreen(app.staticTexts["Verre par verre"], "Hydration screen")
        capture("08_hydration")
        close(app)
        for _ in 0..<Self.scrollSwipes { app.swipeDown(velocity: .fast) }
    }

    /// The Bilan on the current week, then today's outing in it: a walk that
    /// became a run, whose detail shows the two portions (issue #318).
    private func captureSummary(_ app: XCUIApplication) {
        tapWhenReady(app.buttons["Voir le bilan"], "Voir le bilan")
        // The link only shows once the Bilan has loaded (issues #348, #350).
        waitForScreen(app.buttons["Voir dans Santé"], "Bilan")
        capture("04_summary")
        tapWhenReady(app.staticTexts["Marche et course"].firstMatch, "Today's outing")
        waitForScreen(app.staticTexts["PORTIONS"], "Outing detail")
        capture("03_outing")
        // The detail is pushed over the Bilan, whose close button it hides.
        tapWhenReady(app.navigationBars.buttons.firstMatch, "Back to the Bilan")
        close(app)
    }

    private func captureSettings(_ app: XCUIApplication) {
        tapWhenReady(app.buttons["Réglages"], "Settings button")
        waitForScreen(app.staticTexts["Réglages"], "Settings")
        capture("12_settings")
        close(app)
    }

    private func captureWeather(_ app: XCUIApplication) {
        tapWhenReady(app.buttons[ScreenshotCapture.Card.weather], "Weather card")
        // The seeded walk window opens at 12:00, written the way the whole app
        // writes a time since #395 (`TimeOfDay.clockText`).
        waitForScreen(app.staticTexts["Prévision à 12:00 à ton emplacement"], "Weather sheet")
        capture("10_weather")
        close(app)
    }

    /// « Repartir » puts the timer on screen straight away: the phone stopped
    /// asking which activity in #246, even in « les deux » mode — detection
    /// decides. Nothing is written to Santé: the capture doubles'
    /// `saveWorkout` is a no-op, and this run never stops the session anyway.
    private func captureSession(_ app: XCUIApplication) {
        tapWhenReady(app.buttons["Repartir"], "Repartir")
        waitForScreen(app.staticTexts["EN COURS"], "Session in progress")
        capture("07_session")
    }

    private func close(_ app: XCUIApplication) {
        tapWhenReady(app.buttons["Fermer"].firstMatch, "Close button")
    }
}
