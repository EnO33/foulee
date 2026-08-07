import XCTest

/// Drives the app in capture mode and photographs every screen of the App Store
/// set (issue #235). Names match `appstore-screenshots/iphone-6.9/`, minus the
/// composition — the marketing frames are the composer's job, not this one's.
///
/// Two tests, so two launches: the onboarding capture needs an install that has
/// *not* finished onboarding, which is a launch-time decision. Everything else
/// is one pass through a single launch, in the cheapest navigation order —
/// the file numbers below are the store's ordering, not the capture's.
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

    // MARK: - 01 — Onboarding

    func testCaptureOnboarding() {
        let app = launchInCaptureMode(onboarding: true)
        waitForScreen(app.buttons["Commencer"], "Onboarding welcome step")
        capture("01_onboarding")
    }

    // MARK: - 02 … 10 — the app itself

    func testCaptureMainScreens() throws {
        let app = launchInCaptureMode()
        let streakCard = app.buttons[ScreenshotCapture.Card.streak]
        waitForScreen(streakCard, "Home")

        capture("02_home")
        captureStreak(app)
        captureMetric(app, metric: "steps", name: "05_stats")
        captureMetric(app, metric: "minutes", name: "06_minutes")
        captureHydration(app)
        captureSummary(app)
        captureSettings(app)
        captureWeather(app)
        // Last on purpose: it is the only step that leaves the home, starts a
        // session and moves the capture clock, so nothing after it has to be
        // reasoned about.
        captureSession(app)
    }

    // MARK: - Steps

    private func captureStreak(_ app: XCUIApplication) {
        tapWhenReady(app.buttons[ScreenshotCapture.Card.streak], "Streak card")
        waitForScreen(app.staticTexts["SÉRIE ACTUELLE"], "Streak calendar sheet")
        capture("04_streak")
        close(app)
    }

    private func captureMetric(_ app: XCUIApplication, metric: String, name: String) {
        tapWhenReady(app.buttons[ScreenshotCapture.Card.metric(metric)], "\(metric) card")
        waitForScreen(app.staticTexts["STATISTIQUES"], "\(metric) stats screen")
        capture(name)
        close(app)
    }

    /// The hydration card lives below the fold, so this one is the home
    /// scrolled down — exactly what the current `07_hydration` shows.
    ///
    /// Scrolled all the way to the *bottom* rather than to the card: the bottom
    /// is a clamped position, identical on every run whatever the swipe
    /// momentum did, and it frames the hydration card with the week bars under
    /// it. Then back to the top, because the next captures start from there.
    private func captureHydration(_ app: XCUIApplication) {
        for _ in 0..<Self.scrollSwipes { app.swipeUp(velocity: .fast) }
        waitForScreen(app.buttons["J'ai bu un verre"], "Hydration card")
        settleAfterScrolling()
        capture("07_hydration")
        for _ in 0..<Self.scrollSwipes { app.swipeDown(velocity: .fast) }
    }

    private func captureSummary(_ app: XCUIApplication) {
        tapWhenReady(app.buttons["Voir le résumé"], "Voir le résumé")
        waitForScreen(app.staticTexts["AUJOURD'HUI"], "Résumé 7 jours")
        capture("08_summary")
        close(app)
    }

    private func captureSettings(_ app: XCUIApplication) {
        tapWhenReady(app.buttons["Profil et réglages"], "Profile button")
        waitForScreen(app.staticTexts["Préférences"], "Settings")
        capture("09_settings")
        close(app)
    }

    private func captureWeather(_ app: XCUIApplication) {
        tapWhenReady(app.buttons[ScreenshotCapture.Card.weather], "Weather card")
        waitForScreen(app.staticTexts["Prévision à 12 h à ton emplacement"], "Weather sheet")
        capture("10_weather")
        close(app)
    }

    /// « Les deux » is the seeded mode, so starting a session asks which one
    /// first (#224). Answering « Marche » is what puts the timer on screen;
    /// nothing is written to Santé — the capture doubles' `saveWorkout` is a
    /// no-op, and this run never stops the session anyway.
    private func captureSession(_ app: XCUIApplication) {
        tapWhenReady(app.buttons["Repartir"], "Repartir")
        // The picker's rows carry an explicit accessibility label
        // ("Démarrer marche"), not the visible "Marche" of their `Text`.
        tapWhenReady(app.buttons["Démarrer marche"], "Activity picker")
        waitForScreen(app.staticTexts["EN COURS"], "Session in progress")
        capture("03_session")
    }

    private func close(_ app: XCUIApplication) {
        tapWhenReady(app.buttons["Fermer"].firstMatch, "Close button")
    }
}
