import Foundation
import Testing
@testable import FouleeWatch

@Suite("WatchWorkoutMetrics")
struct WatchWorkoutMetricsTests {
    @Test("zero starts every metric at 0 with no heart-rate reading")
    func zeroBaseline() {
        let metrics = WatchWorkoutMetrics.zero
        #expect(metrics.elapsed == 0)
        #expect(metrics.steps == 0)
        #expect(metrics.distanceMeters == 0)
        #expect(metrics.activeCalories == 0)
        #expect(metrics.heartRate == nil)
    }

    @Test("distanceKm converts from the meters HealthKit reports")
    func distanceConversion() {
        var metrics = WatchWorkoutMetrics.zero
        metrics.distanceMeters = 2_500
        #expect(metrics.distanceKm == 2.5)
    }
}

// Value semantics of the state enum, pinned separately: the view relies on
// these to re-render and to pick the right screen. The store's transitions
// themselves are covered in WatchWorkoutStoreTests via the injectable
// WatchWorkoutHealthKit facade.
@MainActor
@Suite("WatchWorkoutStore.State")
struct WatchWorkoutStateTests {
    @Test("Save failure distinguishes the two summary states")
    func endedStatesCompareBySaveOutcome() {
        let metrics = WatchWorkoutMetrics.zero
        #expect(
            WatchWorkoutStore.State.ended(metrics, saveFailed: true)
                != WatchWorkoutStore.State.ended(metrics, saveFailed: false)
        )
        #expect(
            WatchWorkoutStore.State.ended(metrics, saveFailed: true)
                == WatchWorkoutStore.State.ended(metrics, saveFailed: true)
        )
    }

    @Test("Active states compare by their live metrics")
    func activeStatesCompareByMetrics() {
        var walked = WatchWorkoutMetrics.zero
        walked.steps = 1_200
        #expect(WatchWorkoutStore.State.active(.zero) == .active(.zero))
        #expect(WatchWorkoutStore.State.active(.zero) != .active(walked))
    }

    @Test("The three phases are mutually distinct")
    func phasesAreDistinct() {
        let idle = WatchWorkoutStore.State.idle
        let active = WatchWorkoutStore.State.active(.zero)
        let ended = WatchWorkoutStore.State.ended(.zero, saveFailed: false)
        #expect(idle != active)
        #expect(active != ended)
        #expect(idle != ended)
    }
}
