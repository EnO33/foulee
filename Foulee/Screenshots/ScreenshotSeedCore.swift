#if DEBUG
import Foundation

/// The Foundation-only half of the capture seed — the half the **watch** target
/// compiles too (issues #235, #239).
///
/// The split exists for one reason. The watch's capture mode has to show the
/// same day as the phone's: a 34-day streak on the phone board and another
/// number on the wrist board, in the same App Store listing, is exactly what a
/// reviewer notices. Reusing the numbers means compiling the file that holds
/// them into `FouleeWatch`, and that target lists its sources one by one — it
/// can only take a file that names no phone type. So everything here is
/// `Foundation` and arithmetic.
///
/// Anything that mentions a model type (`HealthMetrics`, `UserPreferences`,
/// `WeatherSnapshot`, the seeded history and its series) stays in
/// `ScreenshotSeed.swift` / `ScreenshotSeed+History.swift`, which only the phone
/// target compiles. Those files extend this enum, so `ScreenshotSeed` reads as
/// one type on the phone whatever the file boundary.
///
/// Nothing here reads the wall clock: every value is a constant or a pure
/// function of a day offset counted from `instant`.
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

    // MARK: - Goals

    static let stepsGoal = 10_000
    static let minutesGoal = 30
    static let hydrationGoalML = 2_000
    static let hydrationGlassML = 250

    // MARK: - Today

    /// Today's step count. Below the goal on purpose: the day is still running
    /// at 14:35, and a ring already full on every count reads as a mock-up.
    static let todaySteps = 8_240

    /// Today's active minutes — 42 against a 30 min goal, hence "Fait". Also the
    /// first entry of the seeded history's pinned week, so the number on the
    /// watch home is the number the phone's charts and résumé draw.
    static let todayMinutes = 42

    /// 6,1 km — the steps above through the one step→metres conversion, not a
    /// second number.
    static var todayDistanceKm: Double { distanceKm(steps: todaySteps) }

    static var todayCalories: Int { calories(minutes: todayMinutes) }

    /// 1,5 L of a 2 L goal — six glasses, a visibly unfinished ring, and a
    /// reason for the "J'ai bu" button to still be worth tapping.
    static let waterML = 1_500

    // MARK: - Streak

    /// What the seeded history is *built* to produce. These two are not
    /// injected anywhere on the phone: `StreakCalculator` derives them from the
    /// seeded days, and `ScreenshotSeedTests` asserts it does. The watch has no
    /// history to derive from — it shows the streak the phone synced — so its
    /// capture mode reads `currentStreak` directly, which is what makes the two
    /// boards agree.
    static let currentStreak = 34
    static let bestStreak = 41

    // MARK: - Conversions

    /// Metres per step — the one conversion tying the steps series to the
    /// distance series, so 8 240 pas really is 6,1 km.
    private static let metresPerStep = 0.74

    static func distanceKm(steps: Int) -> Double {
        Double(steps) * metresPerStep / 1_000
    }

    static func calories(minutes: Int) -> Int {
        Int((140 + Double(minutes) * 5.85).rounded())
    }

    // MARK: - Session in progress

    /// What the session-in-progress captures show, on both devices: 18 min 24 s
    /// of a 30 min goal (a 61 % ring), 2 480 steps, 1,83 km, 24 m of climb.
    ///
    /// On the phone `sessionElapsed` is not a number the session screen is told
    /// — it is the offset `ScreenshotClock` is advanced to when the pedometer
    /// double emits, so `ActiveWalkStore` computes it exactly as it does in
    /// production. On the watch it is the elapsed time of the seeded metrics,
    /// because the live workout has no clock of its own to move.
    static let sessionElapsed: TimeInterval = 18 * 60 + 24
    static let sessionSteps = 2_480
    static let sessionDistanceMeters = 1_830.0
    static let sessionElevationMeters = 24.0

    /// Watch-only: the live session screen shows a calorie count and a heart
    /// rate the phone's has no sensor for. Kept beside the rest of the session
    /// numbers rather than in the watch folder — one place holds a session, and
    /// 136 kcal is what the seeded history's own rate (7,4 kcal per active
    /// minute) gives for 18,4 minutes.
    static let sessionCalories = 136
    static let sessionHeartRate = 118
}
#endif
