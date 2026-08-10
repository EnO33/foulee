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
    @ObservationIgnored private let detection: WatchActivityDetection
    /// What the session was *started* as, which HealthKit calls the main
    /// activity and stamps on the `HKWorkout` itself. It never changes for the
    /// life of a session: detection opens and closes nested activities around
    /// it, and the parent type stays inside {walking, running} so the session
    /// keeps counting in the 7-day résumé (`WorkoutActivityFilter`).
    @ObservationIgnored private var mainActivity: SessionActivity?

    init(
        healthKit: WatchWorkoutHealthKit = .live,
        detection: WatchActivityDetection = WatchActivityDetection()
    ) {
        self.healthKit = healthKit
        self.detection = detection
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
        #if DEBUG
        // Capture mode (issue #239): show the seeded session and open nothing.
        // It returns before `healthKit` is read, so there is no authorization
        // prompt, no `HKWorkoutSession`, no builder — and `sessionHandle` stays
        // nil, which makes `stop()` and `retrySave()` no-ops too. Nothing this
        // path can reach writes to Santé.
        if WatchScreenshotMode.isActive {
            startScreenshotSession()
            return
        }
        #endif
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
        detection.stop()
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
        detection.stop()
        sessionHandle = nil
        mainActivity = nil
        lastError = nil
        state = .idle
    }

    #if DEBUG
    /// The seeded live session (issue #239): the state a real session would be
    /// in halfway through, with no session behind it.
    ///
    /// Internal rather than folded into the branch above so
    /// `WatchScreenshotModeTests` can call it on a store built with a
    /// **trap** `WatchWorkoutHealthKit` — every closure of which fails the test
    /// if it is called. That is the runtime proof that this path reaches
    /// HealthKit not at all.
    func startScreenshotSession() {
        state = .active(ScreenshotSeed.watchSessionMetrics)
    }
    #endif

    private func beginSession(activity: SessionActivity) async {
        let handle = await runOrTrap {
            try await healthKit.startSession(Self.configuration(for: activity), self)
        }
        guard let handle else { return }
        sessionHandle = handle
        mainActivity = activity
        state = .active(.zero)
        beginActivityDetection(from: activity)
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
        // Whatever the session's fate, there is nothing left to switch: keep
        // the builder alive for "Réessayer", but let the motion stream go.
        detection.stop()
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

/// Automatic walk/run detection during a live session (issue #249).
///
/// In an extension rather than the class body so the state machine above stays
/// the thing you read first, and because none of this is state — the decision
/// is `ActivitySwitchDetector`'s, the stream is `WatchActivityDetection`'s, and
/// what is left here is only the translation into HealthKit's two calls.
extension WatchWorkoutStore {
    /// The configuration HealthKit stamps a session — or one of its nested
    /// activities — with.
    ///
    /// One builder for both, because a nested activity of the same kind must be
    /// configured exactly like the session that would have started as it:
    /// `locationType` drifting between the two would make the same walk measure
    /// differently depending on whether it was chosen or detected.
    static func configuration(for activity: SessionActivity) -> HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activity.hkActivityType
        configuration.locationType = .outdoor
        return configuration
    }

    private func beginActivityDetection(from activity: SessionActivity) {
        detection.start(from: activity, at: .now) { [weak self] confirmed in
            self?.applySwitch(confirmed)
        }
    }

    /// Move the running session onto `confirmed.activity`, as of the moment the
    /// device says it began.
    ///
    /// The asymmetry is HealthKit's, not ours: a session has one *main*
    /// activity that cannot be ended, and at most one nested activity at a
    /// time. So coming back to what the session started as is an *end*, never a
    /// new begin — and since detection only ever moves between two values, a
    /// nested activity is running exactly when the current one differs from the
    /// main one. That invariant is what keeps `beginNewActivity` from being
    /// called twice in a row.
    private func applySwitch(_ confirmed: ActivitySwitchDetector.Switch) {
        guard case .active = state, let handle = sessionHandle, let mainActivity else { return }
        if confirmed.activity == mainActivity {
            handle.endCurrentActivity(confirmed.date)
        } else {
            handle.beginActivity(Self.configuration(for: confirmed.activity), confirmed.date)
        }
    }
}
