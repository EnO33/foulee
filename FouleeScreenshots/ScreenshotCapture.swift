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

        /// The hero's button for that outing (`TodayHeroCard`).
        var heroButton: String {
            switch self {
            case .watch: ScreenshotCapture.label.heroWatch
            case .garmin: ScreenshotCapture.label.heroGarmin
            }
        }
    }

    /// The language of the run: French unless `tools/capture_screenshots.sh
    /// --language en` asked for the English boards (issue #592).
    static let isEnglish = ProcessInfo.processInfo.environment["FOULEE_CAPTURE_LANGUAGE"] == "en"

    /// Pinned whatever the host runs (issue #408): a simulator left in English
    /// groups thousands as « 8,240 » on the French boards. CI runners are in
    /// English; a developer's Mac usually is not, which is why the difference
    /// went unseen until the captures moved to CI.
    static let localeArguments = (isEnglish
        ? ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        : ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"]) + pseudoArguments

    /// Set by `tools/capture_screenshots.sh --pseudo` (issue #594): Xcode's
    /// double-length pseudo-language, which writes every localized string twice
    /// — « Get started Get started » — to show what a longer translation would
    /// truncate. For the layout review only, never for the store boards.
    ///
    /// It doubles the format, not the result: « Session under way on @ Session
    /// under way on your Watch your Watch ». No exact label survives that, so
    /// the run looks elements up with `labeled(_:)`.
    static let isPseudo = ProcessInfo.processInfo.environment["FOULEE_CAPTURE_PSEUDO"] == "1"

    static let pseudoArguments = isPseudo ? ["-NSDoubleLocalizedStrings", "YES"] : []

    /// Set by `tools/capture_screenshots.sh --text-size` with an accessibility
    /// size (issue #597): the home then runs well past the screen, and the card
    /// a step taps may sit below the fold, not yet built by its lazy stack.
    static let isAccessibilityTextSize = ProcessInfo.processInfo
        .environment["FOULEE_CAPTURE_TEXT_SIZE"]?.hasPrefix("accessibility") == true

    /// The words the run finds its way by, in the run's language: the app's
    /// own strings, as `Foulee/Resources/Localizable.xcstrings` translates them.
    static let label = isEnglish ? Labels.english : Labels.french

    struct Labels {
        let start, heroWatch, heroGarmin, currentStreak, seeInHealth, stopSession: String
        let statistics, drankGlass, hydration, glassByGlass, seeSummary: String
        let walkAndRun, portions, settings, inProgress, goAgain, close: String
        /// The weather sheet's heading up to the hour: the rest is « 12:00 »
        /// in French and « 12:00 PM » in the US, with a narrow no-break space.
        let forecastAtNoon: String

        static let french = Labels(
            start: "Commencer", heroWatch: "Séance en cours sur ta Watch",
            heroGarmin: "Séance en cours sur ta Garmin", currentStreak: "SÉRIE ACTUELLE",
            seeInHealth: "Voir dans Santé", stopSession: "Arrêter la séance",
            statistics: "STATISTIQUES", drankGlass: "J'ai bu un verre", hydration: "Hydratation",
            glassByGlass: "Verre par verre", seeSummary: "Voir le bilan", walkAndRun: "Marche et course",
            portions: "PORTIONS", settings: "Réglages", inProgress: "EN COURS", goAgain: "Repartir",
            close: "Fermer", forecastAtNoon: "Prévision à 12:00 "
        )

        static let english = Labels(
            start: "Get started", heroWatch: "Session under way on your Watch",
            heroGarmin: "Session under way on your Garmin", currentStreak: "CURRENT STREAK",
            seeInHealth: "See in Health", stopSession: "Stop the session",
            statistics: "STATISTICS", drankGlass: "I had a glass", hydration: "Hydration",
            glassByGlass: "Glass by glass", seeSummary: "See the recap", walkAndRun: "Walk and run",
            portions: "PARTS", settings: "Settings", inProgress: "IN PROGRESS", goAgain: "Go again",
            close: "Close", forecastAtNoon: "Forecast at 12:00"
        )
    }

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

extension XCUIElementQuery {
    /// The element showing `label`: that exact label, or under the
    /// pseudo-language one that contains it (`ScreenshotCapture.isPseudo`).
    func labeled(_ label: String) -> XCUIElement {
        guard ScreenshotCapture.isPseudo else { return self[label] }
        return matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }
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
        if ScreenshotCapture.isAccessibilityTextSize { scrollIntoView(element) }
        XCTAssertTrue(
            element.waitForExistence(timeout: ScreenshotCapture.timeout),
            "\(description) never appeared"
        )
        element.tap()
    }

    /// Swipe until `element` can be tapped: down the screen first, then back
    /// up, since the previous step may have left it scrolled. Review runs only
    /// — a store board must not depend on where a swipe's momentum stopped.
    private func scrollIntoView(_ element: XCUIElement) {
        let app = XCUIApplication()
        _ = element.waitForExistence(timeout: 1)
        for _ in 0..<6 {
            if element.exists, element.isHittable { return }
            app.swipeUp()
        }
        for _ in 0..<12 {
            if element.exists, element.isHittable { return }
            app.swipeDown()
        }
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
