#if DEBUG
import Foundation

/// The phone half of the one set of numbers every App Store capture is made of
/// (issue #235) — everything that names a model type, and therefore everything
/// the watch target cannot compile. The constants themselves live in
/// `ScreenshotSeedCore.swift`, which both apps build; the history that derives
/// from them lives in `ScreenshotSeed+History.swift`.
///
/// Everything is a constant or a pure function of a day offset counted from
/// `instant`, so two runs on two different days produce byte-identical screens.
/// Nothing reads `Date()`: the app's clock is `@Dependency(\.date)`, the capture
/// mode points it at `ScreenshotClock`, and that clock reads `instant`.
///
/// The values are also meant to hold together, because a store screenshot is
/// read closely: today's 42 minutes are the duration of today's session in the
/// résumé *and* the last point of the Minutes chart *and* what closes the hero
/// ring; the 34-day streak and the 41-day record are not written down anywhere,
/// they are what `StreakCalculator` derives from the seeded history
/// (`ScreenshotSeedTests` pins that).
extension ScreenshotSeed {
    // MARK: - Preferences

    /// The install the captures show: goals met by a regular user, hydration
    /// on, reminders on, light theme, « les deux » as the activity mode.
    ///
    /// The theme is pinned rather than left on `.system` on purpose — otherwise
    /// the whole set flips to dark the day the simulator is in dark mode.
    ///
    /// `.both` is likewise deliberate (#222/#224): it is the mode that names no
    /// activity in Réglages, and it makes « Démarrer ta sortie » open the
    /// marche/course picker, which is a screen worth showing.
    @MainActor
    static func seed(_ preferences: UserPreferences, hasCompletedOnboarding: Bool) {
        preferences.hasCompletedOnboarding = hasCompletedOnboarding
        preferences.themeMode = .light
        preferences.activityMode = .both
        preferences.activeDays = Weekday.workWeek
        preferences.walkWindowStart = TimeOfDay(hour: 12, minute: 0)
        preferences.walkWindowEnd = TimeOfDay(hour: 13, minute: 30)
        preferences.minutesGoal = minutesGoal
        preferences.stepsGoal = stepsGoal
        preferences.notificationsEnabled = true
        preferences.hydrationEnabled = true
        preferences.hydrationGoalML = hydrationGoalML
        preferences.hydrationGlassML = hydrationGlassML
        preferences.hydrationRemindersEnabled = true
        preferences.hydrationWindowStart = TimeOfDay(hour: 9, minute: 0)
        preferences.hydrationWindowEnd = TimeOfDay(hour: 21, minute: 0)
        preferences.hydrationIntervalMinutes = 120
        preferences.hydrationSnoozeMinutes = 15
    }

    // MARK: - Today

    /// Today's counters. Every field is derived from the same history the
    /// streak and the charts are, so the hero ring, the stat grid and the
    /// Minutes chart cannot disagree: 8 240 steps of a 10 000 goal (a day still
    /// running), 42 active minutes against a 30 min goal (hence "Fait").
    static var todayMetrics: HealthMetrics {
        HealthMetrics(
            steps: steps(offset: 0),
            distanceKm: distanceKm(offset: 0),
            activeMinutes: minutes(offset: 0),
            activeCalories: calories(offset: 0)
        )
    }

    static let weather = WeatherSnapshot(
        temperatureCelsius: 21,
        condition: "Ensoleillé",
        advice: "idéal"
    )

    // MARK: - Garmin

    /// A Garmin watch is present *and* so is Apple Watch data, which is what
    /// keeps `GarminFreshness` from raising the "Ouvre Garmin Connect" hint
    /// over the hero card — a troubleshooting banner has no place in a store
    /// screenshot, and suppressing it by faking a fresh sync would still leave
    /// the verdict clock-dependent.
    static var garminStatus: GarminStatus {
        GarminStatus(
            hasGarminSource: true,
            hasAppleWatchData: true,
            latestGarminSample: instant.addingTimeInterval(-25 * 60)
        )
    }

    static let garminDevices = [
        GarminDevice(
            id: UUID(uuidString: "6A8E17E0-0000-4000-8000-000000000001") ?? UUID(),
            modelName: "Forerunner 965",
            friendlyName: "Ma Forerunner"
        )
    ]

    // MARK: - Running session

    /// A short stroll along the Seine, for the session's route map. Fixed
    /// points, emitted once — nothing here follows real movement.
    static let route = [
        Coordinate(latitude: 48.8570, longitude: 2.3400),
        Coordinate(latitude: 48.8578, longitude: 2.3427),
        Coordinate(latitude: 48.8589, longitude: 2.3451),
        Coordinate(latitude: 48.8601, longitude: 2.3468),
        Coordinate(latitude: 48.8612, longitude: 2.3492)
    ]

    /// Paris, so the weather double is reached (`TodayStore` only fetches the
    /// forecast once the location client answers).
    static let coordinate = Coordinate(latitude: 48.8566, longitude: 2.3522)
}
#endif
