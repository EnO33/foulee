#if DEBUG
import Foundation

/// The one set of numbers every App Store capture is made of (issue #235).
///
/// Everything here is a constant or a pure function of a day offset counted
/// from `instant`, so two runs on two different days produce byte-identical
/// screens. Nothing reads `Date()`: the app's clock is
/// `@Dependency(\.date)`, the capture mode points it at `ScreenshotClock`, and
/// that clock reads `instant` — this constant is where the whole app's notion
/// of "now" comes from during a capture.
///
/// The values are also meant to hold together, because a store screenshot is
/// read closely: today's 42 minutes are the duration of today's session in the
/// résumé *and* the last point of the Minutes chart *and* what closes the hero
/// ring; the 34-day streak and the 41-day record are not written down anywhere,
/// they are what `StreakCalculator` derives from the seeded history
/// (`ScreenshotSeedTests` pins that).
enum ScreenshotSeed {
    /// Thursday 14 May 2026, 14:35 — an ordinary active weekday, mid-afternoon,
    /// after the walk window has closed, so the hero card shows the finished
    /// state ("Sortie terminée") rather than a countdown.
    ///
    /// Built from wall-clock components in `Calendar.current` rather than from
    /// an absolute timestamp: what has to be reproducible is the *displayed*
    /// date, and a fixed timestamp would render as a different day and hour on
    /// a machine in another time zone.
    static let instant: Date = {
        let components = DateComponents(year: 2026, month: 5, day: 14, hour: 14, minute: 35)
        return Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 1_778_855_700)
    }()

    static var calendar: Calendar { .current }

    /// Start of the seeded day — the anchor every generated series counts back
    /// from.
    static var today: Date { calendar.startOfDay(for: instant) }

    /// `offset` days before the seeded today (0 = today).
    static func day(offset: Int) -> Date {
        calendar.date(byAdding: .day, value: -offset, to: today) ?? today
    }

    // MARK: - Preferences

    static let stepsGoal = 10_000
    static let minutesGoal = 30
    static let hydrationGoalML = 2_000
    static let hydrationGlassML = 250

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

    /// 1,5 L of a 2 L goal — six glasses, a visibly unfinished ring, and a
    /// reason for the "J'ai bu" button to still be worth tapping.
    static let waterML = 1_500

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

    /// What the session-in-progress capture shows: 18 min 24 s of a 30 min
    /// goal (a 61 % ring), 2 480 steps, 1,83 km, 24 m of climb.
    ///
    /// `sessionElapsed` is not a number the session screen is told — it is the
    /// offset `ScreenshotClock` is advanced to when the pedometer double emits,
    /// so `ActiveWalkStore` computes it exactly as it does in production.
    static let sessionElapsed: TimeInterval = 18 * 60 + 24
    static let sessionSteps = 2_480
    static let sessionDistanceMeters = 1_830.0
    static let sessionElevationMeters = 24.0

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
