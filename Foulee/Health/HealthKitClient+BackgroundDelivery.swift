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
            let isWater = type == HKQuantityType(.dietaryWater)
            // A workout delivery is the one wake that can have repaired a past
            // day for a Garmin user — see `BackgroundStreakRefresh`.
            let wake: BackgroundStreakRefresh.Wake = type == HKWorkoutType.workoutType() ? .workout : .other
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completionHandler, error in
                let done = UncheckedSendableBox(completionHandler)
                guard error == nil else { done.value(); return }
                Task {
                    // iOS throttles/stops background delivery if the handler
                    // isn't called — `defer` guarantees it on every exit,
                    // including task cancellation when the budget runs out.
                    defer { done.value() }
                    await refreshSnapshotMetrics(store: store, wake: wake)
                    WidgetCenter.shared.reloadAllTimelines()
                    if isWater {
                        await reshiftHydrationRemindersIfWaterIncreased(store: store)
                    }
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
    await refreshSnapshotMetrics(store: HKHealthStore(), wake: .other)
}

/// Overlay today's live sums onto the stored widget snapshot. Skips silently
/// when there's no snapshot yet (first launch publishes one) or a read fails
/// (locked phone — keep the last known values). The streak rides along only
/// when this wake can have changed it (`BackgroundStreakRefresh`).
private func refreshSnapshotMetrics(store: HKHealthStore, wake: BackgroundStreakRefresh.Wake) async {
    guard let stored = SharedStore.read() else { return }
    let now = Date.now
    let defaults = UserDefaults.standard
    let storedDay = stored.day
    // The goal crossing is judged on a HealthKit-only scale of its own (#189).
    // The shared snapshot's minutes now carry the Connect IQ overlay, so using
    // them here would let a watch total pre-consume the crossing edge — or fire
    // it on minutes HealthKit never measured, for a streak whose history is
    // HealthKit's alone. `nil` (no measurement today: first wake after an
    // install or an update) reads as 0, which at worst buys one extra recompute
    // on the day's first wake.
    let storedMinutes = BackgroundStreakRefresh.lastMeasuredMinutesToday(defaults: defaults, now: now) ?? 0
    let measured = await measuredCounters(store: store)
    let streak = await recomputedBackgroundStreak(
        store: store,
        storedDay: storedDay,
        storedMinutes: storedMinutes,
        todayMinutes: measured.minutes ?? storedMinutes,
        wake: wake
    )
    // Consume the edge, exactly like the crossing stamp above it: the next wake
    // must compare against what this one measured, not against what the last
    // one did.
    if let minutes = measured.minutes {
        BackgroundStreakRefresh.markMeasuredMinutes(minutes, at: now, defaults: defaults)
    }
    // Commit against the snapshot as it stands *now*, not the copy read before
    // the queries: several observers fire at once on a Garmin sync and the
    // recompute above can take seconds. A full read-modify-write from the
    // stale copy would put back the streak (and the counters) this pass read
    // at its own start, silently undoing whatever landed meanwhile.
    var snapshot = (SharedStore.read() ?? stored).zeroedIfStale()
    // Connect IQ overlay (#189): the day's high-water floor, folded in with a
    // max — never a sum, and only onto the legs HealthKit answered. A leg it
    // refused keeps the stored value, so a Garmin total can't ride a read
    // nobody made. Calories stay HealthKit-only (Garmin's are a *total* burn).
    //
    // Each rewritten leg carries its own floor into the app group beside it
    // (#214): the widget process can't read `GarminSnapshotStore`, and without
    // the number its own live HealthKit read would have to be floored against
    // the stored *total* — which is what kept a legitimately falling counter
    // pinned at the day's high. Clamped to the counter it accompanies, so the
    // floor can never sit above the total it is holding up.
    //
    // Tied to the same `if let` on purpose. A refused leg keeps the stored
    // counter, so it must keep the stored floor too — that number may hold a
    // post-walk overlay (#158) this process knows nothing about, `pendingWalk`
    // living in `TodayStore`'s memory. On a leg HealthKit *did* answer the walk
    // component goes, exactly as the counter itself does: `max(measured,
    // overlay)` has already dropped the walk lift from the total here, and a
    // floor left above it would be the inconsistency of the line above.
    let overlay = GarminSnapshotStore.readFloor(now: now, from: defaults)
    if let steps = measured.steps {
        snapshot.steps = max(steps, overlay?.steps ?? 0)
        snapshot.floorSteps = min(overlay?.steps ?? 0, snapshot.steps)
    }
    if let minutes = measured.minutes {
        snapshot.minutes = ActiveMinutes.merged(minutes, with: overlay?.activeMinutes ?? 0)
        snapshot.floorMinutes = min(overlay?.activeMinutes ?? 0, snapshot.minutes)
    }
    if let distanceKm = measured.distanceKm {
        snapshot.distanceKm = max(distanceKm, overlay?.distanceKm ?? 0)
        snapshot.floorDistanceKm = min(overlay?.distanceKm ?? 0, snapshot.distanceKm)
    }
    if let calories = measured.calories { snapshot.calories = calories }
    if let waterML = measured.waterML { snapshot.waterML = waterML }
    if let streak { snapshot.streak = streak }
    SharedStore.write(snapshot)
    // The watch complication reads what the phone pushed (`WatchSyncStore`),
    // not the shared snapshot — without this it would keep a pre-repair streak
    // all day for a user who never opens the app (issue #194). Only on a real
    // recompute: quiet wakes would just add WatchConnectivity traffic.
    guard streak != nil else { return }
    PhoneWatchSync.shared.send(WatchSyncPayload(
        streak: snapshot.streak,
        minutesGoal: snapshot.minutesGoal,
        stepsGoal: snapshot.stepsGoal,
        hydrationEnabled: snapshot.hydrationEnabled,
        hydrationGoalML: snapshot.waterGoalML,
        hydrationGlassML: snapshot.hydrationGlassML
    ))
}

