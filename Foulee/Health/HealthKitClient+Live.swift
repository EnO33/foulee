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
        let walkingWorkoutType = HKWorkoutType.workoutType()

        let readTypes: Set<HKObjectType> = [
            stepsType, distanceType, minutesType, caloriesType, walkingWorkoutType
        ]
        let writeTypes: Set<HKSampleType> = [walkingWorkoutType]

        return HealthKitClient(
            isAvailable: {
                HKHealthStore.isHealthDataAvailable()
            },
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

                return try await HealthMetrics(
                    steps: Int(steps),
                    distanceKm: distanceMeters / 1_000,
                    activeMinutes: Int(minutes),
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

                let elapsedMinutes = max(session.elapsed / 60, 0)
                let estimatedCalories = Double(session.estimatedCalories)

                let distanceSample = HKQuantitySample(
                    type: distanceType,
                    quantity: HKQuantity(unit: .meter(), doubleValue: session.distanceMeters),
                    start: session.startedAt,
                    end: endedAt
                )
                let stepsSample = HKQuantitySample(
                    type: stepsType,
                    quantity: HKQuantity(unit: .count(), doubleValue: Double(session.steps)),
                    start: session.startedAt,
                    end: endedAt
                )
                let caloriesSample = HKQuantitySample(
                    type: caloriesType,
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: estimatedCalories),
                    start: session.startedAt,
                    end: endedAt
                )
                let minutesSample = HKQuantitySample(
                    type: minutesType,
                    quantity: HKQuantity(unit: .minute(), doubleValue: elapsedMinutes),
                    start: session.startedAt,
                    end: endedAt
                )
                try await builder.addSamples([
                    distanceSample, stepsSample, caloriesSample, minutesSample
                ])

                try await builder.endCollection(at: endedAt)
                _ = try await builder.finishWorkout()
            },
            dailyMinutes: { daysBack in
                try await dailyExerciseMinutes(
                    store: store,
                    type: minutesType,
                    daysBack: daysBack
                )
            },
            recentWorkouts: { daysBack in
                try await recentWalkingWorkouts(store: store, daysBack: daysBack)
            },
            workoutDetail: { summary in
                try await workoutDetail(for: summary, store: store)
            }
        )
    }()
}

/// Re-fetches the `HKWorkout` matching `summary.id` and pulls heart-rate
/// + step samples scoped to that exact workout via
/// `predicateForObjects(from: workout)` — keeps results clean even when
/// the user wore their Watch outside the walk window.
private func workoutDetail(
    for summary: WorkoutSummary,
    store: HKHealthStore
) async throws -> WorkoutDetail {
    guard let workout = try await fetchWorkout(uuid: summary.id, store: store) else {
        // Workout disappeared between summary and detail fetch — return a
        // detail with the summary alone so the UI can still render.
        return WorkoutDetail(summary: summary, heartRateSamples: [], stepsCount: 0)
    }
    async let hrTask = fetchHeartRateSamples(for: workout, store: store)
    async let stepsTask = fetchStepsCount(for: workout, store: store)
    return try await WorkoutDetail(
        summary: summary,
        heartRateSamples: hrTask,
        stepsCount: stepsTask
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

private func fetchHeartRateSamples(
    for workout: HKWorkout,
    store: HKHealthStore
) async throws -> [HeartRateSample] {
    let predicate = HKQuery.predicateForObjects(from: workout)
    let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
    let bpmUnit = HKUnit(from: "count/min")

    return try await withCheckedThrowingContinuation { continuation in
        let query = HKSampleQuery(
            sampleType: HKQuantityType(.heartRate),
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { _, samples, error in
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

private func fetchStepsCount(
    for workout: HKWorkout,
    store: HKHealthStore
) async throws -> Int {
    let predicate = HKQuery.predicateForObjects(from: workout)

    return try await withCheckedThrowingContinuation { continuation in
        let query = HKStatisticsQuery(
            quantityType: HKQuantityType(.stepCount),
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { _, statistics, error in
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

extension WorkoutSummary {
    fileprivate init(workout: HKWorkout) {
        let distanceMeters = workout
            .statistics(for: HKQuantityType(.distanceWalkingRunning))?
            .sumQuantity()?
            .doubleValue(for: .meter()) ?? 0
        let kcal = workout
            .statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?
            .doubleValue(for: .kilocalorie()) ?? 0
        self.init(
            id: workout.uuid,
            startedAt: workout.startDate,
            endedAt: workout.endDate,
            durationSeconds: workout.duration,
            distanceKm: distanceMeters / 1_000,
            activeCalories: Int(kcal),
            sourceName: workout.sourceRevision.source.name
        )
    }
}

/// Continuation-based bridge to `HKStatisticsCollectionQuery`. Buckets the
/// minutes type by calendar day from `daysBack` days ago through today.
/// Days with no samples land as `0` so the chart shows the gap.
private func dailyExerciseMinutes(
    store: HKHealthStore,
    type: HKQuantityType,
    daysBack: Int
) async throws -> [DailyMinutes] {
    let calendar = Calendar.current
    let endOfToday = calendar.startOfDay(for: .now)
        .addingTimeInterval(24 * 60 * 60)
    guard let startOfRange = calendar.date(
        byAdding: .day, value: -(daysBack - 1), to: calendar.startOfDay(for: .now)
    ) else { return [] }

    let predicate = HKQuery.predicateForSamples(
        withStart: startOfRange, end: endOfToday, options: .strictStartDate
    )
    let interval = DateComponents(day: 1)

    return try await withCheckedThrowingContinuation { continuation in
        let query = HKStatisticsCollectionQuery(
            quantityType: type,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum,
            anchorDate: startOfRange,
            intervalComponents: interval
        )
        query.initialResultsHandler = { _, results, error in
            if let error {
                continuation.resume(throwing: error)
                return
            }
            var output: [DailyMinutes] = []
            results?.enumerateStatistics(from: startOfRange, to: endOfToday) { statistic, _ in
                let minutes = statistic.sumQuantity()?.doubleValue(for: .minute()) ?? 0
                output.append(DailyMinutes(
                    date: statistic.startDate,
                    minutes: Int(minutes)
                ))
            }
            continuation.resume(returning: output)
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
