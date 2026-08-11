@preconcurrency import HealthKit
import Observation
import WidgetKit

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
    private(set) var stepsGoal = 6_000
    private(set) var minutesGoal = 20
    private(set) var waterML = 0
    private(set) var hydrationEnabled = false
    private(set) var hydrationGoalML = 2_000
    private(set) var hydrationGlassML = 250
    /// Whether the phone ever synced a payload — false means "never paired /
    /// phone app never opened", which the UI surfaces instead of hiding
    /// phone-derived content silently.
    private(set) var hasPhoneSync = false
    private(set) var isLoading = true
    /// The user explicitly denied writing `dietaryWater` on the watch — the
    /// hydration card explains it instead of showing a dead "J'ai bu" button.
    /// Write denial is detectable via `authorizationStatus`; read denial is
    /// not (queries just return zeros, by HealthKit design).
    private(set) var waterDenied = false
    /// Set when the last glass failed to save — cleared on the next success.
    private(set) var hydrationError: String?

    @ObservationIgnored private let store = HKHealthStore()
    /// Guards against an older in-flight `load()` overwriting a newer one (the
    /// same race the phone's HydrationStore has — see its `refreshGeneration`).
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var waterObserver: HKObserverQuery?
    private static let waterType = HKQuantityType(.dietaryWater)
    /// Raw HKError descriptions are technical noise on a watch card — a fixed
    /// message tells the user what matters: it didn't count.
    private static let saveFailedMessage = "Verre non enregistré — réessaie"

    private static let readTypes: Set<HKObjectType> = [
        HKQuantityType(.stepCount),
        HKQuantityType(.appleExerciseTime),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.activeEnergyBurned),
        waterType
    ]

    init() {
        // The hydration banner's "J'ai bu" action saves from another object
        // (`WatchHydrationNotificationCenter`) — its denial / failed save
        // reaches the card only through these signals. The store lives as
        // long as the app, so the observations are never removed; `weak self`
        // keeps a stray observer inert.
        _ = NotificationCenter.default.addObserver(
            forName: .watchHydrationActionFailed, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in self?.hydrationError = Self.saveFailedMessage }
        }
        _ = NotificationCenter.default.addObserver(
            forName: .watchHydrationActionDenied, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in self?.waterDenied = true }
        }
        // A confirmed successful save clears the failure — otherwise a
        // banner retry that works would leave « non enregistré » stuck on
        // the card until the next in-app log.
        _ = NotificationCenter.default.addObserver(
            forName: HydrationNotification.actionHandled, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in self?.hydrationError = nil }
        }
    }

    /// Reload whenever `dietaryWater` changes in Health — including water that
    /// synced in from the iPhone — so the watch card reflects it without the
    /// user reopening the app. Idempotent; safe to call on appear.
    func startObserving() {
        #if DEBUG
        // Capture mode (issue #239): the numbers are seeded and never change,
        // so there is nothing to observe — and an observer is a HealthKit
        // registration a capture run has no business making.
        guard !WatchScreenshotMode.isActive else { return }
        #endif
        guard waterObserver == nil, HKHealthStore.isHealthDataAvailable() else { return }
        let query = HKObserverQuery(sampleType: Self.waterType, predicate: nil) { [weak self] _, completion, _ in
            Task { @MainActor in await self?.load() }
            completion()
        }
        store.execute(query)
        waterObserver = query
    }

    func load() async {
        #if DEBUG
        // Capture mode (issue #239) — the one branch in this file's production
        // path. It returns before the phone payload is read and before
        // `HKHealthStore` is touched at all: no authorization request, no
        // query, nothing written. Split into `applyScreenshotSeed()` so a test
        // can drive it without activating the mode process-wide.
        if WatchScreenshotMode.isActive {
            applyScreenshotSeed()
            return
        }
        #endif
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        defer { isLoading = false }

        // Streak + goals come from the phone (source of truth).
        let sync = WatchSyncStore.read()
        hasPhoneSync = sync != nil
        streak = sync?.streak ?? 0
        stepsGoal = sync?.stepsGoal ?? 6_000
        minutesGoal = sync?.minutesGoal ?? 20
        hydrationEnabled = sync?.hydrationEnabled ?? false
        hydrationGoalML = sync?.hydrationGoalML ?? 2_000
        hydrationGlassML = sync?.hydrationGlassML ?? 250

        guard HKHealthStore.isHealthDataAvailable() else { return }
        _ = try? await store.requestAuthorization(toShare: [Self.waterType], read: Self.readTypes)
        waterDenied = store.authorizationStatus(for: Self.waterType) == .sharingDenied

        async let stepsValue = sumToday(.stepCount, unit: .count())
        async let minutesValue = sumToday(.appleExerciseTime, unit: .minute())
        async let distanceValue = sumToday(.distanceWalkingRunning, unit: .meter())
        async let caloriesValue = sumToday(.activeEnergyBurned, unit: .kilocalorie())
        async let waterValue = sumToday(.dietaryWater, unit: .literUnit(with: .milli))

        let newSteps = Int(await stepsValue)
        let newMinutes = Int(await minutesValue)
        let newDistanceKm = await distanceValue / 1_000
        let newCalories = Int(await caloriesValue)
        let newWaterML = Int(await waterValue)

        // A newer load() started while these reads were in flight — don't let
        // this stale result overwrite it (e.g. logging a glass right after the
        // watch comes to the wrist, which both kick off a load).
        guard generation == loadGeneration else { return }
        steps = newSteps
        minutes = newMinutes
        distanceKm = newDistanceKm
        calories = newCalories
        waterML = newWaterML
    }

    /// Refresh only what the session's « Journée » page draws (issue #280).
    ///
    /// **Not `load()`.** That one asks for authorization and fires five
    /// queries, which is a lot to repeat every minute on a wrist already
    /// running a workout session, a motion stream and a clock. Authorization
    /// was granted when the session started — asking again mid-outing would put
    /// a second sheet on screen for nothing.
    ///
    /// The streak and the goals cost no query at all: they are the phone's,
    /// read synchronously out of the app group, so the page draws filled the
    /// instant it appears and only the two numerators arrive late.
    ///
    /// **The day's steps are read, never accumulated.** Adding the session's
    /// own counters to the day's would double-count for as long as HealthKit
    /// takes to publish the wrist's samples — and the error would read as a
    /// generous day rather than as a bug.
    func refreshForSession() async {
        #if DEBUG
        // Capture mode (issue #239): same seeded day as `load()`, and for the
        // same reason — a capture must query nothing.
        if WatchScreenshotMode.isActive {
            applyScreenshotSeed()
            return
        }
        #endif
        let sync = WatchSyncStore.read()
        hasPhoneSync = sync != nil
        streak = sync?.streak ?? 0
        stepsGoal = sync?.stepsGoal ?? 6_000
        minutesGoal = sync?.minutesGoal ?? 20

        guard HKHealthStore.isHealthDataAvailable() else { return }
        // Shares `load()`'s generation counter rather than keeping its own: the
        // two write the same properties, and a `load()` triggered by the water
        // observer can land in the middle of this one.
        loadGeneration += 1
        let generation = loadGeneration
        async let stepsValue = sumToday(.stepCount, unit: .count())
        async let minutesValue = sumToday(.appleExerciseTime, unit: .minute())
        let newSteps = Int(await stepsValue)
        let newMinutes = Int(await minutesValue)
        guard generation == loadGeneration else { return }
        steps = newSteps
        minutes = newMinutes
    }

    /// Log one glass (the phone-synced glass size) to Health, then re-read and
    /// refresh the complication. Requests authorization itself so it works
    /// even when `load()` hasn't run yet, and surfaces denial / a failed save
    /// instead of silently dropping the glass.
    func logGlass() async {
        #if DEBUG
        // Capture mode (issue #239): « J'ai bu » is on screen in the hydration
        // capture. Tapping it must save no `dietaryWater` sample — and the card
        // keeps showing the seeded intake, which is what makes the capture
        // reproducible anyway.
        guard !WatchScreenshotMode.isActive else { return }
        #endif
        guard HKHealthStore.isHealthDataAvailable() else { return }
        _ = try? await store.requestAuthorization(toShare: [Self.waterType], read: Self.readTypes)
        waterDenied = store.authorizationStatus(for: Self.waterType) == .sharingDenied
        guard !waterDenied else { return }
        let sample = HKQuantitySample(
            type: Self.waterType,
            quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: Double(hydrationGlassML)),
            start: .now,
            end: .now
        )
        do {
            try await store.save(sample)
            hydrationError = nil
        } catch {
            hydrationError = Self.saveFailedMessage
            return
        }
        WidgetCenter.shared.reloadTimelines(ofKind: WatchComplicationKind.hydration)
        await refreshWater()
    }

    /// Re-read today's water, and nothing else.
    ///
    /// Logging a glass changes one number, so `load()` — authorization plus
    /// five queries — was always more than this needed. It became worth fixing
    /// with issue #281: « J'ai bu » is now reachable *during a session*, where
    /// that path would put an authorization sheet and five queries on a wrist
    /// already running a workout, a motion stream and a clock.
    ///
    /// No capture-mode guard, and it needs none: the only caller returns before
    /// this line when the mode is on.
    private func refreshWater() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        loadGeneration += 1
        let generation = loadGeneration
        let value = Int(await sumToday(.dietaryWater, unit: .literUnit(with: .milli)))
        guard generation == loadGeneration else { return }
        waterML = value
    }

    #if DEBUG
    /// Serve the seeded day (issue #239). Pure assignment — it reads no store
    /// and no clock, so two capture runs put the same numbers on screen
    /// whatever day they run on.
    ///
    /// `hasPhoneSync` is true because the seeded install *is* a paired one:
    /// left false, the home would draw « Ouvre Foulée sur ton iPhone » across
    /// the board. `waterDenied` / `hydrationError` stay at their defaults, so
    /// the hydration card shows its button rather than a warning.
    ///
    /// Internal rather than private: `WatchScreenshotModeTests` calls it
    /// directly, which is how the seeded values are asserted without switching
    /// the mode on for the whole test process.
    func applyScreenshotSeed() {
        let seed = ScreenshotSeed.watchToday
        steps = seed.steps
        minutes = seed.minutes
        distanceKm = seed.distanceKm
        calories = seed.calories
        streak = seed.streak
        stepsGoal = seed.stepsGoal
        minutesGoal = seed.minutesGoal
        waterML = seed.waterML
        hydrationEnabled = true
        hydrationGoalML = seed.hydrationGoalML
        hydrationGlassML = seed.hydrationGlassML
        hasPhoneSync = true
        waterDenied = false
        hydrationError = nil
        isLoading = false
    }
    #endif

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
