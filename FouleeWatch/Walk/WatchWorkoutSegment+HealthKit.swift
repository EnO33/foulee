@preconcurrency import HealthKit

extension WatchWorkoutSegment {
    /// Read one `HKWorkoutActivity`.
    ///
    /// Fails for an activity Foulée does not record. That is not defensive
    /// padding: watchOS itself can add activities to a session, and a segment
    /// this app cannot name must be dropped rather than folded into one of the
    /// two — a mis-attributed segment is worse than a missing one, because the
    /// totals on screen would silently include time nobody spent walking.
    init?(_ activity: HKWorkoutActivity) {
        guard let sessionActivity = SessionActivity(activity.workoutConfiguration.activityType) else {
            return nil
        }
        self.init(
            id: activity.uuid,
            activity: sessionActivity,
            start: activity.startDate,
            end: activity.endDate,
            steps: Int(activity.sum(HKQuantityType(.stepCount), unit: .count())),
            distanceMeters: activity.sum(HKQuantityType(.distanceWalkingRunning), unit: .meter()),
            activeCalories: Int(activity.sum(HKQuantityType(.activeEnergyBurned), unit: .kilocalorie()))
        )
    }
}

private extension HKWorkoutActivity {
    /// « A dictionary of statistics per quantity type during the activity » —
    /// HealthKit totals each segment itself, over exactly the samples inside
    /// the segment's date interval. Nothing in Foulée re-adds them.
    func sum(_ type: HKQuantityType, unit: HKUnit) -> Double {
        statistics(for: type)?.sumQuantity()?.doubleValue(for: unit) ?? 0
    }
}
