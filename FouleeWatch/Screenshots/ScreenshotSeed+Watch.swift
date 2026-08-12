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
    ///
    /// Since issue #250 the board also names what is being done right now: a
    /// **run**, detected inside a session started as a walk, which is the
    /// feature the wrist screen exists to show.
    ///
    /// `activityTotals` is **derived from the legs**, not left empty and not
    /// invented (issue #299).
    ///
    /// It was empty, and the justification had gone stale in a way that made
    /// the board *shorter than the app*. The comment invoked issue #256 —
    /// « nothing segments a session, so there is nothing to total » — but
    /// issue #265 brought the legs back, and `applyOutingTotals` now fills this
    /// on **every** ingest, leg in flight included. So the breakdown
    /// is true from the first second on a wrist, the `countersText` line exists
    /// in real life, and the 40 mm probe was measuring a page that did not have
    /// it. Two « it fits with room to spare » conclusions rest on that
    /// measurement.
    ///
    /// Derived rather than written out, so it cannot drift from the legs it is
    /// supposed to total: this is exactly what the store computes for the sport
    /// being done.
    ///
    /// The opposite failure is still the one to avoid. The seed once carried a
    /// third of each figure and the composed board advertised a breakdown the
    /// app could not produce — a picture of a feature that did not exist. The
    /// rule has not changed, only which side of it the truth is on.
    static var watchSessionMetrics: WatchWorkoutMetrics {
        WatchWorkoutMetrics(
            elapsed: sessionElapsed,
            steps: sessionSteps,
            distanceMeters: sessionDistanceMeters,
            activeCalories: sessionCalories,
            heartRate: sessionHeartRate,
            activity: .running,
            activityTotals: WatchActivityTotals.of(.running, in: sessionLegs, at: instant),
            // The board must show the line the app shows (issue #299 taught
            // that the hard way). Derived from the run leg — 830 m in 380 s is
            // 7'37"/km — then quantised to five seconds the way a live figure
            // is, so the planche cannot claim a resolution the screen does not.
            recentPace: paceText(secondsPerKm: sessionRunElapsed / (830 / 1_000), roundedTo: 5),
            legs: sessionLegs
        )
    }

    /// The two legs the « Jambes » page shows (issue #276): a walk of 12:04 that
    /// became a run of 06:20 — the outing the detection exists to recognise, and
    /// the one that leaves two records in Santé since issue #265.
    ///
    /// **They add up to the totals above, exactly.** 1 650 + 830 = 2 480 pas,
    /// 1 000 + 830 = 1 830 m, 60 + 48 = 108 kcal, 12:04 + 06:20 = 18:24. A
    /// viewer who checks the arithmetic on the board must find it right; a
    /// listing that does not add up is one a reviewer can notice.
    ///
    /// **Frozen, in three ways that all matter:**
    ///
    /// - The identifiers are literals, not `UUID()`. Two capture runs must
    ///   produce byte-identical boards.
    /// - The dates are offsets from `ScreenshotSeed.instant`, the same fixed
    ///   afternoon every other seeded value counts from — never the wall clock.
    /// - **Neither leg is in flight** (`end` is non-nil on both). A running leg
    ///   measures itself against the instant it is drawn, which would make the
    ///   board depend on when the shutter fired and break the equality
    ///   `WatchScreenshotModeTests` asserts. The cost is a small infidelity —
    ///   during a real outing the newest leg *is* still running — and it is
    ///   invisible on a still photograph.
    static var sessionLegs: [WatchWorkoutSegment] {
        let end = instant
        let boundary = end.addingTimeInterval(-sessionRunElapsed)
        let start = boundary.addingTimeInterval(-sessionWalkElapsed)
        return [
            WatchWorkoutSegment(
                id: legID(1),
                activity: .walking,
                start: start,
                end: boundary,
                steps: 1_650,
                distanceMeters: 1_000,
                activeCalories: 60
            ),
            WatchWorkoutSegment(
                id: legID(2),
                activity: .running,
                start: boundary,
                end: end,
                steps: 830,
                distanceMeters: 830,
                activeCalories: 48
            )
        ]
    }

    /// 12:04 of walking then 06:20 of running — `sessionElapsed` split in two.
    private static let sessionWalkElapsed: TimeInterval = 12 * 60 + 4
    private static let sessionRunElapsed: TimeInterval = 6 * 60 + 20

    /// Same shape as the phone seed's identifiers, and constant for the same
    /// reason. The `?? UUID()` is unreachable for a literal this well-formed;
    /// `seededLegsAreStable` is what says so out loud.
    private static func legID(_ index: Int) -> UUID {
        UUID(uuidString: "1E600000-0000-4000-8000-\(String(format: "%012d", index))") ?? UUID()
    }
}
#endif
