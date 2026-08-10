import Foundation
import HealthKit
import Testing
@testable import FouleeWatch

/// What a detected change does to a live session — which, settled by two
/// outings and one error message, is **rename the screen and nothing else**.
///
/// `HKWorkoutActivity` subactivities cannot change sport inside a session:
///
///     Cannot add subactivity of type HKWorkoutActivityTypeRunning
///
/// — on a session whose own type is `.walking`. They exist for multisport, and
/// the multisport parent would drop the session out of {walking, running} and
/// therefore out of the 7-day résumé. Two versions tried to segment anyway and
/// both killed sessions on the wrist.
@MainActor
@Suite("Watch session activity switching")
struct WatchWorkoutActivitySwitchingTests {
    private let base = Date()

    private func estimate(_ activity: SessionActivity, at offset: TimeInterval) -> MotionActivityEstimate {
        motionEstimate(
            startDate: base.addingTimeInterval(offset),
            walking: activity == .walking,
            running: activity == .running
        )
    }

    /// Start a session and hand back both halves.
    ///
    /// The store comes back too, and callers must hold it: the detection — and
    /// with it the only thing listening to the fake — lives exactly as long as
    /// the store does.
    private func startedSession(
        as activity: SessionActivity,
        stub: WorkoutHealthKitStub
    ) async -> (store: WatchWorkoutStore, motion: FakeMotionSource) {
        let motion = FakeMotionSource()
        motion.isAvailable = true
        let store = stub.makeStore(detection: WatchActivityDetection(source: motion.source))
        await store.start(activity: activity)
        await waitUntil { motion.isStreaming }
        return (store, motion)
    }

    /// Deliver enough consistent estimates to confirm a switch.
    private func detect(_ activity: SessionActivity, from motion: FakeMotionSource, at offset: TimeInterval) {
        motion.deliver(estimate(activity, at: offset))
        motion.deliver(estimate(activity, at: offset + 30))
    }

    private func activity(of store: WatchWorkoutStore) -> SessionActivity? {
        guard case .active(let metrics) = store.state else { return nil }
        return metrics.activity
    }

    @Test("A detected run renames what is on screen and leaves the session alone")
    func aDetectedRunOnlyRenames() async {
        let stub = WorkoutHealthKitStub()
        let (store, motion) = await startedSession(as: .walking, stub: stub)

        detect(.running, from: motion, at: 60)
        await waitUntil { self.activity(of: store) == .running }

        #expect(activity(of: store) == .running)
        // The session is exactly as it was: same workout, still running, never
        // restarted and never failed. Two versions failed this on a wrist.
        #expect(stub.startCalls == 1)
        #expect(stub.startedConfiguration?.activityType == .walking)
        #expect(stub.endCalls == 0)
        #expect(stub.finishCalls == 0)
        #expect(store.lastError == nil)
    }

    @Test("Back to walking renames again, still without touching the session")
    func comingBackAlsoOnlyRenames() async {
        let stub = WorkoutHealthKitStub()
        let (store, motion) = await startedSession(as: .walking, stub: stub)

        detect(.running, from: motion, at: 60)
        await waitUntil { self.activity(of: store) == .running }
        detect(.walking, from: motion, at: 300)
        await waitUntil { self.activity(of: store) == .walking }

        #expect(stub.startCalls == 1)
        #expect(stub.endCalls == 0)
        #expect(store.lastError == nil)
    }

    @Test("A run-mode session starts named as a run")
    func aRunSessionOpensAsARun() async {
        let stub = WorkoutHealthKitStub()
        let (store, motion) = await startedSession(as: .running, stub: stub)

        #expect(activity(of: store) == .running)
        detect(.walking, from: motion, at: 60)
        await waitUntil { self.activity(of: store) == .walking }
        // The `HKWorkout` keeps the type the wearer chose — detection never
        // changes what Santé records.
        #expect(stub.startedConfiguration?.activityType == .running)
    }

    @Test("A single aberrant estimate renames nothing")
    func oneEstimateChangesNothing() async {
        let stub = WorkoutHealthKitStub()
        let (store, motion) = await startedSession(as: .walking, stub: stub)

        motion.deliver(estimate(.running, at: 60))
        motion.deliver(estimate(.walking, at: 90))
        // Nothing to wait for, which is the point — give the ingest tasks room
        // to land before concluding they did nothing.
        try? await Task.sleep(for: .milliseconds(120))

        #expect(activity(of: store) == .walking)
    }

