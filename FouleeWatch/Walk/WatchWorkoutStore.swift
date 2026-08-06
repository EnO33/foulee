@preconcurrency import HealthKit
import Observation
import SwiftUI

/// Drives the live walking workout on watchOS via `HKWorkoutSession` +
/// `HKLiveWorkoutBuilder` — the same APIs the Workouts app uses, which
/// gives us real heart-rate, distance and calorie samples instead of the
/// CMPedometer estimates the iPhone target relies on. The HealthKit calls
/// go through the injectable `WatchWorkoutHealthKit` facade.
///
/// State is a tiny three-case enum so the view binds declaratively.
/// Errors funnel through a single boundary (`runOrTrap`); the rest of the
/// store is happy-path.
@MainActor
@Observable
final class WatchWorkoutStore: NSObject {
    enum State: Equatable {
        case idle
        case active(WatchWorkoutMetrics)
        /// `saveFailed` travels with the summary: `endCollection`/
        /// `finishWorkout` can throw after a perfectly good walk, and the
        /// summary screen is the only place the user can still act on it.
        case ended(WatchWorkoutMetrics, saveFailed: Bool)
    }

    private(set) var state: State = .idle
    private(set) var lastError: String?

    @ObservationIgnored private let healthKit: WatchWorkoutHealthKit
    @ObservationIgnored private var sessionHandle: WatchWorkoutSessionHandle?

    init(healthKit: WatchWorkoutHealthKit = .live) {
        self.healthKit = healthKit
        super.init()
    }

    // The live workout builder saves the metrics its data source collects
    // (heart rate, active energy, distance…) as part of the workout, so we must
    // be authorized to *share* them — sharing only `workoutType` makes
    // `finishWorkout()` fail with an authorization error. Unlike the phone, the
    // watch is the authoritative source during a workout, so these don't
    // double-count the daily totals.
    //
    // Derived from `collectedQuantityTypes` rather than spelled out again: the
    // set that must be authorized *is* the set the data source collects, and
    // the two drifting apart is precisely the authorization failure above.
    private static let writeTypes: Set<HKSampleType> = Set(
        collectedQuantityTypes.map { $0 as HKSampleType }
    ).union([HKWorkoutType.workoutType()])
    private static let readTypes: Set<HKObjectType> = Set(writeTypes.map { $0 as HKObjectType })

    /// Begin a fresh session of `activity`. Idempotent: no-op when already
    /// active.
    ///
    /// The activity is a parameter, not a literal, because it decides what
    /// Santé records the session as — and that stamp is permanent (issue
    /// #223). It comes from the mode the phone synced, or from the user
    /// answering the « les deux » question (issue #224); this path is the same
    /// either way.
    func start(activity: SessionActivity) async {
        guard case .idle = state else { return }
        guard healthKit.isAvailable() else {
            lastError = "HealthKit n'est pas disponible sur ce device."
            return
        }
        var writeTypes = Self.writeTypes
        var readTypes = Self.readTypes
        // Starting a walk is the most visible authorization prompt on the
        // watch — ride the water type along when hydration is on, so "J'ai bu"
        // is covered by the same sheet instead of never getting authorized.
        if WatchSyncStore.read()?.hydrationEnabled == true {
            let waterType = HKQuantityType(.dietaryWater)
            writeTypes.insert(waterType)
            readTypes.insert(waterType)
        }
        let granted = await runOrTrap {
            try await healthKit.requestAuthorization(writeTypes, readTypes)
            return true
        }
        guard granted == true else { return }
        await beginSession(activity: activity)
    }

    /// End the session, save the workout and surface a summary. On a save
    /// failure the builder is kept alive so "Réessayer" can finish it.
    func stop() async {
        guard case .active(let metrics) = state, let handle = sessionHandle else { return }
        handle.end()
        let saved = await runOrTrap {
            try await handle.endCollection(.now)
            try await handle.finishWorkout()
            return true as Bool
        }
        if saved == true { sessionHandle = nil }
        state = .ended(metrics, saveFailed: saved != true)
    }

    /// Second attempt at persisting the workout after a failed `stop()`.
    /// Collection may already be over from the first attempt — only finish is
    /// unconditionally retried.
    func retrySave() async {
        guard case .ended(let metrics, saveFailed: true) = state, let handle = sessionHandle else { return }
        let saved = await runOrTrap {
            if handle.collectionEndDate() == nil {
                try await handle.endCollection(.now)
            }
            try await handle.finishWorkout()
            return true as Bool
        }
        guard saved == true else { return }
        sessionHandle = nil
        lastError = nil
        state = .ended(metrics, saveFailed: false)
    }

    /// Return to idle so a new session can start.
    func reset() {
        sessionHandle = nil
        lastError = nil
        state = .idle
    }

    private func beginSession(activity: SessionActivity) async {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activity.hkActivityType
        configuration.locationType = .outdoor

        let handle = await runOrTrap {
            try await healthKit.startSession(configuration, self)
        }
        guard let handle else { return }
        sessionHandle = handle
        state = .active(.zero)
    }

    fileprivate func ingest(builder: HKLiveWorkoutBuilder) {
        guard case .active(var metrics) = state else { return }
        metrics.elapsed = builder.elapsedTime(at: .now)
        metrics.steps = Int(sumDouble(builder.statistics(for: HKQuantityType(.stepCount)), unit: .count()))
        metrics.distanceMeters = sumDouble(
            builder.statistics(for: HKQuantityType(.distanceWalkingRunning)),
            unit: .meter()
        )
        metrics.activeCalories = Int(sumDouble(
            builder.statistics(for: HKQuantityType(.activeEnergyBurned)),
            unit: .kilocalorie()
        ))
        metrics.heartRate = mostRecent(
            builder.statistics(for: HKQuantityType(.heartRate)),
            unit: HKUnit(from: "count/min")
        )
        state = .active(metrics)
    }

    private func sumDouble(_ statistics: HKStatistics?, unit: HKUnit) -> Double {
        statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
    }

    private func mostRecent(_ statistics: HKStatistics?, unit: HKUnit) -> Int? {
        guard let value = statistics?.mostRecentQuantity()?.doubleValue(for: unit) else {
            return nil
        }
        return Int(value)
    }

    private func runOrTrap<T: Sendable>(_ body: () async throws -> T) async -> T? {
        do {
            return try await body()
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }
}

extension WatchWorkoutStore: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        // No-op: state transitions are driven from start/stop on the store.
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            self?.handleSessionFailure(message)
        }
    }

    /// A failed session is dead mid-walk: land on the summary with the save
    /// banner instead of leaving `.active` frozen (the error used to go to
    /// `lastError`, rendered only on the idle screen — after `reset()` had
    /// already cleared it). The handle stays alive so "Réessayer" can still
    /// finish the builder.
    func handleSessionFailure(_ message: String) {
        lastError = message
        guard case .active(let metrics) = state else { return }
        state = .ended(metrics, saveFailed: true)
    }
}

extension WatchWorkoutStore: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        Task { @MainActor [weak self] in
            self?.ingest(builder: workoutBuilder)
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // No event-specific UI; ignore.
    }
}
