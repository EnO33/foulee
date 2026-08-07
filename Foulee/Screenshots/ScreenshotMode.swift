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
/// **Every store a capture run can reach is diverted or muted**, and the list
/// is exhaustive on purpose, because "it writes nothing" was once claimed here
/// while the run was quietly publishing its fabricated counters into the real
/// widget app group:
///
/// * Santé — `ScreenshotDoubles.healthKit` implements `saveWorkout` and
///   `logWater` as no-ops, so capturing a session records nothing. Nothing
///   under `Foulee/Screenshots/` names HealthKit at all, which is what
///   `ScreenshotModeTests` checks rather than takes on trust.
/// * The app's own preferences — read from `preferencesDefaults`, a throwaway
///   suite, never the app's default store.
/// * The widget app group — `SharedStore.activeSuiteName` is pointed at a
///   second throwaway suite below. Two refreshes write there on a normal run.
/// * The Watch — `PhoneWatchSync` is muted, so the seeded streak never leaves
///   the phone.
/// * The network — the weather, location and Connect IQ doubles talk to
///   nobody.
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

    /// The throwaway suite the seeded preferences live in.
    static let preferencesSuite = "com.eno33.foulee.screenshots"

    /// The throwaway suite the app-group snapshot is diverted into. A separate
    /// domain from the preferences one so a capture leaves the two kinds of
    /// state as separate as the app keeps them.
    static let sharedStoreSuite = "com.eno33.foulee.screenshots.appgroup"

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
        // Everything this mode does hangs off a throwaway suite. Without one
        // there is nowhere safe to seed, so the mode stays off rather than
        // falling back on the app's own store: a capture that doesn't happen
        // is recoverable, a polluted install is not.
        guard let defaults = UserDefaults(suiteName: preferencesSuite) else { return }
        isActive = true
        preferencesDefaults = seededDefaults(
            defaults,
            hasCompletedOnboarding: !arguments.contains(onboardingArgument)
        )
        divertSharedWrites()
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

    /// Send every write that would otherwise leave this process into a
    /// throwaway domain, or nowhere at all.
    ///
    /// Separate from `activateIfRequested` so the test that proves a capture
    /// run leaves the real app group alone can drive exactly this, without
    /// activating the mode in the test host (which would make the "a normal
    /// launch stays off" assertions depend on test ordering).
    ///
    /// The app-group suite is wiped like the preferences one, and for the same
    /// reason: a snapshot left by the previous run is state the next one did
    /// not compute.
    static func divertSharedWrites() {
        SharedStore.activeSuiteName = sharedStoreSuite
        UserDefaults(suiteName: sharedStoreSuite)?
            .removePersistentDomain(forName: sharedStoreSuite)
        PhoneWatchSync.isMuted = true
    }

    /// Seed `defaults` with exactly the preferences `ScreenshotSeed` describes.
    /// Wiped first: a suite that survived a previous capture run would carry
    /// whatever that run left behind (a theme toggled on camera, a finished
    /// onboarding) into the next one.
    ///
    /// Seeded through `UserPreferences` rather than by writing raw keys, so the
    /// defaults keys stay spelled in exactly one place.
    private static func seededDefaults(
        _ defaults: UserDefaults,
        hasCompletedOnboarding: Bool
    ) -> UserDefaults {
        defaults.removePersistentDomain(forName: preferencesSuite)
        ScreenshotSeed.seed(
            UserPreferences(defaults: defaults),
            hasCompletedOnboarding: hasCompletedOnboarding
        )
        return defaults
    }
}
#endif
