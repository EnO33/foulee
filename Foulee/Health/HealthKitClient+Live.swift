import Dependencies
import Foundation
import HealthKit

extension HealthKitClient {
    /// Real implementation backed by a single shared `HKHealthStore`.
    /// All four metrics are fetched in parallel from midnight to now.
    /// Satisfies the `DependencyKey.liveValue` requirement declared
    /// in `HealthKitClient.swift`.
    static let liveValue: HealthKitClient = {
        let store = HKHealthStore()

        let stepsType = HKQuantityType(.stepCount)
        let distanceType = HKQuantityType(.distanceWalkingRunning)
        let minutesType = HKQuantityType(.appleExerciseTime)
        let caloriesType = HKQuantityType(.activeEnergyBurned)
        let heartRateType = HKQuantityType(.heartRate)
        let walkingWorkoutType = HKWorkoutType.workoutType()
        let waterType = HKQuantityType(.dietaryWater)

        // Heart rate is read-only and only surfaces in WorkoutDetailSheet
        // (HR samples scoped to a single HKWorkout) — without it the
        // workoutDetail query fails with "Authorization not determined".
        // Water is read+write for the hydration tracker.
        let readTypes: Set<HKObjectType> = [
            stepsType, distanceType, minutesType, caloriesType,
            heartRateType, walkingWorkoutType, waterType
        ]
        let writeTypes: Set<HKSampleType> = [walkingWorkoutType, waterType]

        return HealthKitClient(
            requestAuthorization: {
                guard HKHealthStore.isHealthDataAvailable() else { return false }
                try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
                return true
            },
            todayMetrics: {
                async let steps = sumToday(store: store, type: stepsType, unit: .count())
                async let distanceMeters = sumToday(store: store, type: distanceType, unit: .meter())
                async let minutes = sumToday(store: store, type: minutesType, unit: .minute())
                async let calories = sumToday(store: store, type: caloriesType, unit: .kilocalorie())
                // Same max() as dailyMinutes (see ActiveMinutes): the hero
                // ring must move for a Garmin-only user, not just the streak.
                async let workoutMinutes = todayWorkoutMinutes(store: store)

                return try await HealthMetrics(
                    steps: Int(steps),
                    distanceKm: distanceMeters / 1_000,
                    activeMinutes: ActiveMinutes.merged(appleMinutes: Int(minutes), workoutMinutes: workoutMinutes),
                    activeCalories: Int(calories)
                )
            },
            saveWalkingWorkout: { session in
                guard let endedAt = session.endedAt else { return }
                let config = HKWorkoutConfiguration()
                config.activityType = .walking
                config.locationType = .outdoor

                let builder = HKWorkoutBuilder(
                    healthStore: store,
                    configuration: config,
                    device: .local()
                )

                try await builder.beginCollection(at: session.startedAt)

                // We deliberately don't write step / distance / energy *samples*
                // here. iOS already records steps and distance from the phone's
                // motion chip, so adding our own would *double-count* the daily
                // totals the Today screen sums back from HealthKit. And Apple
                // Exercise Time is system-computed — third-party apps can't write
                // it at all, so the old `appleExerciseTime` sample is exactly what
                // made `finishWorkout()` fail with an authorization error and drop
                // the whole walk. The system still credits exercise minutes for a
                // saved walking workout, so the streak (which reads exercise
                // minutes) keeps working.
                //
                // Instead we record the walk's own measured numbers as workout
                // *metadata* — metadata isn't summed into any daily total, so it
                // can't double-count, yet it lets the résumé/detail show real
                // values (see WorkoutSummary). Elevation uses the standard key.
                var metadata: [String: Any] = [
                    FouleeWorkoutMetadata.steps: session.steps,
                    FouleeWorkoutMetadata.distanceMeters: session.distanceMeters,
                    FouleeWorkoutMetadata.calories: session.estimatedCalories
                ]
                if session.elevationGainMeters > 0 {
                    metadata[HKMetadataKeyElevationAscended] =
                        HKQuantity(unit: .meter(), doubleValue: session.elevationGainMeters)
                }
                try await builder.addMetadata(metadata)

                try await builder.endCollection(at: endedAt)
                _ = try await builder.finishWorkout()
            },
            dailyMinutes: { daysBack in
                try await mergedDailyMinutes(store: store, minutesType: minutesType, daysBack: daysBack)
            },
            recentWorkouts: { daysBack in
                try await recentWalkingWorkouts(store: store, daysBack: daysBack)
            },
            workoutDetail: { summary in
                try await fetchWorkoutDetail(for: summary, store: store)
            },
            metricSeries: { metric, daysBack in
                try await metricCollection(store: store, metric: metric, daysBack: daysBack)
            },
            hourlyToday: { metric in
                try await metricHourlyToday(store: store, metric: metric)
            },
            observeChanges: {
                healthChangeStream(store: store, types: [stepsType, distanceType, minutesType, caloriesType])
            },
            observeWaterChanges: {
                healthChangeStream(store: store, types: [waterType])
            },
            logWater: { milliliters in
                let sample = HKQuantitySample(
                    type: waterType,
                    quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: Double(milliliters)),
                    start: .now,
                    end: .now
                )
                try await store.save(sample)
            },
            todayWaterML: {
                let milliliters = try await sumToday(store: store, type: waterType, unit: .literUnit(with: .milli))
                return Int(milliliters)
            },
            waterWriteDenied: {
                store.authorizationStatus(for: waterType) == .sharingDenied
            },
            enableBackgroundDelivery: healthBackgroundDeliveryClosure(store: store)
        )
    }()
}

