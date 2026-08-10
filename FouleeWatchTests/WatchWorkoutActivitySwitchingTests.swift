import Foundation
import HealthKit
import Testing
@testable import FouleeWatch

/// What a detected change actually does to the live HealthKit session
/// (issue #249): the last link, from a confirmed switch to
/// `beginNewActivity` / `endCurrentActivity`.
///
/// The rule being pinned is **one nested `HKWorkoutActivity` per stretch, from
/// the first second of the session**, and it is the one thing here that is easy
/// to get wrong in a way nothing complains about. HealthKit's main activity
/// spans the whole session, so a walk→run→walk outing recorded against it would
/// save « marche, 42 min » covering everything plus « course, 12 min » inside —
/// and the half hour actually walked would exist in no object at all. Every
/// switch therefore ends the running segment and opens the next, symmetrically,
/// even when the next one is what the session started as.
@MainActor
@Suite("Watch session activity switching")
struct WatchWorkoutActivitySwitchingTests {
    /// Anchored to real time, unlike the pure suite's fixed epoch, and not by
    /// accident: the store stamps the session start with its own `.now`, and
    /// every boundary is clamped to be at or after it. Estimates from a fixed
    /// past would all clamp to the session start and the dates asserted below
    /// would stop meaning anything. Every offset used here is a minute or more,
    /// so the microseconds between this and the store's stamp cannot matter.
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
    /// The store comes back too, and callers must hold it: the detection —
    /// and with it the only thing listening to the fake — lives exactly as long
    /// as the store does.
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

    @Test("The opening stretch is a segment of its own, from the first second")
    func theSessionOpensItsFirstSegmentImmediately() async {
        let stub = WorkoutHealthKitStub()
        let (store, _) = await startedSession(as: .walking, stub: stub)

        // Without this the opening stretch would be recorded only by the main
        // activity, which covers the entire session and therefore describes no
        // stretch in particular.
        #expect(stub.beganActivities.count == 1)
        #expect(stub.beganActivities.first?.configuration.activityType == .walking)
        #expect(stub.beganActivities.first?.configuration.locationType == .outdoor)
        #expect(stub.endedActivityDates.isEmpty)
        #expect(store.state == .active(.zero))
    }

    @Test("A walk that turns into a run closes the walk and opens the run")
    func aDetectedRunOpensItsOwnSegment() async {
        let stub = WorkoutHealthKitStub()
        let (store, motion) = await startedSession(as: .walking, stub: stub)

        detect(.running, from: motion, at: 60)
        await waitUntil { stub.beganActivities.count == 2 }

        // Not a relabelling: Apple's header says the sensor algorithms are
        // updated to match, so the watch measures differently from here on.
        #expect(stub.beganActivities.last?.configuration.activityType == .running)
        // Both calls carry the same instant — CoreMotion's own stamp for when
        // the run began, not the moment the second estimate landed. A gap
        // between the two would be time belonging to neither segment.
        #expect(stub.beganActivities.last?.date == base.addingTimeInterval(60))
        #expect(stub.endedActivityDates == [base.addingTimeInterval(60)])
        // The session itself is untouched: the `HKWorkout` stays a walk, which
        // keeps it inside {walking, running} and therefore inside the 7-day
        // résumé (`WorkoutActivityFilter`).
        #expect(stub.startedConfiguration?.activityType == .walking)
        #expect(stub.startCalls == 1)
        // And the session is still running: switching a segment must never
        // stop, restart or otherwise disturb the workout it happens inside.
        #expect(store.state == .active(.zero))
    }

