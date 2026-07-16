@preconcurrency import HealthKit
import Observation
import SwiftUI

/// Drives the live walking workout on watchOS via `HKWorkoutSession` +
/// `HKLiveWorkoutBuilder` — the same APIs the Workouts app uses, which
/// gives us real heart-rate, distance and calorie samples instead of the
/// CMPedometer estimates the iPhone target relies on.
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

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?

    // The live workout builder saves the metrics its data source collects
    // (heart rate, active energy, distance…) as part of the workout, so we must
    // be authorized to *share* them — sharing only `workoutType` makes
    // `finishWorkout()` fail with an authorization error. Unlike the phone, the
    // watch is the authoritative source during a workout, so these don't
    // double-count the daily totals.
    private static let writeTypes: Set<HKSampleType> = [
        HKWorkoutType.workoutType(),
        HKQuantityType(.stepCount),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.heartRate)
    ]
    private static let readTypes: Set<HKObjectType> = [
        HKQuantityType(.stepCount),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.heartRate),
        HKWorkoutType.workoutType()
    ]

    /// Begin a fresh walking session. Idempotent: no-op when already active.
    func start() async {
        guard case .idle = state else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
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
            try await store.requestAuthorization(
                toShare: writeTypes,
                read: readTypes
            )
            return true
        }
        guard granted == true else { return }
        await beginSession()
    }

    /// End the session, save the workout and surface a summary. On a save
    /// failure the builder is kept alive so "Réessayer" can finish it.
    func stop() async {
        guard case .active(let metrics) = state, let session, let builder else { return }
        session.end()
        let saved = await runOrTrap {
            try await builder.endCollection(at: .now)
            _ = try await builder.finishWorkout()
            return true as Bool
        }
        self.session = nil
        if saved == true { self.builder = nil }
        state = .ended(metrics, saveFailed: saved != true)
    }

    /// Second attempt at persisting the workout after a failed `stop()`.
    /// Collection may already be over from the first attempt — only finish is
    /// unconditionally retried.
    func retrySave() async {
        guard case .ended(let metrics, saveFailed: true) = state, let builder else { return }
        let saved = await runOrTrap {
            if builder.endDate == nil {
                try await builder.endCollection(at: .now)
            }
            _ = try await builder.finishWorkout()
            return true as Bool
        }
        guard saved == true else { return }
        self.builder = nil
        lastError = nil
        state = .ended(metrics, saveFailed: false)
    }

    /// Return to idle so a new session can start.
    func reset() {
        session = nil
        builder = nil
        lastError = nil
        state = .idle
    }

    private func beginSession() async {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .walking
        configuration.locationType = .outdoor

        let started = await runOrTrap {
            let session = try HKWorkoutSession(
                healthStore: store,
                configuration: configuration
            )
            let builder = session.associatedWorkoutBuilder()
            let dataSource = HKLiveWorkoutDataSource(
                healthStore: store,
                workoutConfiguration: configuration
            )
            // The data source infers the types to collect from the config —
            // distance, active energy and heart rate for a walk, but NOT step
            // count. Enable it explicitly, otherwise the live "pas" counter
            // stays at 0 while distance and heart rate update.
            dataSource.enableCollection(for: HKQuantityType(.stepCount), predicate: nil)
            builder.dataSource = dataSource
            session.delegate = self
            builder.delegate = self

            let startDate = Date()
            session.startActivity(with: startDate)
            try await builder.beginCollection(at: startDate)

            self.session = session
            self.builder = builder
            return true
        }
        guard started == true else { return }
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
    /// already cleared it).
    private func handleSessionFailure(_ message: String) {
        lastError = message
        guard case .active(let metrics) = state else { return }
        session = nil
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