/// HealthKit quantity type, unit and scale factor for a `WalkMetric`. The
/// scale converts the raw HK unit into the metric's display unit (distance:
/// metres → km).
private struct HKMetricMapping {
    let type: HKQuantityType
    let unit: HKUnit
    let scale: Double
}

private func hkMapping(for metric: WalkMetric) -> HKMetricMapping {
    switch metric {
    case .steps: HKMetricMapping(type: HKQuantityType(.stepCount), unit: .count(), scale: 1)
    case .minutes: HKMetricMapping(type: HKQuantityType(.appleExerciseTime), unit: .minute(), scale: 1)
    case .distance: HKMetricMapping(type: HKQuantityType(.distanceWalkingRunning), unit: .meter(), scale: 1.0 / 1_000)
    case .calories: HKMetricMapping(type: HKQuantityType(.activeEnergyBurned), unit: .kilocalorie(), scale: 1)
    }
}

/// Daily buckets of `metric` over the last `daysBack` days (today included).
private func metricCollection(
    store: HKHealthStore,
    metric: WalkMetric,
    daysBack: Int
) async throws -> [MetricPoint] {
    // The stats "minutes" series must match the hero and the streak: route
    // through the source-agnostic merge instead of raw appleExerciseTime.
    if metric == .minutes {
        let merged = try await mergedDailyMinutes(
            store: store, minutesType: HKQuantityType(.appleExerciseTime), daysBack: daysBack
        )
        return merged.map { MetricPoint(date: $0.date, value: Double($0.minutes)) }
    }
    let calendar = Calendar.current
    let endOfToday = calendar.startOfDay(for: .now).addingTimeInterval(24 * 60 * 60)
    guard let start = calendar.date(
        byAdding: .day, value: -(daysBack - 1), to: calendar.startOfDay(for: .now)
    ) else { return [] }
    return try await statisticsCollection(
        store: store, metric: metric, start: start, end: endOfToday,
        interval: DateComponents(day: 1)
    )
}

/// Hourly buckets of `metric` from midnight today through now.
private func metricHourlyToday(
    store: HKHealthStore,
    metric: WalkMetric
) async throws -> [MetricPoint] {
    // Same reason as `metricCollection`: raw appleExerciseTime would show a
    // Garmin-only user an empty hourly curve under a non-zero daily bar.
    if metric == .minutes {
        return try await mergedHourlyMinutesToday(
            store: store, minutesType: HKQuantityType(.appleExerciseTime)
        )
    }
    let calendar = Calendar.current
    let start = calendar.startOfDay(for: .now)
    return try await statisticsCollection(
        store: store, metric: metric, start: start, end: .now,
        interval: DateComponents(hour: 1)
    )
}

