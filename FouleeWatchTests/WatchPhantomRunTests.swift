import Foundation
import Testing
@testable import FouleeWatch

/// No more phantom runs in the middle of a walk (issue #390).
///
/// The outing that prompted it: 57 minutes of walking, with a « run » of 60 m
/// in 1'19" — 2,6 km/h, half the walk's own pace — written into Santé as its
/// own workout. Three rules now stand between a stray reading and a workout.
@MainActor
@Suite("Phantom runs")
struct WatchPhantomRunTests {
    private let base = Date(timeIntervalSince1970: 1_754_000_000)

    private func at(_ offset: TimeInterval) -> Date { base.addingTimeInterval(offset) }

    // MARK: - The distance trail

    @Test("A stretch's speed is its distance over its time, interpolated at both ends")
    func trailSpeed() {
        var trail = DistanceTrail()
        trail.record(MovementSample(date: at(0), distanceMeters: 0))
        trail.record(MovementSample(date: at(100), distanceMeters: 300))
        trail.record(MovementSample(date: at(200), distanceMeters: 600))
        #expect(trail.speed(from: at(50), to: at(150)) == 3)
    }

    @Test("A trail that began after the stretch, or a stretch too short, says nothing")
    func trailSaysNothingWithoutEvidence() {
        var trail = DistanceTrail()
        trail.record(MovementSample(date: at(100), distanceMeters: 0))
        trail.record(MovementSample(date: at(200), distanceMeters: 300))
        #expect(trail.speed(from: at(50), to: at(200)) == nil)
        #expect(trail.speed(from: at(150), to: at(155)) == nil)
    }

    // MARK: - The store

    private func runningSession(
        stub: WorkoutHealthKitStub
    ) async -> (store: WatchWorkoutStore, motion: FakeMotionSource) {
        let motion = FakeMotionSource()
        motion.isAvailable = true
        let store = stub.makeStore(detection: WatchActivityDetection(source: motion.source, pedometer: .inert))
        await store.start(activity: .walking)
        await waitUntil { motion.isStreaming }
        return (store, motion)
    }

    private func detectRun(_ motion: FakeMotionSource, store: WatchWorkoutStore, at offset: TimeInterval) async {
        motion.deliver(motionEstimate(startDate: at(offset), running: true))
        await waitUntil {
            guard case .active(let metrics) = store.state else { return false }
            return metrics.activity == .running
        }
    }

    /// Walk the trail at `speed` m/s from `from` to `to`, one reading a second.
    private func move(_ store: WatchWorkoutStore, at speed: Double, from: TimeInterval, to: TimeInterval) {
        for second in stride(from: from, through: to, by: 1) {
            store.recordMovement(distanceMeters: speed * second, at: at(second))
        }
    }

    @Test("A run is held for 45 s before it is recorded, a walk for 15")
    func aRunWaitsLonger() async {
        #expect(WatchWorkoutStore.minimumLegDuration(becoming: .running) == 45)
        #expect(WatchWorkoutStore.minimumLegDuration(becoming: .walking) == 15)

        let stub = WorkoutHealthKitStub()
        let (store, motion) = await runningSession(stub: stub)
        await detectRun(motion, store: store, at: 60)
        await store.splitIfDue(at: at(60 + 30))
        #expect(stub.startedLegs.count == 1, "30 s is not a run yet")
        await store.splitIfDue(at: at(60 + 45))
        #expect(stub.startedLegs.count == 2)
    }

    @Test("The phantom: a « run » at a walking pace is dropped, and the walk goes on")
    func aRunAtWalkingPaceIsDropped() async {
        let stub = WorkoutHealthKitStub()
        let (store, motion) = await runningSession(stub: stub)
        // 60 m in 79 s — the outing that prompted the issue.
        move(store, at: 60.0 / 79, from: 0, to: 200)
        await detectRun(motion, store: store, at: 100)
        await store.splitIfDue(at: at(100 + WatchWorkoutStore.minimumRunDuration))

        #expect(stub.startedLegs.count == 1, "no workout for a run nobody ran")
        guard case .active(let metrics) = store.state else {
            Issue.record("the outing must go on")
            return
        }
        #expect(metrics.activity == .walking)
    }

    @Test("A run at a running pace is recorded")
    func aRealRunIsRecorded() async {
        let stub = WorkoutHealthKitStub()
        let (store, motion) = await runningSession(stub: stub)
        move(store, at: 3, from: 0, to: 200)
        await detectRun(motion, store: store, at: 100)
        await store.splitIfDue(at: at(100 + WatchWorkoutStore.minimumRunDuration))

        #expect(stub.startedLegs.count == 2)
        #expect(stub.startedLegs.last?.configuration.activityType == .running)
    }
}
