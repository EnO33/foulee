import Foundation
@preconcurrency import HealthKit
import WidgetKit

/// Builds the live `enableBackgroundDelivery` closure: register for hourly
/// step updates (the finest cadence iOS allows for steps) and, on each
/// background wake, refresh the widget snapshot's metrics + reload the
/// widgets — so the Lock Screen rings move during the day even if the user
/// never opens the app. Separate file to keep HealthKitClient+Live.swift
/// within the file-length limit.
func healthBackgroundDeliveryClosure(store: HKHealthStore) -> @Sendable () async -> Void {
    {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let stepsType = HKQuantityType(.stepCount)
        try? await store.enableBackgroundDelivery(for: stepsType, frequency: .hourly)
        let query = HKObserverQuery(sampleType: stepsType, predicate: nil) { _, completionHandler, error in
            let done = ObserverCompletionBox(completionHandler)
            guard error == nil else { done.value(); return }
            Task {
                await refreshSnapshotMetrics(store: store)
                WidgetCenter.shared.reloadAllTimelines()
                done.value()
            }
        }
        store.execute(query)
    }
}

/// Overlay today's live sums onto the stored widget snapshot. Skips silently
/// when there's no snapshot yet (first launch publishes one) or a read fails
/// (locked phone — keep the last known values).
private func refreshSnapshotMetrics(store: HKHealthStore) async {
    guard var snapshot = SharedStore.read() else { return }
    if let steps = await backgroundSum(store, .stepCount, .count()) { snapshot.steps = Int(steps) }
    if let minutes = await backgroundSum(store, .appleExerciseTime, .minute()) { snapshot.minutes = Int(minutes) }
    if let meters = await backgroundSum(store, .distanceWalkingRunning, .meter()) { snapshot.distanceKm = meters / 1_000 }
    if let kcal = await backgroundSum(store, .activeEnergyBurned, .kilocalorie()) { snapshot.calories = Int(kcal) }
    if let water = await backgroundSum(store, .dietaryWater, .literUnit(with: .milli)) { snapshot.waterML = Int(water) }
    snapshot.date = .now
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

/// Carries the observer's non-Sendable completion into a `Task` (invoked once).
private struct ObserverCompletionBox: @unchecked Sendable {
    let value: () -> Void
    init(_ value: @escaping () -> Void) { self.value = value }
}
