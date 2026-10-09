import Foundation
import Testing
@testable import FouleeWatch

/// The wrist carrying on a walk the phone handed over (issue #335): one
/// outing, the phone's leg first, the wrist's next.
@MainActor
@Suite("Watch handoff continuation")
struct WatchHandoffContinuationTests {
    private func handoff(endedAgo: TimeInterval = 2) -> SessionHandoff {
        let end = Date.now.addingTimeInterval(-endedAgo)
        return SessionHandoff(
            outingID: UUID(),
            phoneLeg: SessionHandoff.Leg(
                activity: .running, start: end.addingTimeInterval(-600), end: end,
                steps: 1_800, distanceMeters: 1_600, activeCalories: 140
            )
        )
    }

    @Test("The wrist opens leg 1 of the phone's outing, where the phone stopped")
    func opensTheNextLeg() async {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()
        let handed = handoff()
        await store.start(activity: .running, continuing: handed)

        #expect(stub.outingLegs == [handed.continuingLeg])
        #expect(stub.startedLegs.first?.at == handed.handedOverAt)
    }

    /// The phone's ten minutes are on screen from the first second, not lost
    /// with the phone's session.
    @Test("The outing's totals include the phone's leg from the start")
    func totalsIncludeThePhone() async {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()
        await store.start(activity: .running, continuing: handoff())

        guard case .active(let metrics) = store.state else {
            Issue.record("expected an active session, got \(store.state)")
            return
        }
        #expect(metrics.steps >= 1_800)
        #expect(metrics.distanceMeters >= 1_600)
        #expect(metrics.elapsed >= 600)
        #expect(metrics.legs.first?.activity == .running)
    }

    /// The phone saved its own leg: the next one at the wrist is 2, not 1.
    @Test("The legs after carry on the outing's numbering")
    func nextLegIsTwo() async {
        let stub = WorkoutHealthKitStub()
        let motion = FakeMotionSource()
        motion.isAvailable = true
        let store = stub.makeStore(detection: WatchActivityDetection(source: motion.source, pedometer: .inert))
        let handed = handoff()
        await store.start(activity: .running, continuing: handed)
        await waitUntil { motion.isStreaming }

        let switchedAt = Date.now.addingTimeInterval(60)
        motion.deliver(motionEstimate(startDate: switchedAt, walking: true, running: false))
        await waitUntil {
            guard case .active(let metrics) = store.state else { return false }
            return metrics.activity == .walking
        }
        await store.splitIfDue(at: switchedAt.addingTimeInterval(WatchWorkoutStore.minimumLegDuration))

        #expect(stub.outingLegs.map(\.index) == [1, 2])
        #expect(Set(stub.outingLegs.map(\.outingID)) == [handed.outingID])
    }
}
