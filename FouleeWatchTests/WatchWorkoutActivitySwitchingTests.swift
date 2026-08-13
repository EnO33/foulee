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

    // MARK: - A split that fails never ends the outing

    /// **Nothing but « Terminer » ends an outing.**
    ///
    /// This used to end it, and it cost a real sortie: on the fifth switch the
    /// next leg could not be opened and the app finished everything — on the
    /// « Bravo » path, so the reason never even reached the screen. The wearer
    /// was still walking.
    @Test("A leg that cannot be reopened leaves the outing running")
    func aFailedReopenKeepsTheOutingAlive() async {
        let stub = WorkoutHealthKitStub()
        let (store, motion) = await startedSession(as: .walking, stub: stub)

        detect(.running, from: motion, at: 60)
        await waitUntil { self.activity(of: store) == .running }
        stub.startError = StubError()
        await store.splitIfDue(at: base.addingTimeInterval(60 + WatchWorkoutStore.minimumLegDuration))

        // The walk is saved — it was finished before the run was attempted —
        // and the outing carries on. Nothing more will be measured, which is a
        // loss; ending the sortie would have been a bigger one.
        #expect(stub.finishCalls == 1)
        guard case .active = store.state else {
            Issue.record("only « Terminer » may end an outing")
            return
        }
        // And the reason is on record rather than swallowed.
        #expect(store.lastError == "boom")
    }

    /// Even with no session left, « Terminer » must work — otherwise the outing
    /// could never be ended at all, which is worse than ending it early.
    @Test("« Terminer » still ends an outing whose session is gone")
    func stopWorksWithoutASession() async {
        let stub = WorkoutHealthKitStub()
        let (store, motion) = await startedSession(as: .walking, stub: stub)

        detect(.running, from: motion, at: 60)
        await waitUntil { self.activity(of: store) == .running }
        stub.startError = StubError()
        await store.splitIfDue(at: base.addingTimeInterval(60 + WatchWorkoutStore.minimumLegDuration))
        await store.stop()

        guard case .ended(_, let saveFailed) = store.state else {
            Issue.record("« Terminer » must end the outing")
            return
        }
        // Nothing to retry: every leg recorded is already saved.
        #expect(saveFailed == false)
    }

    @Test("A leg that cannot be closed leaves the outing running too")
    func aFailedCloseKeepsTheOutingAlive() async {
        let stub = WorkoutHealthKitStub()
        let (store, motion) = await startedSession(as: .walking, stub: stub)

        detect(.running, from: motion, at: 60)
        await waitUntil { self.activity(of: store) == .running }
        stub.finishError = StubError()
        await store.splitIfDue(at: base.addingTimeInterval(60 + WatchWorkoutStore.minimumLegDuration))

        guard case .active = store.state else {
            Issue.record("only « Terminer » may end an outing")
            return
        }
        // The builder is still alive, so « Terminer » can still finish the leg
        // that would not close.
        #expect(stub.handleToken != nil)
        #expect(store.lastError == "boom")
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
