import HealthKit

/// Which workout activity types the 7-day résumé reports on.
///
/// Read-side filter only, and the single one in the app: streak, ring,
/// widgets and complications all count `appleExerciseTime` and never look
/// at an activity type. Until #217 this filter was `.walking` alone, so a
/// runner saw a streak of 7 next to seven "aucune séance" placeholders —
/// the sheet contradicted what the app had just credited.
///
/// Deliberately *not* conditioned on the user's activity preference: the
/// résumé is a factual record of what was done, and those minutes already
/// validated the streak whatever the setting was. Filtering on the
/// preference would recreate the exact asymmetry that is the bug.
enum WorkoutActivityFilter {
    /// Walking, running and hiking. All three report their distance under
    /// `.distanceWalkingRunning`, so `WorkoutSummary.init(workout:)` maps
    /// them without a special case.
    static let summarizedActivityTypes: Set<HKWorkoutActivityType> = [
        .walking, .running, .hiking
    ]

    /// The whole predicate `recentWorkouts` hands to `HKSampleQuery`: an
    /// accepted activity type AND a start date inside the last `daysBack`
    /// days, today included.
    ///
    /// Composed here rather than at the call site on purpose. The bug was a
    /// single `.walking` literal next to `HKSampleQuery`, and a test can't
    /// reach into a private function in `HealthKitClient+Live.swift` — so
    /// asserting the accepted types alone let #217 come back in full with
    /// the suite green (measured). With the composition living here there is
    /// no activity knob left at the call site, and every clause the query
    /// actually runs is under test.
    ///
    /// `nil` when the calendar can't step `daysBack` days back; the caller
    /// reports that as "no workouts" rather than as a failure.
    static func recentWorkoutsPredicate(
        daysBack: Int,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> NSPredicate? {
        let startOfToday = calendar.startOfDay(for: now)
        guard let start = calendar.date(
            byAdding: .day, value: -(daysBack - 1), to: startOfToday
        ) else { return nil }

        return NSCompoundPredicate(andPredicateWithSubpredicates: [
            summarizedActivityPredicate,
            HKQuery.predicateForSamples(
                withStart: start,
                end: startOfToday.addingTimeInterval(24 * 60 * 60),
                options: .strictStartDate
            )
        ])
    }

    /// `HKQuery.predicateForWorkouts(with:)` accepts exactly one activity
    /// type, so a multi-type filter has to be an OR over one predicate per
    /// accepted type.
    private static var summarizedActivityPredicate: NSPredicate {
        NSCompoundPredicate(orPredicateWithSubpredicates:
            summarizedActivityTypes.map { HKQuery.predicateForWorkouts(with: $0) }
        )
    }
}
