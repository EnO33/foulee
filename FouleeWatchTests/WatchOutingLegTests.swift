import Foundation
import Testing
@testable import FouleeWatch

/// Every leg of an outing carries the same outing identifier (issue #316), so
/// the phone can show five workouts in Santé as the one sortie they were.
@MainActor
@Suite("Watch outing legs")
struct WatchOutingLegTests {
    private let base = Date()

    private func estimate(_ activity: SessionActivity, at offset: TimeInterval) -> MotionActivityEstimate {
        motionEstimate(
            startDate: base.addingTimeInterval(offset),
            walking: activity == .walking,
            running: activity == .running
        )
    }

    /// Walk, run, walk: three legs, one outing, indexes in order.
    @Test("Every leg shares the outing, in order")
    func legsShareTheOuting() async {
        let stub = WorkoutHealthKitStub()
        let motion = FakeMotionSource()
        motion.isAvailable = true
        let store = stub.makeStore(detection: WatchActivityDetection(source: motion.source))
        await store.start(activity: .walking)
        await waitUntil { motion.isStreaming }

        for (activity, offset) in [(SessionActivity.running, 60.0), (.walking, 180)] {
            motion.deliver(estimate(activity, at: offset))
            await waitUntil {
                guard case .active(let metrics) = store.state else { return false }
                return metrics.activity == activity
            }
            await store.splitIfDue(at: base.addingTimeInterval(offset + WatchWorkoutStore.minimumLegDuration))
        }

        #expect(stub.outingLegs.map(\.index) == [0, 1, 2])
        #expect(Set(stub.outingLegs.map(\.outingID)).count == 1)
    }

    /// Two outings in a row must never read as one, however close together.
    @Test("A new outing draws a new identifier")
    func outingsAreDistinct() async {
        let stub = WorkoutHealthKitStub()
        let store = stub.makeStore()
        await store.start(activity: .walking)
        await store.stop()
        store.reset()
        await store.start(activity: .walking)

        #expect(stub.outingLegs.map(\.index) == [0, 0])
        #expect(stub.outingLegs.first?.outingID != stub.outingLegs.last?.outingID)
    }

    /// HealthKit accepts only strings, numbers, dates and quantities as
    /// metadata — a raw `UUID` would be refused, and the phone reads a string.
    @Test("The stamp is made of values HealthKit accepts")
    func metadataShape() {
        let id = UUID()
        let metadata = OutingLeg(outingID: id, index: 3).metadata

        #expect(metadata[FouleeWorkoutMetadata.outingID] as? String == id.uuidString)
        #expect(metadata[FouleeWorkoutMetadata.legIndex] as? Int == 3)
        #expect(metadata.count == 2)
    }
}