/// Today's counters as this wake measured them. A nil leg is a read HealthKit
/// refused (locked phone), which must keep the stored value rather than
/// publish a zero.
private struct MeasuredCounters {
    var steps: Int?
    var minutes: Int?
    var distanceKm: Double?
    var calories: Int?
    var waterML: Int?
}

private func measuredCounters(store: HKHealthStore) async -> MeasuredCounters {
    // Independent sums — run concurrently to keep the background wake short.
    async let steps = backgroundSum(store, .stepCount, .count())
    async let minutes = backgroundSum(store, .appleExerciseTime, .minute())
    async let meters = backgroundSum(store, .distanceWalkingRunning, .meter())
    async let kcal = backgroundSum(store, .activeEnergyBurned, .kilocalorie())
    async let water = backgroundSum(store, .dietaryWater, .literUnit(with: .milli))
    // Same max() as the app and the widget (see ActiveMinutes): a background
    // wake must not overwrite a Garmin user's merged minutes with raw zeros.
    // Both legs must answer — merging a failed workout read as 0 would do
    // exactly that overwrite for a Garmin-only user; keep the stored value.
    async let workoutMinutes = todayWorkoutMinutes(store: store)
    var counters = MeasuredCounters()
    if let steps = await steps { counters.steps = Int(steps) }
    if let minutes = await minutes, let workoutMinutes = try? await workoutMinutes {
        counters.minutes = ActiveMinutes.merged(
            appleMinutes: Int(minutes),
            workoutMinutes: workoutMinutes
        )
    }
    if let meters = await meters { counters.distanceKm = meters / 1_000 }
    if let kcal = await kcal { counters.calories = Int(kcal) }
    if let water = await water { counters.waterML = Int(water) }
    return counters
}

/// Last dietaryWater total this observer saw, kept in the app's own defaults
/// — day-stamped so yesterday's total is never a baseline for today. The
/// shared snapshot can't serve as the "before" value: the widget's
/// `LogWaterIntent` rewrites it from its own process before (or racing) this
/// observer, which would mask exactly the glasses this path exists to catch.
private let observedWaterTotalKey = "hydration.observedWaterML"
private let observedWaterDayKey = "hydration.observedWaterAt"

/// A glass logged outside the app (widget intent, the Watch, another Health
/// app) never runs the in-app reschedule path, so a reminder could fire
/// minutes after it. This observer is the one hook that wakes for every water
/// sample; reshift today's grid when the total increased. It also fires for
/// the app's own writes, where the reschedule already ran — the second call
/// is harmless (the drink stamp lands seconds apart and the pending requests
/// are replaced deterministically). Decreases (sample deletions) and the
/// initial fire at observer registration must not shift anything.
private func reshiftHydrationRemindersIfWaterIncreased(store: HKHealthStore) async {
    guard let total = await backgroundSum(store, .dietaryWater, .literUnit(with: .milli)) else { return }
    let defaults = UserDefaults.standard
    let previous = lastObservedWaterToday(defaults: defaults)
    defaults.set(total, forKey: observedWaterTotalKey)
    defaults.set(Date.now.timeIntervalSince1970, forKey: observedWaterDayKey)
    let enabled = defaults.bool(forKey: "preferences.hydrationEnabled")
        && defaults.bool(forKey: "preferences.hydrationRemindersEnabled")
    let lastDrinkStamp = defaults.double(forKey: HydrationReminderScheduler.lastDrinkKey)
    let lastDrinkAge: TimeInterval? = lastDrinkStamp > 0
        ? Date.now.timeIntervalSince1970 - lastDrinkStamp
        : nil
    guard HydrationReminderScheduler.shouldRescheduleAfterWaterDelivery(
        previousML: previous,
        currentML: Int(total),
        remindersEnabled: enabled,
        lastDrinkAge: lastDrinkAge
    ) else { return }
    await HydrationReminderScheduler().recordDrinkAndReschedule()
}

/// The total recorded by the last observation *today*, or nil when none —
/// so the day's first out-of-app glass counts as an increase from 0.
private func lastObservedWaterToday(defaults: UserDefaults) -> Int? {
    let stamp = defaults.double(forKey: observedWaterDayKey)
    guard stamp > 0,
          Calendar.current.isDate(Date(timeIntervalSince1970: stamp), inSameDayAs: .now)
    else { return nil }
    return Int(defaults.double(forKey: observedWaterTotalKey))
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
