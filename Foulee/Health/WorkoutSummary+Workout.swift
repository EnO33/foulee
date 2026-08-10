import HealthKit

extension WorkoutSummary {
    /// Map an `HKWorkout` to the view-facing summary. For sessions Foulée
    /// recorded on the phone, steps / distance come from our own metadata (we
    /// don't write those as samples — they'd double-count the daily totals);
    /// for sessions from other sources (Watch, Apple Workouts) they fall back
    /// to the workout's statistics. Energy goes the other way round — see
    /// below. Elevation gain comes from the standard
    /// `HKMetadataKeyElevationAscended` metadata (0 when not recorded).
    init(workout: HKWorkout) {
        let metadata = workout.metadata
        let distanceMeters = (metadata?[FouleeWorkoutMetadata.distanceMeters] as? Double)
            ?? workout
                .statistics(for: HKQuantityType(.distanceWalkingRunning))?
                .sumQuantity()?
                .doubleValue(for: .meter())
            ?? 0
        // Energy is the one field where the order is measurement first,
        // metadata second — the reverse of distance above (issue #223).
        //
        // Our metadata number is not a measurement: it is
        // `WalkSession.estimatedCalories`, kilocalories-per-step times steps.
        // Preferring it over a real `activeEnergyBurned` total meant an
        // estimate could overwrite something HealthKit actually measured, and
        // the estimate is stored in the workout forever. In practice this
        // changes nothing for the sessions already in Santé: the phone writes
        // no energy samples at all (see `HealthKitClient+Live`), so a workout
        // carrying our metadata has no statistics to prefer and falls straight
        // through to the same value it has always shown. It only decides the
        // case where both exist — where the measurement is the better answer.
        let kcal = workout
            .statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?
            .doubleValue(for: .kilocalorie())
            ?? (metadata?[FouleeWorkoutMetadata.calories] as? Int).map(Double.init)
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
            sourceName: workout.sourceRevision.source.name,
            // Already on the workout, and read at last (issue #245): the type
            // was available here all along, it simply went nowhere.
            activity: RecordedActivity(workout.workoutActivityType)
        )
    }
}
