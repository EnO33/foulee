import Foundation
import Testing
@testable import FouleeWatch

/// What the wrist states to the phone, and when (issue #278).
///
/// The link itself is untestable here — it needs a paired iPhone — but
/// everything that decides *what* goes over it is not: the shape of a snapshot,
/// the moments that force one, and the interval that spaces the rest.
@MainActor
@Suite("Mirror snapshots")
struct WatchMirrorSnapshotTests {
    private let base = Date()

    private func estimate(_ activity: SessionActivity, at offset: TimeInterval) -> MotionActivityEstimate {
        motionEstimate(
            startDate: base.addingTimeInterval(offset),
            walking: activity == .walking,
            running: activity == .running
        )
    }

    // MARK: - The shape

    /// The outing's clock is a **date**, not a duration, so the phone keeps
    /// counting between two wakes instead of freezing on the last figure it was
    /// told. Same construction as issue #266, and for the same reason.
    @Test("A snapshot carries the outing's start, not its elapsed time")
    func theClockIsADate() {
        var metrics = WatchWorkoutMetrics.zero
        metrics.timerBasis = base
        // Deliberately inconsistent with the basis: the pushed `elapsed` is a
        // stale snapshot of the clock, and reading it instead of the basis is
        // exactly the mistake issue #266 fixed. The two must not agree here, or
        // this test cannot tell the branches apart.
        metrics.elapsed = 42
        let snapshot = metrics.snapshot(at: base.addingTimeInterval(600), isEnded: false)

        #expect(snapshot.outingStartedAt == base)
        #expect(snapshot.elapsed(at: base.addingTimeInterval(900)) == 900)
    }

    /// A finished session clears its basis so the recap stops counting — the
    /// snapshot still has to state where the outing began.
    @Test("A finished session still states where the outing began")
    func aFinishedSessionFallsBack() {
        var metrics = WatchWorkoutMetrics.zero
        metrics.elapsed = 600
        metrics.timerBasis = nil
        let snapshot = metrics.snapshot(at: base, isEnded: true)

        #expect(snapshot.outingStartedAt == base.addingTimeInterval(-600))
        #expect(snapshot.isEnded)
    }

    @Test("The figures on screen are the figures sent")
    func theFiguresTravel() {
        var metrics = WatchWorkoutMetrics.zero
        metrics.steps = 2_480
        metrics.distanceMeters = 1_830
        metrics.activeCalories = 108
        metrics.heartRate = 118
        metrics.activity = .running
        let snapshot = metrics.snapshot(at: base, isEnded: false)

        #expect(snapshot.steps == 2_480)
        #expect(snapshot.distanceMeters == 1_830)
        #expect(snapshot.activeCalories == 108)
        #expect(snapshot.heartRate == 118)
        #expect(snapshot.activity == .running)
        #expect(snapshot.sentAt == base)
    }

    // MARK: - When

    @Test("The start of an outing is sent at once, without waiting the interval")
    func theStartIsSentImmediately() async {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()
        await store.start(activity: .walking)
        await store.mirrorIfDue(at: base)

        #expect(stub.sentSnapshots.count == 1)
        #expect(stub.sentSnapshots.first?.isEnded == false)
    }

    /// Not one message per second. HealthKit caches what a mirrored session
    /// sends and wakes the phone periodically, so a higher rate buys no
    /// freshness and costs CPU on a watch that can be suspended for using it.
    @Test("Between two ticks nothing is sent")
    func theIntervalIsRespected() async {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()
        await store.start(activity: .walking)
        await store.mirrorIfDue(at: base)

        await store.mirrorIfDue(at: base.addingTimeInterval(WatchWorkoutStore.mirrorInterval - 1))
        #expect(stub.sentSnapshots.count == 1)

        await store.mirrorIfDue(at: base.addingTimeInterval(WatchWorkoutStore.mirrorInterval))
        #expect(stub.sentSnapshots.count == 2)
    }

    /// The one signal the phone has that the outing is over. It has to go out
    /// **before** the handle is released on a successful save — which it was
    /// not, on the first draft of this feature.
    @Test("Stopping sends a final snapshot marked ended, even when the save succeeds")
    func theEndIsAlwaysSent() async {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()
        await store.start(activity: .walking)
        await store.stop()

        #expect(stub.sentSnapshots.last?.isEnded == true)
        // And it left while the session was still alive.
        // `sendToRemoteWorkoutSession` needs one; sending after `end()` would
        // have been a send into a corpse, which the stub cannot refuse but a
        // real watch would.
        #expect(stub.sentAfterEnd.last == false)
        // The save succeeded, so the handle is gone — the end still went out.
        #expect(stub.handleToken == nil)
    }

