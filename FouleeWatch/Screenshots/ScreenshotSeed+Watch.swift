#if DEBUG
import Foundation

/// The two screens' worth of seeded state the watch capture needs, assembled
/// from the shared constants (issue #239).
///
/// Assembled, not invented: every number below comes from
/// `Foulee/Screenshots/ScreenshotSeedCore.swift`, the file both apps compile.
/// That is the whole point — the streak on the wrist board and the streak on
/// the phone board are one constant, so they cannot drift apart between two
/// captures of the same release.
extension ScreenshotSeed {
    /// What `WatchTodayStore` serves in capture mode. A struct rather than six
    /// loose constants so the store's seeded path is one assignment block, and
    /// so a test can compare the store against the seed field by field.
    struct WatchToday {
        var steps: Int
        var minutes: Int
        var distanceKm: Double
        var calories: Int
        var streak: Int
        var stepsGoal: Int
        var minutesGoal: Int
        var waterML: Int
        var hydrationGoalML: Int
        var hydrationGlassML: Int
    }

    /// The seeded day, as the watch home shows it: 8 240 pas de 10 000, 42 min
    /// de 30, 6,1 km, 386 kcal, une série de 34 jours et 1,5 L de 2 L.
    ///
    /// The streak is the phone's `currentStreak` — on the watch it is a synced
    /// value, not something the wrist derives, so capture mode reads it where
    /// the phone's `StreakCalculator` would land.
    static var watchToday: WatchToday {
        WatchToday(
            steps: todaySteps,
            minutes: todayMinutes,
            distanceKm: todayDistanceKm,
            calories: todayCalories,
            streak: currentStreak,
            stepsGoal: stepsGoal,
            minutesGoal: minutesGoal,
            waterML: waterML,
            hydrationGoalML: hydrationGoalML,
            hydrationGlassML: hydrationGlassML
        )
    }

    /// The live session the third capture shows: 18:24 écoulées, 2 480 pas,
    /// 1,83 km, 136 kcal, 118 bpm. The same session the phone's `03_session`
    /// board shows, plus the two counters only the wrist can measure.
    static var watchSessionMetrics: WatchWorkoutMetrics {
        WatchWorkoutMetrics(
            elapsed: sessionElapsed,
            steps: sessionSteps,
            distanceMeters: sessionDistanceMeters,
            activeCalories: sessionCalories,
            heartRate: sessionHeartRate
        )
    }
}
#endif
