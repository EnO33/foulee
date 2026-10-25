import FouleeKit
import Foundation
import Testing
@testable import FouleeWatch

/// The climb and descent of a watch outing, stamped on each leg (issues #535,
/// #564).
@MainActor
@Suite("Watch climb")
struct WatchClimbTests {
    @Test("A leg is stamped with what the outing climbed and descended while it ran")
    func stampedOnSave() async {
        let stub = WorkoutHealthKitStub()
        let climb = WatchClimbStore(source: .inert)
        let store = stub.makeStore(climb: climb)
        await store.start(activity: .walking)
        // Before the leg: the barometer's first reading.
        climb.record(.zero, at: stub.clock.now)
        stub.clock.advance(by: 600)
        climb.record(Elevation(ascent: 85.4, descent: 42), at: stub.clock.now)
        store.refreshActivityTotals(at: stub.clock.now)
        if case .active(let metrics) = store.state {
            #expect(metrics.climbMeters == 85.4)
        } else {
            Issue.record("expected an active outing, got \(store.state)")
        }
        await store.stop()
        #expect(stub.climbs == [Elevation(ascent: 85.4, descent: 42)])
    }

    /// The phone reads no stamp as « not measured »: a flat outing, or a watch
    /// without a barometer, writes none rather than 0 m.
    @Test("Under a metre either way, no stamp")
    func flatOuting() async {
        let stub = WorkoutHealthKitStub()
        let climb = WatchClimbStore(source: .inert)
        let store = stub.makeStore(climb: climb)
        await store.start(activity: .walking)
        climb.record(Elevation(ascent: 0.4, descent: 0.6), at: stub.clock.now)
        await store.stop()
        #expect(stub.climbs.isEmpty)
        #expect(stub.finishCalls == 1)
    }

    @Test("The summary carries the climb after the distance, when there is one")
    func summaryFigures() {
        var metrics = WatchWorkoutMetrics.zero
        metrics.steps = 3_100
        metrics.distanceMeters = 2_400
        let flat = WatchFinishedView(metrics: metrics, saveFailed: false, errorMessage: nil, onRetry: {}, onDone: {})
        #expect(!flat.figuresText.contains("↑"))
        metrics.climbMeters = 119.6
        let hilly = WatchFinishedView(metrics: metrics, saveFailed: false, errorMessage: nil, onRetry: {}, onDone: {})
        #expect(hilly.figuresText.hasSuffix(" · ↑ 120 m"))
    }
}