    @Test("Coming back to the starting activity opens a third segment, not a gap")
    func returningToTheStartingActivityOpensItsOwnSegment() async {
        let stub = WorkoutHealthKitStub()
        let (store, motion) = await startedSession(as: .walking, stub: stub)

        detect(.running, from: motion, at: 60)
        await waitUntil { stub.beganActivities.count == 2 }
        detect(.walking, from: motion, at: 300)
        await waitUntil { stub.beganActivities.count == 3 }

        // The failure this guards is the cheaper-looking shape: end the run and
        // stop there, letting the main activity « absorb » the walk that
        // follows. It costs one call less and loses the returning stretch — the
        // main activity already covers the whole session, so folding into it
        // says nothing about the twelve minutes just walked.
        #expect(stub.beganActivities.map(\.configuration.activityType) == [.walking, .running, .walking])
        #expect(stub.endedActivityDates == [base.addingTimeInterval(60), base.addingTimeInterval(300)])
        #expect(store.state == .active(.zero))
    }

    @Test("A run-mode session segments the same way, starting from the run")
    func aRunSessionSegmentsFromTheRun() async {
        let stub = WorkoutHealthKitStub()
        let (store, motion) = await startedSession(as: .running, stub: stub)

        detect(.walking, from: motion, at: 60)
        await waitUntil { stub.beganActivities.count == 2 }
        detect(.running, from: motion, at: 300)
        await waitUntil { stub.beganActivities.count == 3 }

        #expect(stub.beganActivities.map(\.configuration.activityType) == [.running, .walking, .running])
        // Back on the run, and the screen says so — `.zero` names a walk.
        #expect(store.state == .active(.empty(for: .running)))
    }

    @Test("A single aberrant estimate touches the session not at all")
    func oneEstimateChangesNothing() async {
        let stub = WorkoutHealthKitStub()
        let (store, motion) = await startedSession(as: .walking, stub: stub)

        motion.deliver(estimate(.running, at: 60))
        motion.deliver(estimate(.walking, at: 90))
        // Nothing to wait for, which is the point — give the ingest tasks room
        // to land before concluding they did nothing.
        try? await Task.sleep(for: .milliseconds(120))

        // One segment — the opening one — and nothing since.
        #expect(stub.beganActivities.count == 1)
        #expect(stub.endedActivityDates.isEmpty)
        #expect(store.state == .active(.zero))
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
        // to switch: the session is over.
        #expect(!motion.isStreaming)
        #expect(stub.handleToken != nil)
    }

    // MARK: - What the screen is handed (issue #250)

    @Test("The live metrics name the sport being done and total only that sport")
    func metricsCarryTheCurrentSportAndItsTotals() async {
        let stub = WorkoutHealthKitStub()
        let (store, motion) = await startedSession(as: .walking, stub: stub)

        // What HealthKit would report once the run is under way: a closed walk
        // and a run in flight.
        stub.segments = [
            WatchWorkoutSegment(
                id: UUID(),
                activity: .walking,
                start: base,
                end: base.addingTimeInterval(60),
                steps: 90,
                distanceMeters: 70,
                activeCalories: 4
            ),
            WatchWorkoutSegment(
                id: UUID(),
                activity: .running,
                start: base.addingTimeInterval(60),
                end: nil,
                steps: 420,
                distanceMeters: 530,
                activeCalories: 31
            )
        ]
        detect(.running, from: motion, at: 60)
        await waitUntil { stub.beganActivities.count == 2 }
        // `ingest` is what refreshes the block, and it is driven by HealthKit
        // handing over samples — which the stub never does. Drive it the way
        // the builder would.
        store.refreshActivityTotals()

        guard case .active(let metrics) = store.state else {
            Issue.record("la séance devrait être en cours")
            return
        }
        #expect(metrics.activity == .running)
        // The run's figures, not the session's: 90 walking steps must not be
        // in there.
        #expect(metrics.activityTotals.steps == 420)
        #expect(metrics.activityTotals.activeCalories == 31)
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

        // HealthKit refused, so there is no session to switch anything on —
        // and the motion permission sheet must not be raised for a session
        // that never began.
        #expect(store.state == .idle)
        #expect(motion.opens == 0)
    }
}
