import Foundation
import Testing
@testable import FouleeWatch

/// Pausing an outing started on the wrist (issue #384).
///
/// A pause has to stop three things together — HealthKit, the clock and the
/// detection — or it lies somewhere: a workout longer than the outing, a clock
/// that ran through the coffee, or a leg cut because standing still looked
/// like a change of sport.
@MainActor
@Suite("Watch pause")
struct WatchPauseTests {
    private let base = ManualClock.origin

    // MARK: - The leg's clock

    @Test("A leg's elapsed leaves out the time it was paused")
    func elapsedLeavesOutPauses() {
        var leg = WatchWorkoutSegment(
            id: UUID(), activity: .walking, start: base, end: nil,
            steps: 0, distanceMeters: 0, activeCalories: 0
        )
        leg.pausedDuration = 60
        #expect(leg.elapsed(at: base.addingTimeInterval(600)) == 540)
    }

    @Test("A clock read during a pause stands still")
    func elapsedStandsStillWhilePaused() {
        var leg = WatchWorkoutSegment(
            id: UUID(), activity: .walking, start: base, end: nil,
            steps: 0, distanceMeters: 0, activeCalories: 0
        )
        leg.pausedSince = base.addingTimeInterval(300)
        #expect(leg.elapsed(at: base.addingTimeInterval(300)) == 300)
        #expect(leg.elapsed(at: base.addingTimeInterval(900)) == 300)
    }

    // MARK: - The store

    private func elapsed(of store: WatchWorkoutStore) -> TimeInterval? {
        guard case .active(let metrics) = store.state else { return nil }
        return metrics.elapsed
    }

    @Test("Pause and resume reach HealthKit, and the outing's clock skips the pause")
    func pauseAndResume() async {
        let stub = WorkoutHealthKitStub()
        let clock = stub.clock
        let store = stub.makeStore()
        await store.start(activity: .walking)

        clock.advance(by: 10)
        store.pause()
        clock.advance(by: 60)
        store.refreshActivityTotals(at: clock.now)
        #expect(store.isPaused)
        #expect(elapsed(of: store) == 10)
        if case .active(let metrics) = store.state {
            #expect(metrics.isPaused)
            #expect(metrics.timerBasis == nil)
        }

        store.resume()
        clock.advance(by: 30)
        store.refreshActivityTotals(at: clock.now)
        #expect(!store.isPaused)
        #expect(elapsed(of: store) == 40)
        #expect(stub.pauseCalls == 1)
        #expect(stub.resumeCalls == 1)
    }

    @Test("Pausing twice, or resuming a running outing, does nothing")
    func pauseIsIdempotent() async {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()
        await store.start(activity: .walking)

        store.resume()
        store.pause()
        store.pause()
        #expect(stub.pauseCalls == 1)
        #expect(stub.resumeCalls == 0)
    }

    @Test("A pause stops the detection, and drops a change waiting to be cut")
    func aPauseNeverCutsALeg() async {
        let stub = WorkoutHealthKitStub()
        let motion = FakeMotionSource()
        motion.isAvailable = true
        let clock = stub.clock
        let store = stub.makeStore(detection: WatchActivityDetection(source: motion.source, pedometer: .inert))
        await store.start(activity: .walking)
        await waitUntil { motion.isStreaming }

        clock.advance(by: 120)
        motion.deliver(motionEstimate(startDate: base.addingTimeInterval(60), running: true))
        store.pause()
        #expect(!motion.isStreaming)
        clock.advance(by: WatchWorkoutStore.minimumLegDuration * 4)
        await store.splitIfDue(at: clock.now)
        #expect(stub.startCalls == 1, "a pause must not open a second leg")

        store.resume()
        await waitUntil { motion.isStreaming }
    }

    @Test("The phone is told the outing is paused")
    func theSnapshotSaysPaused() {
        var metrics = WatchWorkoutMetrics.zero
        metrics.isPaused = true
        #expect(metrics.snapshot(at: base, isEnded: false).isPaused)
    }
}
