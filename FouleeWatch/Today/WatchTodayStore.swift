@preconcurrency import HealthKit
import Observation

/// Today's at-a-glance numbers for the watch home: steps, exercise minutes,
/// distance, calories and the current streak. Reads HealthKit directly on the
/// watch (no app-group sync with the phone), so the streak uses the default
/// goal — same as the watch complication.
@MainActor
@Observable
final class WatchTodayStore {
    private(set) var steps = 0
    private(set) var minutes = 0
    private(set) var distanceKm = 0.0
    private(set) var calories = 0
    private(set) var streak = 0
    private(set) var isLoading = true

    @ObservationIgnored private let store = HKHealthStore()

    private static let goalMinutes = 20
    private static let historyDays = 30
    private static let readTypes: Set<HKObjectType> = [
        HKQuantityType(.stepCount),
        HKQuantityType(.appleExerciseTime),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.activeEnergyBurned)
    ]

    func load() async {
        isLoading = true
        defer { isLoading = false }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        _ = try? await store.requestAuthorization(toShare: [], read: Self.readTypes)

        async let stepsValue = sumToday(.stepCount, unit: .count())
        async let minutesValue = sumToday(.appleExerciseTime, unit: .minute())
        async let distanceValue = sumToday(.distanceWalkingRunning, unit: .meter())
        async let caloriesValue = sumToday(.activeEnergyBurned, unit: .kilocalorie())

        steps = Int(await stepsValue)
        minutes = Int(await minutesValue)
        distanceKm = await distanceValue / 1_000
        calories = Int(await caloriesValue)

        let history = await dailyExerciseMinutes()
        streak = StreakCalculator.current(history: history, goalMinutes: Self.goalMinutes, today: .now)
    }

    /// Today's cumulative sum for a quantity. Missing data resolves to 0 (no
    /// error path), so an empty metric never blocks the others.
    private func sumToday(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double {
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: HKQuantityType(identifier),
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(query)
        }
    }

    /// Daily exercise minutes over the last `historyDays` days, for the streak.
    private func dailyExerciseMinutes() async -> [DailyMinutes] {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: .now).addingTimeInterval(24 * 60 * 60)
        guard let start = calendar.date(
            byAdding: .day, value: -(Self.historyDays - 1), to: calendar.startOfDay(for: .now)
        ) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: HKQuantityType(.appleExerciseTime),
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: start,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, results, _ in
                var output: [DailyMinutes] = []
                results?.enumerateStatistics(from: start, to: end) { statistic, _ in
                    let minutes = statistic.sumQuantity()?.doubleValue(for: .minute()) ?? 0
                    output.append(DailyMinutes(date: statistic.startDate, minutes: Int(minutes)))
                }
                continuation.resume(returning: output)
            }
            store.execute(query)
        }
    }
}
