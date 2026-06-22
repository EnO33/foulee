import HealthKit

extension WorkoutSummary {
    /// Map an `HKWorkout` to the view-facing summary. For walks Foulée
    /// recorded, steps / distance / energy come from our own metadata (we don't
    /// write those as samples — they'd double-count the daily totals); for walks
    /// from other sources (Watch, Apple Workouts) they fall back to the
    /// workout's statistics. Elevation gain comes from the standard
    /// `HKMetadataKeyElevationAscended` metadata (0 when not recorded).
    init(workout: HKWorkout) {
        let metadata = workout.metadata
        let distanceMeters = (metadata?[FouleeWorkoutMetadata.distanceMeters] as? Double)
            ?? workout
                .statistics(for: HKQuantityType(.distanceWalkingRunning))?
                .sumQuantity()?
                .doubleValue(for: .meter())
            ?? 0
        let kcal = (metadata?[FouleeWorkoutMetadata.calories] as? Int).map(Double.init)
            ?? workout
                .statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?
                .doubleValue(for: .kilocalorie())
            ?? 0
        let steps = metadata?[FouleeWorkoutMetadata.steps] as? Int ?? 0
        let elevation = (metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?
            .doubleValue(for: .meter()) ?? 0
        self.init(
            id: workout.uuid,
            startedAt: workout.startDate,
            endedAt: workout.endDate,
            durationSeconds: workout.duration,
            distanceKm: distanceMeters / 1_000,
            activeCalories: Int(kcal),
            steps: steps,
            elevationMeters: elevation,
            sourceName: workout.sourceRevision.source.name
        )
    }
}