/// Shared `HKStatisticsCollectionQuery` bridge: cumulative-sum buckets of
/// `metric` from `start` to `end` at `interval`, mapped to the metric's
/// display unit and zero-filled for empty buckets.
private func statisticsCollection(
    store: HKHealthStore,
    metric: WalkMetric,
    start: Date,
    end: Date,
    interval: DateComponents
) async throws -> [MetricPoint] {
    let mapping = hkMapping(for: metric)
    let predicate = HKQuery.predicateForSamples(
        withStart: start, end: end, options: .strictStartDate
    )
    return try await withCheckedThrowingContinuation { continuation in
        let query = HKStatisticsCollectionQuery(
            quantityType: mapping.type,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: interval
        )
        query.initialResultsHandler = { _, results, error in
            if isNoDataAvailable(error) {
                continuation.resume(returning: [])
                return
            }
            if let error {
                continuation.resume(throwing: error)
                return
            }
            var output: [MetricPoint] = []
            results?.enumerateStatistics(from: start, to: end) { statistic, _ in
                let value = (statistic.sumQuantity()?.doubleValue(for: mapping.unit) ?? 0) * mapping.scale
                output.append(MetricPoint(date: statistic.startDate, value: value))
            }
            continuation.resume(returning: output)
        }
        store.execute(query)
    }
}

/// Re-fetches the `HKWorkout` matching `summary.id` and pulls heart-rate
/// + step samples scoped to that exact workout via
/// `predicateForObjects(from: workout)` — keeps results clean even when
/// the user wore their Watch outside the walk window.
private func fetchWorkoutDetail(
    for summary: WorkoutSummary,
    store: HKHealthStore
) async throws -> WorkoutDetail {
    guard let workout = try await fetchWorkout(uuid: summary.id, store: store) else {
        // Workout disappeared between summary and detail fetch — return a
        // detail with the summary alone so the UI can still render.
        return WorkoutDetail(summary: summary, heartRateSamples: [], stepsCount: summary.steps)
    }
    async let hrTask = fetchHeartRateSamples(for: workout, store: store)
    // Foulée walks carry their measured step count in metadata (we don't write
    // step samples); fall back to a window query for walks from other sources
    // (Watch, Apple Workouts).
    let steps: Int
    if summary.steps > 0 {
        steps = summary.steps
    } else {
        steps = try await fetchStepsCount(for: workout, store: store)
    }
    return WorkoutDetail(
        summary: summary,
        heartRateSamples: try await hrTask,
        stepsCount: steps
    )
}

private func fetchWorkout(uuid: UUID, store: HKHealthStore) async throws -> HKWorkout? {
    let predicate = HKQuery.predicateForObject(with: uuid)
    return try await withCheckedThrowingContinuation { continuation in
        let query = HKSampleQuery(
            sampleType: .workoutType(),
            predicate: predicate,
            limit: 1,
            sortDescriptors: nil
        ) { _, samples, error in
            if let error {
                continuation.resume(throwing: error)
                return
            }
            continuation.resume(returning: (samples as? [HKWorkout])?.first)
        }
        store.execute(query)
    }
}

