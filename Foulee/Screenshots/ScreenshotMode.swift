#if DEBUG
import Dependencies
import Foundation

/// Deterministic capture mode for the App Store screenshots (issue #235).
///
/// **This whole file — and every other file under `Foulee/Screenshots/` — is
/// wrapped in `#if DEBUG`.** A Release build compiles none of it: the type does
/// not exist, so neither the launch-argument check nor the doubles can be
/// reached, whatever the process is launched with. The call site in `FouleeApp`
/// carries the same guard. That is the first of the two locks; the second is
/// the launch argument below, which a normal launch never carries.
///
/// What it does, once both locks are open: install a fixed clock and a set of
/// read-only dependency doubles (`ScreenshotDoubles`) whose values come from
/// `ScreenshotSeed`, and hand `RootView` a throwaway `UserDefaults` suite so a
/// capture run cannot disturb the developer's own preferences.
///
/// It writes nothing anywhere — not to HealthKit, not to `UserDefaults.standard`,
/// not to the network. `ScreenshotDoubles.healthKit` implements `saveWorkout`
/// and `logWater` as no-ops precisely so capturing a running session records
/// nothing.
@MainActor
enum ScreenshotMode {
    /// The argument the capture target passes on launch. Distinctive on
    /// purpose: the `Foulee` prefix keeps it out of the way of Apple's own
    /// `-AppleLanguages`-style switches.
    ///
    /// Duplicated as a string literal in the `FouleeScreenshots` UI-test target
    /// — a UI test drives a separate process and cannot import app code.
    /// `ScreenshotModeTests` pins the two spellings together.
    static let launchArgument = "-FouleeScreenshotMode"

    /// Second, optional argument: seed the preferences as a *fresh install* so
    /// the onboarding flow is what `RootView` renders. Without it the seeded
    /// install has finished onboarding and the app opens on Aujourd'hui.
    static let onboardingArgument = "-FouleeScreenshotOnboarding"

    /// Whether `arguments` asks for the capture mode. Pure and parameterised so
    /// the "a normal launch does not activate it" test can assert on the real
    /// `ProcessInfo` arguments *and* on hand-built ones.
    static func isRequested(arguments: [String]) -> Bool {
        arguments.contains(launchArgument)
    }

    /// Whether the current process activated the mode. Read by the test that
    /// proves a normal launch leaves it off.
    private(set) static var isActive = false

    /// The suite `RootView` must read its `UserPreferences` from, or `nil` when
    /// the mode is off — in which case the app uses `.standard`, as always.
    private(set) static var preferencesDefaults: UserDefaults?

    /// Called first thing in `FouleeApp.init()`, before any `@Dependency` is
    /// resolved: `prepareDependencies` only takes effect while nothing has read
    /// the value it overrides yet.
    ///
    /// Idempotent — SwiftUI can construct `FouleeApp` more than once, and a
    /// second `prepareDependencies` pass would trap.
    static func activateIfRequested(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        guard !isActive, isRequested(arguments: arguments) else { return }
        isActive = true
        preferencesDefaults = seededDefaults(
            hasCompletedOnboarding: !arguments.contains(onboardingArgument)
        )
        prepareDependencies { values in
            // Every date the app shows is derived from this one clock, so the
            // capture reads the same day whatever day it is run on. The only
            // thing that ever moves it is the session double
            // (`ScreenshotDoubles.pedometer`), and it moves it to a fixed
            // offset — see `ScreenshotClock`.
            values.date = DateGenerator { ScreenshotClock.shared.now }
            values.healthKit = ScreenshotDoubles.healthKit
            values.weather = ScreenshotDoubles.weather
            values.location = ScreenshotDoubles.location
            values.notifications = ScreenshotDoubles.notifications
            values.garminConnectIQ = ScreenshotDoubles.garminConnectIQ
            values.pedometer = ScreenshotDoubles.pedometer
            values.altimeter = ScreenshotDoubles.altimeter
        }
    }

    /// A throwaway suite holding exactly the preferences `ScreenshotSeed`
    /// describes. Wiped first: a suite that survived a previous capture run
    /// would carry whatever that run left behind (a theme toggled on camera, a
    /// finished onboarding) into the next one.
    ///
    /// Seeded through `UserPreferences` rather than by writing raw keys, so the
    /// defaults keys stay spelled in exactly one place.
    private static func seededDefaults(hasCompletedOnboarding: Bool) -> UserDefaults {
        let suite = "com.eno33.foulee.screenshots"
        guard let defaults = UserDefaults(suiteName: suite) else { return .standard }
        defaults.removePersistentDomain(forName: suite)
        ScreenshotSeed.seed(
            UserPreferences(defaults: defaults),
            hasCompletedOnboarding: hasCompletedOnboarding
        )
        return defaults
    }
}
#endif
