import HealthKit

extension WorkoutSummary {
    /// Map an `HKWorkout` to the view-facing summary. Distance + energy come
    /// from the workout's statistics; elevation gain from the standard
    /// `HKMetadataKeyElevationAscended` metadata (0 when the source didn't
    /// record it — e.g. older Foulée walks).
    init(workout: HKWorkout) {
        let distanceMeters = workout
            .statistics(for: HKQuantityType(.distanceWalkingRunning))?
            .sumQuantity()?
            .doubleValue(for: .meter()) ?? 0
        let kcal = workout
            .statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?
            .doubleValue(for: .kilocalorie()) ?? 0
        let elevation = (workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?
            .doubleValue(for: .meter()) ?? 0
        self.init(
            id: workout.uuid,
            startedAt: workout.startDate,
            endedAt: workout.endDate,
            durationSeconds: workout.duration,
            distanceKm: distanceMeters / 1_000,
            activeCalories: Int(kcal),
            elevationMeters: elevation,
            sourceName: workout.sourceRevision.source.name
        )
    }
}