    @Test("Stopping the session stops detection")
    func stoppingEndsDetection() async {
        let stub = WorkoutHealthKitStub()
        let motion = FakeMotionSource()
        motion.isAvailable = true
        let store = stub.makeStore(detection: WatchActivityDetection(source: motion.source))
        await store.start(activity: .walking)
        await waitUntil { motion.isStreaming }

        await store.stop()

        // A stream left open outlives the session that justified it — a
        // CoreMotion subscription running against the battery with nothing
        // reading it.
        #expect(motion.closes == 1)
        #expect(!motion.isStreaming)
    }

    @Test("A session that fails mid-walk stops detection too")
    func aFailedSessionStopsDetection() async {
        let stub = WorkoutHealthKitStub()
        let motion = FakeMotionSource()
        motion.isAvailable = true
        let store = stub.makeStore(detection: WatchActivityDetection(source: motion.source))
        await store.start(activity: .walking)
        await waitUntil { motion.isStreaming }

        store.handleSessionFailure("session interrompue")

        // The builder stays alive for « Réessayer », but there is nothing left
        // to name: the session is over.
        #expect(!motion.isStreaming)
        #expect(stub.handleToken != nil)
    }

    @Test("Detection never starts without a session")
    func noSessionMeansNoStream() async {
        let stub = WorkoutHealthKitStub()
        stub.isAvailable = false
        let motion = FakeMotionSource()
        motion.isAvailable = true
        let store = stub.makeStore(detection: WatchActivityDetection(source: motion.source))

        await store.start(activity: .walking)
        try? await Task.sleep(for: .milliseconds(120))

        // HealthKit refused, so there is no session to name anything on — and
        // the motion permission sheet must not be raised for a session that
        // never began.
        #expect(store.state == .idle)
        #expect(motion.opens == 0)
    }

    // MARK: - What the screen is handed

    @Test("Per-sport figures are shown only when HealthKit has measured some")
    func noSegmentsMeansNoFigures() async {
        let stub = WorkoutHealthKitStub()
        let (store, motion) = await startedSession(as: .walking, stub: stub)

        detect(.running, from: motion, at: 60)
        await waitUntil { self.activity(of: store) == .running }
        store.refreshActivityTotals()

        guard case .active(let metrics) = store.state else {
            Issue.record("la séance devrait être en cours")
            return
        }
        // Nothing segments the session any more, so there is nothing to total.
        // The screen must say « Course » and stop there — « Course » next to
        // four zeros reads as a broken counter, not as an absent measurement.
        #expect(metrics.activityTotals == .zero)
        #expect(metrics.activityHeadlineText == "Course")
    }

    @Test("Measured figures are shown, with the sport and its clock")
    func measuredSegmentsAreShown() async {
        let stub = WorkoutHealthKitStub()
        let (store, _) = await startedSession(as: .walking, stub: stub)

        // Whatever HealthKit reports — nothing today, and something again the
        // day segmenting comes back (issue #256).
        stub.segments = [
            WatchWorkoutSegment(
                id: UUID(),
                activity: .walking,
                start: base,
                end: base.addingTimeInterval(724),
                steps: 1_480,
                distanceMeters: 1_830,
                activeCalories: 136
            )
        ]
        store.refreshActivityTotals()

        guard case .active(let metrics) = store.state else {
            Issue.record("la séance devrait être en cours")
            return
        }
        #expect(metrics.activityTotals.steps == 1_480)
        #expect(metrics.activityHeadlineText == "Marche · 12:04")
    }
}

/// The summary screen of a failed session (issue #256).
///
/// A session died outdoors on `v1.38` and the one sentence HealthKit produced
/// to explain it went to `lastError` — rendered only on the home screen, which
/// `reset()` clears on the way there. The message existed and nobody could read
/// it. These pin that it now appears where the failure does, and only there.
@MainActor
@Suite("Watch finished screen")
struct WatchFinishedScreenTests {
    private func screen(saveFailed: Bool, error: String?) -> WatchFinishedView {
        WatchFinishedView(
            metrics: .zero,
            saveFailed: saveFailed,
            errorMessage: error,
            onRetry: {},
            onDone: {}
        )
    }

    @Test("A failed session shows what HealthKit said")
    func aFailureShowsItsReason() {
        #expect(screen(saveFailed: true, error: "boom").reasonText == "boom")
    }

    @Test("A session that saved shows no reason, even when one is lying around")
    func aSuccessStaysQuiet() {
        // `lastError` outlives the failure that set it: a retry that succeeds
        // leaves the old message behind, and printing it under « Bravo » would
        // report a failure that has just been fixed.
        #expect(screen(saveFailed: false, error: "boom").reasonText == nil)
    }

    @Test("A failure HealthKit said nothing about prints nothing")
    func aSilentFailurePrintsNothing() {
        #expect(screen(saveFailed: true, error: nil).reasonText == nil)
    }
}
