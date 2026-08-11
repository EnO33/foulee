import Foundation
import Testing
@testable import FouleeWatch

/// The session clock (issue #266).
///
/// It used to be a *duration* pushed from the store, written only when
/// HealthKit delivered a batch. The screen wrapped it in a `TimelineView` that
/// rebuilt every second and redrew the same frozen number, so the clock
/// advanced in jerks at HealthKit's pace — and the view's own doc comment
/// claimed the opposite. It is a *date* now, and the clock derives from it.
@Suite("Watch session clock")
struct WatchSessionClockTests {
    private let start = Date(timeIntervalSince1970: 1_754_000_000)

    private func running(since offset: TimeInterval, pushed: TimeInterval = 0) -> WatchWorkoutMetrics {
        var metrics = WatchWorkoutMetrics.zero
        metrics.elapsed = pushed
        metrics.timerBasis = start.addingTimeInterval(-offset)
        return metrics
    }

    @Test("The clock advances without anything being pushed to it")
    func theClockRunsOnItsOwn() {
        // The whole defect, as a value: same metrics, two instants, two
        // readings. Nothing here calls `ingest` — that is the point.
        let metrics = running(since: 0)
        #expect(metrics.elapsed(at: start) == 0)
        #expect(metrics.elapsed(at: start.addingTimeInterval(1)) == 1)
        #expect(metrics.elapsed(at: start.addingTimeInterval(754)) == 754)
    }

    @Test("A stale pushed duration does not hold the clock back")
    func thePushedSnapshotIsNotTheClock() {
        // HealthKit last said « 30 s » a while ago; the session has been
        // running for ten minutes. Before #266 the screen showed 30 s.
        let metrics = running(since: 600, pushed: 30)
        #expect(metrics.elapsed(at: start) == 600)
    }

    @Test("Without a basis the pushed duration is what shows")
    func noBasisFallsBackToTheSnapshot() {
        // Two callers want a value that does not move: the finished summary,
        // and the seeded capture whose board must stay byte-identical.
        var finished = WatchWorkoutMetrics.zero
        finished.elapsed = 1_104
        #expect(finished.timerBasis == nil)
        #expect(finished.elapsed(at: start) == 1_104)
        #expect(finished.elapsed(at: start.addingTimeInterval(3_600)) == 1_104)
    }

    @Test("A clock read before its own start reads zero, never backwards")
    func theClockNeverRunsBackwards() {
        let metrics = running(since: 0)
        #expect(metrics.elapsed(at: start.addingTimeInterval(-60)) == 0)
    }

    #if DEBUG
    @Test("The capture seed has no running clock")
    func theSeededSessionDoesNotTick() {
        // A capture with a live clock could not produce byte-identical files
        // between two runs — the boards are regenerated per release and
        // compared. `nil` basis is what keeps the shutter deterministic.
        #expect(ScreenshotSeed.watchSessionMetrics.timerBasis == nil)
        #expect(
            ScreenshotSeed.watchSessionMetrics.elapsed(at: start)
                == ScreenshotSeed.watchSessionMetrics.elapsed(at: start.addingTimeInterval(9_999))
        )
    }
    #endif
}
