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
    /// What detection says is happening right now — the source of the sport
    /// named on screen (issue #250).
    @ObservationIgnored private var currentActivity: SessionActivity = .walking
    /// Segments the builder's delegate reported as ended.
    ///
    /// Kept because `HKLiveWorkoutBuilder.workoutActivities` is documented only
    /// for activities added by hand, and a session's own segments disappearing
    /// from that list would silently zero every per-sport total the moment a
    /// switch happened. Merged with the two live readings, never trusted alone.
    @ObservationIgnored private var endedSegments: [WatchWorkoutSegment] = []

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
        endedSegments = []
        state = .idle
        lastError = nil
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
        endedSegments = []
        state = .active(.empty(for: activity))
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
        applyActivityTotals(to: &metrics, at: .now)
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

    /// The moment a segment's totals stop moving — and the one moment its
    /// figures are certainly complete.
    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didEnd workoutActivity: HKWorkoutActivity
    ) {
        guard let segment = WatchWorkoutSegment(workoutActivity) else { return }
        Task { @MainActor [weak self] in
            self?.recordEndedSegment(segment)
        }
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

    /// Open the first segment and start classifying.
    ///
    /// The session's *main* activity is not enough to record the opening
    /// stretch, and that is the whole reason a nested activity is opened here
    /// rather than only at the first switch. HealthKit's main activity spans
    /// the entire session: on a walk with a run in the middle it would save
    /// « marche, 42 min » covering everything plus « course, 12 min » inside it,
    /// and the 30 minutes actually spent walking would exist nowhere — not in
    /// Santé, and not as anything the watch could show while it happens.
    ///
    /// One nested activity per stretch makes each one a measured object with
    /// its own `startDate`, `endDate` and `allStatistics`. HealthKit does the
    /// segmenting; nothing here recomputes it.
    private func beginActivityDetection(from activity: SessionActivity) {
        let now = Date.now
        currentActivity = activity
        sessionHandle?.beginActivity(Self.configuration(for: activity), now)
        detection.start(from: activity, at: now) { [weak self] confirmed in
            self?.applySwitch(confirmed)
        }
    }

    /// Name the sport being done and total it (issue #250).
    private func applyActivityTotals(to metrics: inout WatchWorkoutMetrics, at now: Date) {
        metrics.activity = currentActivity
        metrics.activityTotals = WatchActivityTotals.of(currentActivity, in: recordedSegments(), at: now)
    }

    /// Refresh the per-activity block on its own.
    ///
    /// Split out of `ingest(builder:)` and internal because that method takes
    /// an `HKLiveWorkoutBuilder`, a type no test can construct — while this
    /// half needs none of it.
    func refreshActivityTotals(at now: Date = .now) {
        guard case .active(var metrics) = state else { return }
        applyActivityTotals(to: &metrics, at: now)
        state = .active(metrics)
    }

    /// Every segment of the running session, from all three sources that know
    /// about them. See `WatchWorkoutSegment.merged(_:)` for why there are
    /// three.
    func recordedSegments() -> [WatchWorkoutSegment] {
        WatchWorkoutSegment.merged([endedSegments, sessionHandle?.segments() ?? []])
    }

    /// Keep a segment the builder's delegate reported as ended.
    ///
    /// Internal so a test can drive it without an `HKWorkoutActivity`, which
    /// cannot be built with statistics.
    func recordEndedSegment(_ segment: WatchWorkoutSegment) {
        endedSegments = WatchWorkoutSegment.merged([endedSegments, [segment]])
    }

    /// Close the running segment and open the next one, both dated from the
    /// moment the device says the activity changed.
    ///
    /// Symmetric on purpose. HealthKit's own model is not — `endCurrentActivity`
    /// « reverts to the main session activity », so coming back to what the
    /// session started as could have been an end with no matching begin. That
    /// shape is one call cheaper and loses the returning stretch entirely: it
    /// would fold back into the main activity, which already covers the whole
    /// session and therefore says nothing about it.
    private func applySwitch(_ confirmed: ActivitySwitchDetector.Switch) {
        guard case .active = state, let handle = sessionHandle else { return }
        handle.endCurrentActivity(confirmed.date)
        handle.beginActivity(Self.configuration(for: confirmed.activity), confirmed.date)
        currentActivity = confirmed.activity
    }
}
