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
    private let base = Date(timeIntervalSince1970: 1_754_000_000)

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

    /// `value` is `expected`, or later by at most `slack`: the leg started no
    /// earlier than the bracket's start and no later than its end.
    private func isWithin(_ value: TimeInterval?, _ expected: TimeInterval, slack: TimeInterval) -> Bool {
        guard let value else { return false }
        return value >= expected - 0.01 && value <= expected + slack + 0.01
    }

    @Test("Pause and resume reach HealthKit, and the outing's clock skips the pause")
    func pauseAndResume() async {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()
        // The leg is dated inside `start`, somewhere between these two reads:
        // a slow runner can take over a second there, so the clock is checked
        // against that bracket rather than a fixed tolerance.
        let before = Date()
        await store.start(activity: .walking)
        let start = Date()
        let slack = start.timeIntervalSince(before)

        store.pause(at: start.addingTimeInterval(10))
        store.refreshActivityTotals(at: start.addingTimeInterval(70))
        #expect(store.isPaused)
        #expect(isWithin(elapsed(of: store), 10, slack: slack))
        if case .active(let metrics) = store.state {
            #expect(metrics.isPaused)
            #expect(metrics.timerBasis == nil)
        }

        store.resume(at: start.addingTimeInterval(70))
        store.refreshActivityTotals(at: start.addingTimeInterval(100))
        #expect(!store.isPaused)
        #expect(isWithin(elapsed(of: store), 40, slack: slack))
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
        let store = stub.makeStore(detection: WatchActivityDetection(source: motion.source, pedometer: .inert))
        await store.start(activity: .walking)
        await waitUntil { motion.isStreaming }

        motion.deliver(motionEstimate(startDate: base.addingTimeInterval(60), running: true))
        store.pause()
        #expect(!motion.isStreaming)
        await store.splitIfDue(at: .now.addingTimeInterval(WatchWorkoutStore.minimumLegDuration * 4))
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