/// Heart-rate samples that landed during the workout's time window.
///
/// We deliberately use a date-range predicate rather than
/// `predicateForObjects(from: workout)` because Apple's Workouts app
/// (Forme) doesn't always attach HR samples to the parent workout — the
/// samples live independently in the HR store. Date-range catches them
/// either way. `HKError.noDataAvailable` is treated as an empty array,
/// not an error.
private func fetchHeartRateSamples(
    for workout: HKWorkout,
    store: HKHealthStore
) async throws -> [HeartRateSample] {
    let predicate = HKQuery.predicateForSamples(
        withStart: workout.startDate,
        end: workout.endDate,
        options: .strictStartDate
    )
    let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
    let bpmUnit = HKUnit(from: "count/min")

    return try await withCheckedThrowingContinuation { continuation in
        let query = HKSampleQuery(
            sampleType: HKQuantityType(.heartRate),
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { _, samples, error in
            if isNoDataAvailable(error) {
                continuation.resume(returning: [])
                return
            }
            if let error {
                continuation.resume(throwing: error)
                return
            }
            let quantitySamples = (samples as? [HKQuantitySample]) ?? []
            let mapped = quantitySamples.map {
                HeartRateSample(
                    id: $0.uuid,
                    date: $0.startDate,
                    bpm: Int($0.quantity.doubleValue(for: bpmUnit).rounded())
                )
            }
            continuation.resume(returning: mapped)
        }
        store.execute(query)
    }
}

/// Total steps recorded during the workout window. Same rationale as
/// `fetchHeartRateSamples`: date-range predicate so we catch steps even
/// when the recording app didn't link them to the workout; treat
/// `HKError.noDataAvailable` as 0 since "0 steps" is the right UI
/// answer when nothing matched.
private func fetchStepsCount(
    for workout: HKWorkout,
    store: HKHealthStore
) async throws -> Int {
    let predicate = HKQuery.predicateForSamples(
        withStart: workout.startDate,
        end: workout.endDate,
        options: .strictStartDate
    )

    return try await withCheckedThrowingContinuation { continuation in
        let query = HKStatisticsQuery(
            quantityType: HKQuantityType(.stepCount),
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { _, statistics, error in
            if isNoDataAvailable(error) {
                continuation.resume(returning: 0)
                return
            }
            if let error {
                continuation.resume(throwing: error)
                return
            }
            let count = statistics?.sumQuantity()?.doubleValue(for: .count()) ?? 0
            continuation.resume(returning: Int(count))
        }
        store.execute(query)
    }
}

/// `HKError.Code.noDataAvailable` (= 11) is the framework's way of
/// saying "your predicate matched zero samples". Empty result, not a
/// real failure — bubble it back as the type-appropriate zero value
/// instead of letting the sheet show "Détail indisponible". Internal:
/// also used by HealthKitClient+ActiveMinutes.swift.
func isNoDataAvailable(_ error: (any Error)?) -> Bool {
    guard let hkError = error as? HKError else { return false }
    return hkError.code == .errorNoData
}

/// All walking workouts (activityType `.walking`) started in the last
/// `daysBack` days (today included), regardless of which app or device
/// wrote them. Newest first.
private func recentWalkingWorkouts(
    store: HKHealthStore,
    daysBack: Int
) async throws -> [WorkoutSummary] {
    let calendar = Calendar.current
    let endOfDay = calendar.startOfDay(for: .now).addingTimeInterval(24 * 60 * 60)
    guard let start = calendar.date(
        byAdding: .day, value: -(daysBack - 1), to: calendar.startOfDay(for: .now)
    ) else { return [] }

    let activityPredicate = HKQuery.predicateForWorkouts(with: .walking)
    let datePredicate = HKQuery.predicateForSamples(
        withStart: start, end: endOfDay, options: .strictStartDate
    )
    let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
        activityPredicate, datePredicate
    ])
    let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

    return try await withCheckedThrowingContinuation { continuation in
        let query = HKSampleQuery(
            sampleType: .workoutType(),
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { _, samples, error in
            if let error {
                continuation.resume(throwing: error)
                return
            }
            let workouts = (samples as? [HKWorkout]) ?? []
            let summaries = workouts.map(WorkoutSummary.init(workout:))
            continuation.resume(returning: summaries)
        }
        store.execute(query)
    }
}

/// Continuation-based bridge to `HKStatisticsQuery`. Sums the cumulative
/// quantity between midnight today and now.
private func sumToday(
    store: HKHealthStore,
    type: HKQuantityType,
    unit: HKUnit
) async throws -> Double {
    let calendar = Calendar.current
    let start = calendar.startOfDay(for: .now)
    let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: .strictStartDate)

    return try await withCheckedThrowingContinuation { continuation in
        let query = HKStatisticsQuery(
            quantityType: type,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { _, statistics, error in
            // "No samples yet today" (e.g. zero exercise minutes before the
            // first walk) is reported as `errorNoData` — that's 0, not a
            // failure, so don't let it set the Today error banner.
            if isNoDataAvailable(error) {
                continuation.resume(returning: 0)
                return
            }
            if let error {
                continuation.resume(throwing: error)
                return
            }
            let value = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
            continuation.resume(returning: value)
        }
        store.execute(query)
    }
}
