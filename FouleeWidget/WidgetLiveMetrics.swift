import Foundation
@preconcurrency import HealthKit

/// Live HealthKit reads from the widget process, overlaid on the app-written
/// snapshot. While the phone is unlocked the rings move on the system's own
/// refresh cadence — no need to open the app. While locked, the Health store
/// is encrypted: reads fail, callers keep the snapshot values (the existing
/// Lock Screen behavior).
enum WidgetLiveMetrics {
    /// The shared snapshot with every metric HealthKit can currently provide
    /// refreshed live. Persists the merge so the next locked render shows the
    /// freshest values we ever saw.
    static func freshSnapshot() async -> WidgetSnapshot {
        var snapshot = SharedStore.read() ?? .placeholder
        guard HKHealthStore.isHealthDataAvailable() else { return snapshot }
        let store = HKHealthStore()
        var changed = false
        if let steps = await todaySum(store, .stepCount, .count()) {
            snapshot.steps = Int(steps); changed = true
        }
        if let minutes = await todaySum(store, .appleExerciseTime, .minute()) {
            snapshot.minutes = Int(minutes); changed = true
        }
        if let meters = await todaySum(store, .distanceWalkingRunning, .meter()) {
            snapshot.distanceKm = meters / 1_000; changed = true
        }
        if let kcal = await todaySum(store, .activeEnergyBurned, .kilocalorie()) {
            snapshot.calories = Int(kcal); changed = true
        }
        if let water = await todaySum(store, .dietaryWater, .literUnit(with: .milli)) {
            snapshot.waterML = Int(water); changed = true
        }
        if changed {
            snapshot.date = .now
            SharedStore.write(snapshot)
        }
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
