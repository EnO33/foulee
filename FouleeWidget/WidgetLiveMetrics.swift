import Foundation
@preconcurrency import HealthKit

/// Live HealthKit reads from the widget process, overlaid on the app-written
/// snapshot. While the phone is unlocked the rings move on the system's own
/// refresh cadence — no need to open the app. While locked, the Health store
/// is encrypted: reads fail, callers keep the snapshot values (the existing
/// Lock Screen behavior).
enum WidgetLiveMetrics {
    /// The shared snapshot with every metric HealthKit can currently provide
    /// refreshed live. Read-only: the app (foreground refresh, background
    /// delivery, BGAppRefresh) owns persistence — having every widget instance
    /// also write the app-group on each render only amplified writes and raced
    /// the app's own updates.
    static func freshSnapshot() async -> WidgetSnapshot {
        var snapshot = SharedStore.read() ?? .placeholder
        guard HKHealthStore.isHealthDataAvailable() else { return snapshot }
        let store = HKHealthStore()
        // The five sums are independent — run them concurrently so the widget
        // provider stays well inside its tight time budget (5 serial healthd
        // round-trips risked the extension being killed mid-getTimeline).
        async let steps = todaySum(store, .stepCount, .count())
        async let minutes = todaySum(store, .appleExerciseTime, .minute())
        async let meters = todaySum(store, .distanceWalkingRunning, .meter())
        async let kcal = todaySum(store, .activeEnergyBurned, .kilocalorie())
        async let water = todaySum(store, .dietaryWater, .literUnit(with: .milli))
        if let steps = await steps { snapshot.steps = Int(steps) }
        if let minutes = await minutes { snapshot.minutes = Int(minutes) }
        if let meters = await meters { snapshot.distanceKm = meters / 1_000 }
        if let kcal = await kcal { snapshot.calories = Int(kcal) }
        if let water = await water { snapshot.waterML = Int(water) }
        return snapshot
    }

    /// Today's cumulative sum, or nil when HealthKit can't answer (locked
    /// phone, no authorization). "No samples yet" is a real 0, not a failure.
    private static func todaySum(
        _ store: HKHealthStore,
        _ identifier: HKQuantityTypeIdentifier,
        _ unit: HKUnit
    ) async -> Double? {
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: HKQuantityType(identifier),
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error, (error as? HKError)?.code == .errorNoData {
                    continuation.resume(returning: 0)
                } else if error != nil {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0)
                }
            }
            store.execute(query)
        }
    }
}

/// Carries a non-Sendable WidgetKit completion into a `Task` (invoked once).
struct WidgetCompletionBox<Value>: @unchecked Sendable {
    let value: (Value) -> Void
    init(_ value: @escaping (Value) -> Void) { self.value = value }
}
