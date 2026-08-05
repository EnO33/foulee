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
    ///
    /// The live reads are **merged into** the stored snapshot, not substituted
    /// for it (`mergingLiveCounters`): the app can have written counters this
    /// process cannot measure — the Connect IQ overlay (#189) never touches
    /// HealthKit, and a walk that just ended has not been flushed into it yet
    /// (#158) — and replacing them here would discard both on every render.
    /// The snapshot carries how much they lifted (`floor*`), so this process
    /// can hold exactly that much up and let everything else follow the read.
    static func freshSnapshot() async -> WidgetSnapshot {
        // Zero counters from a previous day up front: when locked-phone reads
        // fail below, the fallback must not show yesterday's totals — and the
        // merge below must not have them on its other side either.
        let snapshot = (SharedStore.read() ?? .placeholder).zeroedIfStale()
        guard HKHealthStore.isHealthDataAvailable() else { return snapshot }
        let store = HKHealthStore()
        // The six reads are independent — run them concurrently so the widget
        // provider stays well inside its tight time budget (serial healthd
        // round-trips risked the extension being killed mid-getTimeline).
        async let steps = todaySum(store, .stepCount, .count())
        async let minutes = todaySum(store, .appleExerciseTime, .minute())
        async let meters = todaySum(store, .distanceWalkingRunning, .meter())
        async let kcal = todaySum(store, .activeEnergyBurned, .kilocalorie())
        async let water = todaySum(store, .dietaryWater, .literUnit(with: .milli))
        async let workouts = todayWorkoutIntervals(store)
        var liveMinutes: Int?
        if let minutes = await minutes {
            // Same max() as the app (see ActiveMinutes): a Garmin-only user's
            // widget minutes must match the hero ring.
            let startOfDay = Calendar.current.startOfDay(for: .now)
            let workoutMinutes = ActiveMinutes.workoutMinutesByDay((await workouts) ?? [])[startOfDay] ?? 0
            liveMinutes = ActiveMinutes.merged(appleMinutes: Int(minutes), workoutMinutes: workoutMinutes)
        }
        return snapshot.mergingLiveCounters(
            steps: (await steps).map { Int($0) },
            minutes: liveMinutes,
            distanceKm: (await meters).map { $0 / 1_000 },
            calories: (await kcal).map { Int($0) },
            waterML: (await water).map { Int($0) }
        )
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

    /// Workouts started today (any activity type), or nil when HealthKit
    /// can't answer. "No workouts yet" is an empty array, not a failure.
    private static func todayWorkoutIntervals(
        _ store: HKHealthStore
    ) async -> [ActiveMinutes.WorkoutInterval]? {
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error, (error as? HKError)?.code == .errorNoData {
                    continuation.resume(returning: [])
                } else if error != nil {
                    continuation.resume(returning: nil)
                } else {
                    let workouts = (samples as? [HKWorkout]) ?? []
                    continuation.resume(returning: workouts.map {
                        ActiveMinutes.WorkoutInterval(start: $0.startDate, duration: $0.duration)
                    })
                }
            }
            store.execute(query)
        }
    }
}
