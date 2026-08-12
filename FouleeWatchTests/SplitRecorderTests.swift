import Foundation
import Testing
@testable import FouleeWatch

/// Kilometre boundaries, and when they were crossed (issue #301).
///
/// Pure arithmetic over the two numbers the store already computes, which is
/// the only reason any of it is checkable: a split that is a few seconds out
/// looks exactly like a split that is right.
@Suite("Split recorder")
struct SplitRecorderTests {
    /// Walk at `speed` m/s, one reading every `every` seconds.
    private func run(
        _ recorder: inout SplitRecorder,
        at speed: Double,
        for seconds: TimeInterval,
        every: TimeInterval = 5,
        from elapsed: TimeInterval = 0,
        distance: Double = 0
    ) -> (elapsed: TimeInterval, distance: Double) {
        var now = elapsed
        var covered = distance
        while now < elapsed + seconds {
            now += every
            covered += speed * every
            recorder.record(distanceMeters: covered, elapsed: now)
        }
        return (now, covered)
    }

    @Test("Under a kilometre there is nothing to say")
    func nothingBeforeTheFirstKilometre() {
        var recorder = SplitRecorder()
        _ = run(&recorder, at: 2, for: 400)
        #expect(recorder.splits.isEmpty)
    }

    /// 2 m/s is 500 s a kilometre. The boundary falls between two readings, so
    /// this only lands on 500 if it is interpolated.
    @Test("A kilometre is timed where it was crossed, not where it was noticed")
    func theBoundaryIsInterpolated() {
        var recorder = SplitRecorder()
        _ = run(&recorder, at: 2, for: 600, every: 7)

        #expect(recorder.splits.count == 1)
        #expect(recorder.splits.first?.kilometre == 1)
        #expect(recorder.splits.first?.duration == 500)
    }

    /// Without interpolation the error lands on **two** kilometres — one too
    /// long, the next too short — so a run of them is where it shows.
    @Test("Several kilometres in a row each carry their own time")
    func consecutiveKilometresAreExact() {
        var recorder = SplitRecorder()
        _ = run(&recorder, at: 2.5, for: 1_400, every: 9)

        #expect(recorder.splits.count == 3)
        for split in recorder.splits {
            #expect(abs(split.duration - 400) < 0.001, "km \(split.kilometre) drifted")
        }
    }

    /// A long gap between deliveries can straddle a whole kilometre.
    @Test("A reading that jumps two kilometres records both")
    func aJumpRecordsEveryBoundary() {
        var recorder = SplitRecorder()
        recorder.record(distanceMeters: 0, elapsed: 0)
        recorder.record(distanceMeters: 2_400, elapsed: 1_200)

        #expect(recorder.splits.map(\.kilometre) == [1, 2])
        #expect(recorder.splits.first?.duration == 500)
        #expect(recorder.splits.last?.duration == 500)
    }

    /// HealthKit revises distance downwards — the repository has a test for
    /// exactly that elsewhere. A dip must not let a boundary be crossed twice.
    @Test("A distance revised downwards cannot re-cross a boundary")
    func aRevisionDoesNotDuplicate() {
        var recorder = SplitRecorder()
        recorder.record(distanceMeters: 0, elapsed: 0)
        recorder.record(distanceMeters: 1_100, elapsed: 550)
        #expect(recorder.splits.count == 1)

        // Revised down, then back up past the same boundary.
        recorder.record(distanceMeters: 980, elapsed: 560)
        recorder.record(distanceMeters: 1_150, elapsed: 600)

        #expect(recorder.splits.count == 1, "km 1 was already recorded")
    }

    /// The kilometres partition the outing: their durations add up to the time
    /// at which the last boundary was crossed, with nothing lost between them.
    @Test("The kilometres do not overlap and do not leave gaps")
    func theKilometresPartitionTheOuting() {
        var recorder = SplitRecorder()
        // Speed changes halfway, so the two kilometres are genuinely unequal.
        let first = run(&recorder, at: 2, for: 600, every: 5)
        _ = run(&recorder, at: 4, for: 400, every: 5, from: first.elapsed, distance: first.distance)

        #expect(recorder.splits.count == 2)
        let total = recorder.splits.map(\.duration).reduce(0, +)
        // The first phase reaches 1 200 m, so km 1 is entirely at 2 m/s
        // (500 s) and km 2 entirely at 4 m/s from there (200 m of the first
        // phase are already past the boundary — 800 m at 4 m/s is 200 s, and
        // km 2 begins at 500 s, so it is crossed at 800 s).
        //
        // The invariant is what matters: the durations sum to the instant the
        // last boundary was crossed, with nothing lost between kilometres.
        #expect(abs(total - 800) < 0.001)
    }

    @Test("A reading that does not move the clock is ignored")
    func aStillClockIsIgnored() {
        var recorder = SplitRecorder()
        recorder.record(distanceMeters: 0, elapsed: 0)
        recorder.record(distanceMeters: 1_200, elapsed: 0)
        #expect(recorder.splits.isEmpty)
    }
}
