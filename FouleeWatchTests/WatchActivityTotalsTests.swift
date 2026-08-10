import Foundation
import Testing
@testable import FouleeWatch

/// Per-sport totals, the arithmetic half of issue #250.
///
/// HealthKit measures each segment; this adds up the segments of one sport and
/// nothing else. Pure, so the cases that matter — an outing that alternates, a
/// segment still running, three sources disagreeing about the same list — are
/// stated here rather than hoped for on a wrist.
@Suite("Watch per-activity totals")
struct WatchActivityTotalsTests {
    private let base = Date(timeIntervalSince1970: 1_754_000_000)

    private func segment(
        _ activity: SessionActivity,
        from: TimeInterval,
        to: TimeInterval?,
        steps: Int = 0,
        metres: Double = 0,
        kcal: Int = 0,
        id: UUID = UUID()
    ) -> WatchWorkoutSegment {
        WatchWorkoutSegment(
            id: id,
            activity: activity,
            start: base.addingTimeInterval(from),
            end: to.map { base.addingTimeInterval($0) },
            steps: steps,
            distanceMeters: metres,
            activeCalories: kcal
        )
    }

    // MARK: - How long a segment has been recording

    @Test("An ended segment measures between its two dates")
    func anEndedSegmentIsBounded() {
        let walk = segment(.walking, from: 0, to: 600)
        #expect(walk.elapsed(at: base.addingTimeInterval(3_600)) == 600)
    }

    @Test("The segment in flight measures up to now, and never backwards")
    func theRunningSegmentGrows() {
        let run = segment(.running, from: 600, to: nil)
        #expect(run.elapsed(at: base.addingTimeInterval(900)) == 300)
        // A clock read before the segment opened — a device stamp slightly
        // ahead of ours — must not produce a negative duration on screen.
        #expect(run.elapsed(at: base) == 0)
    }

    // MARK: - Adding up one sport

    @Test("The totals of a sport are the sum of its segments, and only those")
    func totalsCoverOneSportOnly() {
        // The outing this feature exists for: walk, run, walk again.
        let segments = [
            segment(.walking, from: 0, to: 600, steps: 900, metres: 700, kcal: 30),
            segment(.running, from: 600, to: 1_200, steps: 1_100, metres: 1_400, kcal: 80),
            segment(.walking, from: 1_200, to: 1_800, steps: 800, metres: 650, kcal: 28)
        ]
        let now = base.addingTimeInterval(1_800)

        let walking = WatchActivityTotals.of(.walking, in: segments, at: now)
        #expect(walking.elapsed == 1_200)
        #expect(walking.steps == 1_700)
        #expect(walking.distanceMeters == 1_350)
        #expect(walking.activeCalories == 58)

        let running = WatchActivityTotals.of(.running, in: segments, at: now)
        #expect(running.elapsed == 600)
        #expect(running.steps == 1_100)

        // The two must partition the session, never overlap it: a segment
        // counted on both sides would make « marche + course » exceed the
        // session it happened inside.
        #expect(walking.steps + running.steps == 2_800)
    }

    @Test("The segment in flight counts towards its sport as it runs")
    func theRunningSegmentIsIncluded() {
        let segments = [
            segment(.walking, from: 0, to: 600, steps: 900),
            segment(.running, from: 600, to: nil, steps: 400)
        ]
        let running = WatchActivityTotals.of(.running, in: segments, at: base.addingTimeInterval(900))
        // Not zero until it ends — the block on screen would sit at 00:00 for
        // the whole first run of the outing, which is exactly when it is read.
        #expect(running.elapsed == 300)
        #expect(running.steps == 400)
    }

    @Test("A sport with no segment totals nothing rather than nothing at all")
    func anAbsentSportIsZero() {
        let segments = [segment(.walking, from: 0, to: nil, steps: 900)]
        #expect(WatchActivityTotals.of(.running, in: segments, at: base) == .zero)
    }

    // MARK: - Three sources, one list

    @Test("Merging keeps the freshest copy of a segment, not two of it")
    func mergingDeduplicates() {
        let id = UUID()
        let stale = segment(.running, from: 600, to: nil, steps: 100, id: id)
        let fresh = segment(.running, from: 600, to: 900, steps: 480, id: id)

        let merged = WatchWorkoutSegment.merged([[stale], [fresh]])

        // Same segment read twice — once mid-flight from the builder, once
        // final from the delegate. Appending both would double every figure it
        // carries.
        #expect(merged.count == 1)
        #expect(merged.first?.steps == 480)
        #expect(merged.first?.end == base.addingTimeInterval(900))
    }

    @Test("Merging keeps a segment only one source knows about")
    func mergingLosesNothing() {
        let walk = segment(.walking, from: 0, to: 600)
        let run = segment(.running, from: 600, to: nil)

        // The case this exists for: `workoutActivities` turning out not to
        // carry the segments a session began, so the only record of the ended
        // walk is what the delegate handed over.
        let merged = WatchWorkoutSegment.merged([[walk], [run]])
        #expect(merged.map(\.activity) == [.walking, .running])
    }

    @Test("Merged segments come back oldest first")
    func mergingSorts() {
        let merged = WatchWorkoutSegment.merged([
            [segment(.walking, from: 1_200, to: nil)],
            [segment(.walking, from: 0, to: 600), segment(.running, from: 600, to: 1_200)]
        ])
        #expect(merged.map(\.start) == [0, 600, 1_200].map(base.addingTimeInterval))
    }

    // MARK: - What it reads as

    @Test("The spoken summary names the sport before its numbers")
    func theSummaryNamesTheSport() {
        var metrics = WatchWorkoutMetrics.empty(for: .running)
        metrics.activityTotals = WatchActivityTotals(
            elapsed: 724,
            steps: 1_480,
            distanceMeters: 1_830,
            activeCalories: 136
        )
        // Without the leading word, VoiceOver reads six numbers belonging to
        // nothing in particular — and « quel sport la montre a compris ? » is
        // the question this block answers.
        #expect(metrics.activitySummaryText == "Course : 12:04, 1480 pas, 1,8 km, 136 kcal")
    }

    @Test("The two displayed lines name the sport and its three counters")
    func theDisplayedLinesReadRight() {
        var metrics = WatchWorkoutMetrics.empty(for: .running)
        metrics.activityTotals = WatchActivityTotals(
            elapsed: 724,
            steps: 1_480,
            distanceMeters: 1_830,
            activeCalories: 136
        )
        #expect(metrics.activityHeadlineText == "Course · 12:04")
        // One decimal, not two: this line refreshes with the session, and the
        // second decimal would flicker without adding anything readable at a
        // glance.
        #expect(metrics.activityTotals.countersText == "1480 pas  1,8 km  136 kcal")
    }
}
