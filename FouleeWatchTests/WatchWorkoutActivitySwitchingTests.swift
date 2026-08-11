import Foundation
import HealthKit
import Testing
@testable import FouleeWatch

/// What a detected change does to a live session (issue #265).
///
/// It cuts the outing in two. HealthKit refuses to segment a single session —
/// « Cannot add subactivity of type HKWorkoutActivityTypeRunning », observed on
/// a wrist (#256) — so a second sport needs a second session, closed and
/// reopened at the boundary. It is what Forme does when you tap « + »
/// mid-outing, and the reason Santé ends up with a walk *and* a run.
///
/// **The two halves move at different speeds, and that is the design.**
/// Renaming the screen cannot fail and self-corrects on the next reading. A
/// split writes a permanent workout, so it waits for the new sport to hold —
/// and is back-dated to where the sport actually changed, so waiting costs no
/// accuracy.
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

    private func detect(_ activity: SessionActivity, from motion: FakeMotionSource, at offset: TimeInterval) {
        motion.deliver(estimate(activity, at: offset))
    }

    private func activity(of store: WatchWorkoutStore) -> SessionActivity? {
        guard case .active(let metrics) = store.state else { return nil }
        return metrics.activity
    }

    // MARK: - The screen moves first, the recording follows

    @Test("A detected run renames the screen before anything is recorded")
    func theScreenLeadsTheRecording() async {
        let stub = WorkoutHealthKitStub()
        let (store, motion) = await startedSession(as: .walking, stub: stub)

        detect(.running, from: motion, at: 60)
        await waitUntil { self.activity(of: store) == .running }

        // One leg so far: the outing has not been cut, and no second workout
        // exists in Santé. A leg that short would be noise, not a stretch.
        #expect(stub.startedLegs.count == 1)
        #expect(stub.endCollectionCalls == 0)
        #expect(store.lastError == nil)
    }

    @Test("Once the new sport has held, the outing is cut at the boundary")
    func theSplitIsBackDatedToTheBoundary() async {
        let stub = WorkoutHealthKitStub()
        let (store, motion) = await startedSession(as: .walking, stub: stub)

        detect(.running, from: motion, at: 60)
        await waitUntil { self.activity(of: store) == .running }
        // Long enough after the boundary for the leg to be worth recording.
        await store.splitIfDue(at: base.addingTimeInterval(60 + WatchWorkoutStore.minimumLegDuration))

        #expect(stub.startedLegs.count == 2)
        #expect(stub.startedLegs.last?.configuration.activityType == .running)
        // Both ends carry the *boundary*, not the moment of noticing. A gap
        // between them would be time belonging to neither leg — and the walk
        // would keep the first seconds of the run.
        #expect(stub.startedLegs.last?.at == base.addingTimeInterval(60))
        #expect(stub.endCollectionDates == [base.addingTimeInterval(60)])
    }

    @Test("A change that has not held long enough yet is not recorded")
    func theThresholdIsWaitedOut() async {
        let stub = WorkoutHealthKitStub()
        let (store, motion) = await startedSession(as: .walking, stub: stub)

        detect(.running, from: motion, at: 60)
        await waitUntil { self.activity(of: store) == .running }
        // Still running, but only for a few seconds. Every leg costs a
        // permanent workout in Santé, so a stretch this short is noise.
        await store.splitIfDue(at: base.addingTimeInterval(60 + WatchWorkoutStore.minimumLegDuration - 1))

        #expect(stub.startedLegs.count == 1)
        #expect(stub.endCollectionCalls == 0)

        // One second later it has held long enough — and the boundary is still
        // where the sport changed, so waiting cost no accuracy.
        await store.splitIfDue(at: base.addingTimeInterval(60 + WatchWorkoutStore.minimumLegDuration))
        #expect(stub.startedLegs.count == 2)
        #expect(stub.startedLegs.last?.at == base.addingTimeInterval(60))
    }

    @Test("A change that does not hold leaves the outing whole")
    func aBriefChangeIsNotRecorded() async {
        let stub = WorkoutHealthKitStub()
        let (store, motion) = await startedSession(as: .walking, stub: stub)

        detect(.running, from: motion, at: 60)
        await waitUntil { self.activity(of: store) == .running }
        detect(.walking, from: motion, at: 65)
        await waitUntil { self.activity(of: store) == .walking }
        // Well past the threshold — and still nothing to record, because the
        // queued change was cancelled when the sport came back.
        await store.splitIfDue(at: base.addingTimeInterval(600))

        #expect(stub.startedLegs.count == 1)
        #expect(stub.endCollectionCalls == 0)
    }

    @Test("A run-mode outing cuts the same way, starting from the run")
    func aRunOutingCutsFromTheRun() async {
        let stub = WorkoutHealthKitStub()
        let (store, motion) = await startedSession(as: .running, stub: stub)

        #expect(stub.startedLegs.first?.configuration.activityType == .running)
        detect(.walking, from: motion, at: 60)
        await waitUntil { self.activity(of: store) == .walking }
        await store.splitIfDue(at: base.addingTimeInterval(60 + WatchWorkoutStore.minimumLegDuration))

        #expect(stub.startedLegs.map(\.configuration.activityType) == [.running, .walking])
    }

    // MARK: - A split that fails never costs what came before

    @Test("A leg that cannot be reopened ends the outing rather than recording nothing")
    func aFailedReopenEndsTheOuting() async {
        let stub = WorkoutHealthKitStub()
        let (store, motion) = await startedSession(as: .walking, stub: stub)

        detect(.running, from: motion, at: 60)
        await waitUntil { self.activity(of: store) == .running }
        stub.startError = StubError()
        await store.splitIfDue(at: base.addingTimeInterval(60 + WatchWorkoutStore.minimumLegDuration))

        // The walk is already saved — it was finished before the run was
        // attempted. Carrying on with no session would record nothing while
        // pretending to.
        #expect(stub.finishCalls == 1)
        if case .ended = store.state {} else { Issue.record("la sortie devrait être terminée") }
        #expect(store.lastError == "boom")
    }

    @Test("A leg that cannot be closed keeps the builder for « Réessayer »")
    func aFailedCloseIsRetryable() async {
        let stub = WorkoutHealthKitStub()
        let (store, motion) = await startedSession(as: .walking, stub: stub)

        detect(.running, from: motion, at: 60)
        await waitUntil { self.activity(of: store) == .running }
        stub.finishError = StubError()
        await store.splitIfDue(at: base.addingTimeInterval(60 + WatchWorkoutStore.minimumLegDuration))

        guard case .ended(_, let saveFailed) = store.state else {
            Issue.record("la sortie devrait être terminée")
            return
        }
        // Retryable, and the builder is still alive for it — « Réessayer »
        // finishes the leg that could not be closed.
        #expect(saveFailed)
        #expect(stub.handleToken != nil)
    }

    // MARK: - The rest of the lifecycle is untouched

    @Test("Stopping the session stops detection")
    func stoppingEndsDetection() async {
        let stub = WorkoutHealthKitStub()
        let (store, motion) = await startedSession(as: .walking, stub: stub)

        await store.stop()

        #expect(motion.closes == 1)
        #expect(!motion.isStreaming)
    }

    @Test("A session that fails mid-walk stops detection too")
    func aFailedSessionStopsDetection() async {
        let stub = WorkoutHealthKitStub()
        let (store, motion) = await startedSession(as: .walking, stub: stub)

        store.handleSessionFailure("session interrompue")

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

        #expect(store.state == .idle)
        #expect(motion.opens == 0)
    }
}
