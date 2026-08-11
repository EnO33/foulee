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
    /// The legs of this outing that are already saved as their own `HKWorkout`
    /// (issue #265).
    ///
    /// A change of sport ends the running leg and opens another — the way Forme
    /// does it, and the only way Santé ends up with a walk *and* a run.
    /// HealthKit refuses to segment a single session (#256).
    @ObservationIgnored private var finishedLegs: [WatchWorkoutSegment] = []
    /// When the leg in flight began. Its own builder counts from here.
    @ObservationIgnored private var legStartedAt = Date.now
    /// The sport the leg in flight is **recorded** as.
    ///
    /// Not always what the screen says: the display follows detection at once,
    /// the recording waits for `minimumLegDuration`. That gap is deliberate —
    /// see `applySwitch`.
    @ObservationIgnored private var legActivity: SessionActivity = .walking
    /// Distinguishes the leg in flight from the finished ones when they are
    /// folded into one list.
    @ObservationIgnored private var legIdentity = UUID()
    /// What the leg in flight has measured so far, as of the last batch.
    @ObservationIgnored private var currentLeg = WatchActivityTotals.zero
    /// A confirmed change waiting to become a leg (issue #265).
    ///
    /// The screen follows detection immediately; the **recording** waits. A leg
    /// shorter than `minimumLegDuration` is not a stretch of an outing, it is
    /// noise — and every leg costs a permanent workout in Santé. Dated from the
    /// boundary, so waiting costs no accuracy: the split, when it happens, is
    /// back-dated to where the sport actually changed.
    @ObservationIgnored private var pendingSplit: ActivitySwitchDetector.Switch?
    /// The last counters the classifier of issue #267 was able to read.
    ///
    /// Kept rather than replaced on every batch: HealthKit delivers far more
    /// often than there is movement to measure, and a window of half a second
    /// divides into a meaningless cadence.
    @ObservationIgnored private var lastMovementSample: MovementSample?

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
        let granted = await runOrTrap("autorisation HealthKit") {
            try await healthKit.requestAuthorization(writeTypes, readTypes)
            return true
        }
        guard granted == true else { return }
        await beginSession(activity: activity)
    }

    /// End the session, save the workout and surface a summary. On a save
    /// failure the builder is kept alive so "Réessayer" can finish it.
    func stop() async {
        guard case .active(var metrics) = state, let handle = sessionHandle else { return }
        detection.stop()
        let end = Date.now
        handle.end()
        let saved = await runOrTrap("enregistrement de la séance") {
            try await handle.endCollection(end)
            try await handle.finishWorkout()
            return true as Bool
        }
        if saved == true { sessionHandle = nil }

        // Close the leg in flight so every leg of the outing has an end, and
        // the summary can give each sport its own figures (issue #265).
        finishedLegs.append(legInFlight(endingAt: end))
        metrics.legs = finishedLegs
        metrics.elapsed = WatchActivityTotals.of(finishedLegs, at: end).elapsed
        // No basis: the summary shows the final duration, not a clock that
        // keeps running (issue #266).
        metrics.timerBasis = nil
        state = .ended(metrics, saveFailed: saved != true)
    }

    /// Second attempt at persisting the workout after a failed `stop()`.
    /// Collection may already be over from the first attempt — only finish is
    /// unconditionally retried.
    func retrySave() async {
        guard case .ended(let metrics, saveFailed: true) = state, let handle = sessionHandle else { return }
        let saved = await runOrTrap("nouvel essai d'enregistrement") {
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
        finishedLegs = []
        pendingSplit = nil
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
        let now = Date.now
        let handle = await runOrTrap("ouverture de la séance") {
            try await healthKit.startSession(Self.configuration(for: activity), now, self)
        }
        guard let handle else { return }
        sessionHandle = handle
        finishedLegs = []
        legStartedAt = now
        legActivity = activity
        legIdentity = UUID()
        currentLeg = .zero
        pendingSplit = nil
        lastMovementSample = nil
        state = .active(.empty(for: activity))
        beginActivityDetection(from: activity)
    }

    func ingest(builder: HKLiveWorkoutBuilder) {
        guard case .active(var metrics) = state else { return }
        let now = Date.now
        // The builder counts **this leg**. Every leg before it is already a
        // saved workout with its own builder, so the outing's figures are the
        // sum — the screen must never fall back to the leg's own counters, or
        // it would reset to zero the moment the sport changed.
        currentLeg = WatchActivityTotals(
            elapsed: builder.elapsedTime(at: now),
            steps: Int(sumDouble(builder.statistics(for: HKQuantityType(.stepCount)), unit: .count())),
            distanceMeters: sumDouble(
                builder.statistics(for: HKQuantityType(.distanceWalkingRunning)),
                unit: .meter()
            ),
            activeCalories: Int(sumDouble(
                builder.statistics(for: HKQuantityType(.activeEnergyBurned)),
                unit: .kilocalorie()
            ))
        )
        applyOutingTotals(to: &metrics, at: now)
        metrics.heartRate = mostRecent(
            builder.statistics(for: HKQuantityType(.heartRate)),
            unit: HKUnit(from: "count/min")
        )
        state = .active(metrics)
        classifyMovement(steps: metrics.steps, distanceMeters: metrics.distanceMeters, at: now)
        Task { await self.splitIfDue(at: now) }
    }

    /// A failed session is dead mid-walk: land on the summary with the save
    /// banner instead of leaving `.active` frozen (the error used to go to
    /// `lastError`, rendered only on the idle screen — after `reset()` had
    /// already cleared it). The handle stays alive so "Réessayer" can still
    /// finish the builder.
    func handleSessionFailure(_ message: String) {
        lastError = message
        // The path of issue #256, and the one the console has to survive: the
        // session died on its own, so nothing here chose to stop.
        FouleeLog.session.error("séance interrompue : \(message, privacy: .public)")
        // Whatever the session's fate, there is nothing left to switch: keep
        // the builder alive for "Réessayer", but let the motion stream go.
        detection.stop()
        guard case .active(let metrics) = state else { return }
        state = .ended(metrics, saveFailed: true)
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

    /// The log line is the whole of issue #273. `lastError` reaches a screen,
    /// but only sometimes and only while that screen lives — a failed split
    /// mid-outing left nothing behind at all. And HealthKit's own sentence says
    /// nothing about *which* of the six calls funnelling through here produced
    /// it, which is the question a wrist test has to answer.
    ///
    /// - Parameter step: names the call, for the log only. `lastError` keeps
    ///   HealthKit's wording, which reads better on a wrist.
    private func runOrTrap<T: Sendable>(
        _ step: StaticString,
        _ body: () async throws -> T
    ) async -> T? {
        do {
            return try await body()
        } catch {
            lastError = error.localizedDescription
            FouleeLog.session.error(
                "\(step, privacy: .public) : \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }
}

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

    /// Start classifying. **Records nothing into the session** — see
    /// `applySwitch`.
    /// Read the session's own counters as a second, much faster opinion on
    /// what the wearer is doing (issue #267).
    ///
    /// CoreMotion takes around thirty seconds to change its mind — its
    /// smoothing is its purpose. Cadence and speed change within one window,
    /// and they cost nothing new: these are the counters already driving the
    /// screen. Both feed the same detector, so nothing about the decision
    /// depends on which noticed first.
    private func classifyMovement(steps: Int, distanceMeters: Double, at now: Date) {
        let sample = MovementSample(date: now, steps: steps, distanceMeters: distanceMeters)
        guard let previous = lastMovementSample else {
            lastMovementSample = sample
            return
        }
        guard let observation = MovementClassifier.observation(from: previous, to: sample) else {
            // Not enough of a change to read. Keep the older sample so the
            // window keeps widening rather than restarting on every batch.
            return
        }
        lastMovementSample = sample
        detection.ingest(observation)
    }

    private func beginActivityDetection(from activity: SessionActivity) {
        let now = Date.now
        currentActivity = activity
        detection.start(from: activity, at: now) { [weak self] confirmed in
            self?.applySwitch(confirmed)
        }
    }

    /// The shortest stretch that deserves a workout of its own.
    ///
    /// Chosen with the user, and low on purpose: they would rather tidy an
    /// occasional stray workout than lose the accuracy of a boundary. Below
    /// this a leg is shorter than the gap between two readings — noise, not an
    /// observation.
    static let minimumLegDuration: TimeInterval = 15

    /// Name the sport being done and total the **outing** — every leg, not the
    /// one in flight (issue #265).
    private func applyOutingTotals(to metrics: inout WatchWorkoutMetrics, at now: Date) {
        let legs = allLegs()
        metrics.activity = currentActivity
        metrics.legs = legs
        let outing = WatchActivityTotals.of(legs, at: now)
        metrics.elapsed = outing.elapsed
        metrics.steps = outing.steps
        metrics.distanceMeters = outing.distanceMeters
        metrics.activeCalories = outing.activeCalories
        // The instant the clock would have read zero, so the screen can run it
        // on its own between batches (issue #266).
        metrics.timerBasis = now.addingTimeInterval(-outing.elapsed)
        metrics.activityTotals = WatchActivityTotals.of(currentActivity, in: legs, at: now)
    }

    /// Refresh the totals on their own.
    ///
    /// Split out of `ingest(builder:)` and internal because that method takes
    /// an `HKLiveWorkoutBuilder`, a type no test can construct — while this
    /// half needs none of it.
    func refreshActivityTotals(at now: Date = .now) {
        guard case .active(var metrics) = state else { return }
        applyOutingTotals(to: &metrics, at: now)
        state = .active(metrics)
    }

    /// Every leg of the outing: those already saved, plus the one in flight.
    private func allLegs() -> [WatchWorkoutSegment] {
        finishedLegs + [legInFlight(endingAt: nil)]
    }

    private func legInFlight(endingAt end: Date?) -> WatchWorkoutSegment {
        WatchWorkoutSegment(
            id: legIdentity,
            activity: legActivity,
            start: legStartedAt,
            end: end,
            steps: currentLeg.steps,
            distanceMeters: currentLeg.distanceMeters,
            activeCalories: currentLeg.activeCalories
        )
    }

    /// Note the change on screen at once, and queue the recording.
    ///
    /// **The two halves move at different speeds on purpose.** Renaming cannot
    /// fail and cannot be wrong for long — the next reading corrects it. Cutting
    /// the outing in two writes a permanent workout into Santé, so it waits
    /// until the new sport has held for `minimumLegDuration`.
    ///
    /// Waiting costs no accuracy: the split carries `confirmed.date`, the
    /// instant the sport actually changed, and both HealthKit calls accept a
    /// past date.
    private func applySwitch(_ confirmed: ActivitySwitchDetector.Switch) {
        guard case .active = state else { return }
        currentActivity = confirmed.activity
        refreshActivityTotals()
        // Back to what the leg is already recording: whatever was queued is
        // moot, and no workout was created — which is the whole point of
        // waiting.
        pendingSplit = confirmed.activity == legActivity ? nil : confirmed
    }

    /// Cut the outing here, if a queued change has held long enough.
    ///
    /// Called from `ingest`, so it runs at HealthKit's own pace rather than on
    /// a timer of its own — there is nothing to decide between two batches.
    /// Internal so a test can drive it with an explicit clock — `ingest` takes
    /// an `HKLiveWorkoutBuilder`, which no test can build.
    func splitIfDue(at now: Date) async {
        guard case .active = state,
              let pending = pendingSplit,
              now.timeIntervalSince(pending.date) >= Self.minimumLegDuration
        else { return }
        pendingSplit = nil
        await splitLeg(to: pending.activity, at: pending.date)
    }

    /// Close the leg in flight and open the next one at the same instant.
    ///
    /// This is what Forme does when you tap « + » mid-outing, and the only
    /// shape HealthKit allows: a session records one sport, so a second sport
    /// needs a second session (#256).
    ///
    /// **A failure here never costs what came before.** Every finished leg is
    /// already its own saved workout. If the next leg cannot be opened the
    /// outing ends, with the reason on screen — which is a smaller loss than a
    /// session that keeps running while recording nothing.
    private func splitLeg(to activity: SessionActivity, at boundary: Date) async {
        guard let handle = sessionHandle else { return }
        let closed = await runOrTrap("fermeture de la jambe") {
            handle.end()
            try await handle.endCollection(boundary)
            try await handle.finishWorkout()
            return true as Bool
        }
        finishedLegs.append(legInFlight(endingAt: boundary))

        guard closed == true else {
            // The builder is still alive, so « Réessayer » can still finish it.
            endOuting(saveFailed: true)
            return
        }
        sessionHandle = nil

        let next = await runOrTrap("ouverture de la jambe suivante") {
            try await healthKit.startSession(Self.configuration(for: activity), boundary, self)
        }
        guard let next else {
            endOuting(saveFailed: false)
            return
        }
        sessionHandle = next
        legStartedAt = boundary
        legActivity = activity
        legIdentity = UUID()
        currentLeg = .zero
        lastMovementSample = nil
    }

    /// End the outing from inside a split that could not continue.
    private func endOuting(saveFailed: Bool) {
        detection.stop()
        guard case .active(let metrics) = state else { return }
        state = .ended(metrics, saveFailed: saveFailed)
    }
}
