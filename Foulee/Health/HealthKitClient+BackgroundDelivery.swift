import Foundation
@preconcurrency import HealthKit
import os
import WidgetKit

/// One-shot guard: the observers must be registered exactly once per process.
/// `bootstrap()` (and thus this closure) runs on every Today-tab appearance,
/// and each run would otherwise `execute` a fresh set of HKObserverQuery on the
/// long-lived live store — stacking observers so a single sample fires the
/// handler N times.
private let backgroundObserversStarted = OSAllocatedUnfairLock(initialState: false)

/// Builds the live `enableBackgroundDelivery` closure: register for Health
/// background updates and, on each wake, refresh the widget snapshot's
/// metrics + reload the widgets — so the rings move during the day even if
/// the user never opens the app. Steps are clamped to hourly by iOS; water
/// and workouts deliver *immediately*, so drinking (even from the watch) or
/// finishing a walk updates the iPhone widgets within seconds. Separate file
/// to keep HealthKitClient+Live.swift within the file-length limit.
func healthBackgroundDeliveryClosure(store: HKHealthStore) -> @Sendable () async -> Void {
    {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let shouldStart = backgroundObserversStarted.withLock { started -> Bool in
            guard !started else { return false }
            started = true
            return true
        }
        guard shouldStart else { return }
        let deliveries: [(HKSampleType, HKUpdateFrequency)] = [
            (HKQuantityType(.stepCount), .hourly),
            (HKQuantityType(.dietaryWater), .immediate),
            (HKWorkoutType.workoutType(), .immediate)
        ]
        for (type, frequency) in deliveries {
            try? await store.enableBackgroundDelivery(for: type, frequency: frequency)
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completionHandler, error in
                let done = UncheckedSendableBox(completionHandler)
                guard error == nil else { done.value(); return }
                Task {
                    // iOS throttles/stops background delivery if the handler
                    // isn't called — `defer` guarantees it on every exit,
                    // including task cancellation when the budget runs out.
                    defer { done.value() }
                    await refreshSnapshotMetrics(store: store)
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
            store.execute(query)
        }
    }
}

/// Same snapshot refresh, callable with a standalone store — used by the
/// BGAppRefresh task as an extra wake source between Health deliveries.
func refreshWidgetSnapshotFromHealth() async {
    guard HKHealthStore.isHealthDataAvailable() else { return }
    await refreshSnapshotMetrics(store: HKHealthStore())
}

/// Overlay today's live sums onto the stored widget snapshot. Skips silently
/// when there's no snapshot yet (first launch publishes one) or a read fails
/// (locked phone — keep the last known values).
private func refreshSnapshotMetrics(store: HKHealthStore) async {
    guard let stored = SharedStore.read() else { return }
    // Zero counters from a previous day before overlaying: a failed read
    // below must not carry yesterday's totals into a freshly-stamped write.
    var snapshot = stored.zeroedIfStale()
    // Independent sums — run concurrently to keep the background wake short.
    async let steps = backgroundSum(store, .stepCount, .count())
    async let minutes = backgroundSum(store, .appleExerciseTime, .minute())
    async let meters = backgroundSum(store, .distanceWalkingRunning, .meter())
    async let kcal = backgroundSum(store, .activeEnergyBurned, .kilocalorie())
    async let water = backgroundSum(store, .dietaryWater, .literUnit(with: .milli))
    if let steps = await steps { snapshot.steps = Int(steps) }
    if let minutes = await minutes { snapshot.minutes = Int(minutes) }
    if let meters = await meters { snapshot.distanceKm = meters / 1_000 }
    if let kcal = await kcal { snapshot.calories = Int(kcal) }
    if let water = await water { snapshot.waterML = Int(water) }
    SharedStore.write(snapshot)
}

/// Today's cumulative sum, or nil when HealthKit can't answer. "No samples
/// yet" is a real 0, not a failure.
private func backgroundSum(
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
