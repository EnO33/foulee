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
            }
        )
    }()
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
