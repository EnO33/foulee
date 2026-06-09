@preconcurrency import HealthKit
import Observation

/// Today's at-a-glance numbers for the watch home: steps, exercise minutes,
/// distance and calories come straight from the watch's HealthKit (today's
/// data is always present locally). The streak is *not* recomputed here — the
/// watch keeps only a few days of history, so it would undercount long streaks.
/// It's the value the phone computed and synced (`WatchSyncStore`).
@MainActor
@Observable
final class WatchTodayStore {
    private(set) var steps = 0
    private(set) var minutes = 0
    private(set) var distanceKm = 0.0
    private(set) var calories = 0
    private(set) var streak = 0
    private(set) var waterML = 0
    private(set) var hydrationEnabled = false
    private(set) var hydrationGoalML = 2_000
    private(set) var hydrationGlassML = 250
    private(set) var isLoading = true

    @ObservationIgnored private let store = HKHealthStore()
    private static let waterType = HKQuantityType(.dietaryWater)

    private static let readTypes: Set<HKObjectType> = [
        HKQuantityType(.stepCount),
        HKQuantityType(.appleExerciseTime),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.activeEnergyBurned),
        waterType
    ]

    func load() async {
        isLoading = true
        defer { isLoading = false }

        // Streak + hydration goal come from the phone (source of truth).
        let sync = WatchSyncStore.read()
        streak = sync?.streak ?? 0
        hydrationEnabled = sync?.hydrationEnabled ?? false
        hydrationGoalML = sync?.hydrationGoalML ?? 2_000
        hydrationGlassML = sync?.hydrationGlassML ?? 250

        guard HKHealthStore.isHealthDataAvailable() else { return }
        _ = try? await store.requestAuthorization(toShare: [Self.waterType], read: Self.readTypes)

        async let stepsValue = sumToday(.stepCount, unit: .count())
        async let minutesValue = sumToday(.appleExerciseTime, unit: .minute())
        async let distanceValue = sumToday(.distanceWalkingRunning, unit: .meter())
        async let caloriesValue = sumToday(.activeEnergyBurned, unit: .kilocalorie())
        async let waterValue = sumToday(.dietaryWater, unit: .literUnit(with: .milli))

        steps = Int(await stepsValue)
        minutes = Int(await minutesValue)
        distanceKm = await distanceValue / 1_000
        calories = Int(await caloriesValue)
        waterML = Int(await waterValue)
    }

    /// Log one glass (the phone-synced glass size) to Health, then re-read.
    func logGlass() async {
        let sample = HKQuantitySample(
            type: Self.waterType,
            quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: Double(hydrationGlassML)),
            start: .now,
            end: .now
        )
        try? await store.save(sample)
        await load()
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
}