    /// **The inverse of what this test used to assert**, and the change is the
    /// point: a split that fails no longer ends the outing, so it must not tell
    /// the phone that it did. The wearer is still walking; the phone should
    /// still show the sortie.
    ///
    /// Only « Terminer » sends the end — see `theEndIsAlwaysSent`.
    @Test("A split that fails does not tell the phone the outing is over")
    func aFailedSplitDoesNotEndTheMirror() async {
        let stub = WorkoutHealthKitStub()
        let motion = FakeMotionSource()
        motion.isAvailable = true
        let store = stub.makeStore(detection: WatchActivityDetection(source: motion.source))
        await store.start(activity: .walking)
        await waitUntil { motion.isStreaming }
        motion.deliver(estimate(.running, at: 60))
        await waitUntil {
            guard case .active(let metrics) = store.state else { return false }
            return metrics.activity == .running
        }
        stub.endCollectionError = StubError()
        await store.splitIfDue(at: base.addingTimeInterval(60 + WatchWorkoutStore.minimumLegDuration))

        #expect(stub.sentSnapshots.allSatisfy { $0.isEnded == false })
    }

    /// A periodic tick from an ended session would carry `isEnded: false` and
    /// un-end, on the phone, an outing that is over.
    @Test("Nothing is sent by the interval once the outing has ended")
    func nothingTicksAfterTheEnd() async {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()
        await store.start(activity: .walking)
        await store.stop()
        let afterStop = stub.sentSnapshots.count

        await store.mirrorIfDue(at: base.addingTimeInterval(3_600))
        #expect(stub.sentSnapshots.count == afterStop)
        #expect(stub.sentSnapshots.last?.isEnded == true)
    }

    /// A change of sport carries information no tick can: the phone would
    /// otherwise keep naming the previous sport for up to an interval.
    @Test("A change of sport is sent without waiting the interval")
    func aSwitchForcesASend() async {
        let stub = WorkoutHealthKitStub()
        let motion = FakeMotionSource()
        motion.isAvailable = true
        let store = stub.makeStore(detection: WatchActivityDetection(source: motion.source))
        await store.start(activity: .walking)
        await waitUntil { motion.isStreaming }
        motion.deliver(estimate(.running, at: 60))
        await waitUntil {
            guard case .active(let metrics) = store.state else { return false }
            return metrics.activity == .running
        }
        let before = stub.sentSnapshots.count
        await store.splitIfDue(at: base.addingTimeInterval(60 + WatchWorkoutStore.minimumLegDuration))

        #expect(stub.sentSnapshots.count == before + 1)
        #expect(stub.sentSnapshots.last?.activity == .running)
        // Dated now, **never the boundary**. A split is back-dated by up to
        // `minimumLegDuration`, so a snapshot stamped with the boundary would
        // be older than the last periodic send and the phone would drop it on
        // its newest-wins rule — the send would look done and change nothing.
        let boundary = base.addingTimeInterval(60)
        #expect(stub.sentSnapshots.last?.sentAt != boundary)
    }

    // MARK: - What the phone can ask (issue #282)

    /// The point of routing through `stop()` rather than ending the session:
    /// `stop()` closes the leg, folds the outing's figures, saves, and tells
    /// the phone it is over. Ending the session from the command handler would
    /// leave the wrist holding an outing nobody finished.
    @Test("A stop from the phone ends the outing the way the wrist would")
    func aStopCommandStops() async {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()
        await store.start(activity: .walking)

        await store.handle(.stop, from: stub.handleIDs[0])

        guard case .ended(_, let saveFailed) = store.state else {
            Issue.record("a stop from the phone must end the outing")
            return
        }
        #expect(saveFailed == false)
        #expect(stub.endCollectionCalls == 1)
        #expect(stub.finishCalls == 1)
        // And the phone was told, by the same path a wrist-side stop uses.
        #expect(stub.sentSnapshots.last?.isEnded == true)
    }

    /// Same rule as every other callback since issue #290: a command that
    /// arrives on a leg we have already abandoned is not about the outing we
    /// are recording now.
    @Test("A stop addressed to an abandoned leg is ignored")
    func aStopFromAnAbandonedLegIsIgnored() async {
        let stub = WorkoutHealthKitStub()
        let motion = FakeMotionSource()
        motion.isAvailable = true
        let store = stub.makeStore(detection: WatchActivityDetection(source: motion.source))
        await store.start(activity: .walking)
        await waitUntil { motion.isStreaming }
        motion.deliver(estimate(.running, at: 60))
        await waitUntil {
            guard case .active(let metrics) = store.state else { return false }
            return metrics.activity == .running
        }
        await store.splitIfDue(at: base.addingTimeInterval(60 + WatchWorkoutStore.minimumLegDuration))

        await store.handle(.stop, from: stub.handleIDs[0])

        guard case .active = store.state else {
            Issue.record("the outing must survive a command aimed at a closed leg")
            return
        }
    }

    // MARK: - A phone that is not there

    /// The ordinary case, not the exception. A wrist that cannot reach a phone
    /// is still a wrist that is recording perfectly well.
    @Test("A refused send leaves the outing recording")
    func aRefusedSendIsHarmless() async {
        let stub = WorkoutHealthKitStub()
        stub.sendError = StubError()
        let store = stub.makeStore()
        await store.start(activity: .walking)
        await store.mirrorIfDue(at: base)

        #expect(store.state == .active(.empty(for: .walking)))
        #expect(store.lastError == nil)
        // The send was attempted — without this the test passes with the whole
        // mirror path deleted.
        #expect(stub.sentSnapshots.count == 1)
    }
}
