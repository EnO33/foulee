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

    /// Two legs, because the block only appears on a sortie that has changed
    /// sport (issue #299) — on one leg it would repeat the clock and the tiles.
    /// These two tests are about the *wording*, so they set up the state the
    /// wording is actually shown in.
    @Test("The spoken summary names the sport before its numbers")
    func theSummaryNamesTheSport() {
        var metrics = WatchWorkoutMetrics.empty(for: .running)
        metrics.legs = [
            segment(.walking, from: 0, to: 380, id: UUID()),
            segment(.running, from: 380, to: 1_104, id: UUID())
        ]
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
        metrics.legs = [
            segment(.walking, from: 0, to: 380, id: UUID()),
            segment(.running, from: 380, to: 1_104, id: UUID())
        ]
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

/// The summary of an outing that changed sport (issue #265).
///
/// A change ends one `HKWorkout` and opens another, so Santé shows a walk *and*
/// a run. The summary is where that is said before the wearer goes looking.
@Suite("Watch outing breakdown")
struct WatchOutingBreakdownTests {
    private let start = Date(timeIntervalSince1970: 1_754_000_000)

    private func leg(
        _ activity: SessionActivity,
        from: TimeInterval,
        to: TimeInterval,
        metres: Double
    ) -> WatchWorkoutSegment {
        WatchWorkoutSegment(
            id: UUID(),
            activity: activity,
            start: start.addingTimeInterval(from),
            end: start.addingTimeInterval(to),
            steps: 0,
            distanceMeters: metres,
            activeCalories: 0
        )
    }

    private func metrics(_ legs: [WatchWorkoutSegment]) -> WatchWorkoutMetrics {
        var metrics = WatchWorkoutMetrics.zero
        metrics.legs = legs
        return metrics
    }

    @Test("A single-sport outing gets no breakdown")
    func oneSportSaysNothingMore() {
        // The totals above already say it. « Marche 18:24 » under an 18:24
        // clock is a line repeating itself, on a screen with no room to spare.
        #expect(metrics([leg(.walking, from: 0, to: 1_800, metres: 2_000)]).perSport.isEmpty)
        #expect(metrics([]).perSport.isEmpty)
    }

    @Test("An outing that changed sport names both, with their own figures")
    func bothSportsAreNamed() {
        let outing = metrics([
            leg(.walking, from: 0, to: 600, metres: 700),
            leg(.running, from: 600, to: 1_500, metres: 2_400),
            leg(.walking, from: 1_500, to: 1_800, metres: 350)
        ])
        let sports = outing.perSport

        #expect(sports.map(\.activity) == [.walking, .running])
        // The two walking legs are one line, summed — not two rows for one
        // sport.
        #expect(sports.first?.totals.elapsed == 900)
        #expect(sports.first?.totals.distanceMeters == 1_050)
        #expect(sports.last?.totals.elapsed == 900)
        #expect(sports.last?.totals.distanceMeters == 2_400)
    }

    @Test("Each sport reads as one line, figure drawn beside the words")
    func eachSportReadsAsOneLine() {
        let outing = metrics([
            leg(.walking, from: 0, to: 724, metres: 1_220),
            leg(.running, from: 724, to: 1_104, metres: 610)
        ])
        // The glyph is *not* in this string. Interpolating a SwiftUI `Image`
        // only works inside a single text literal — concatenated with `+` it
        // becomes a `String` and renders as
        // « SwiftUI.Image(SwiftUI.ImageProviderBox<…>) », which is what the
        // first capture of this screen actually showed.
        #expect(outing.perSport.first?.text == "Marche · 12:04 · 1,2 km · 9'53\"/km")
        #expect(outing.perSport.last?.text == "Course · 06:20 · 0,6 km · 10'22\"/km")
    }

    /// The pace of a whole stretch is the honest one — the relative error of a
    /// wrist-estimated distance averages out over a sortie, and the duration is
    /// exact. But `paceText` still says nothing under 50 m, and a line has to
    /// end cleanly rather than trail an empty separator (issue #297).
    @Test("A stretch too short to divide ends after its distance")
    func aShortStretchCarriesNoPace() {
        let outing = metrics([
            leg(.walking, from: 0, to: 600, metres: 900),
            leg(.running, from: 600, to: 615, metres: 20)
        ])
        #expect(outing.perSport.last?.text == "Course · 00:15 · 0,0 km")
        #expect(outing.perSport.first?.text.contains("/km") == true)
    }

    @Test("The sports add up to the outing")
    func theBreakdownPartitionsTheOuting() {
        let legs = [
            leg(.walking, from: 0, to: 600, metres: 700),
            leg(.running, from: 600, to: 1_800, metres: 3_000)
        ]
        let outing = metrics(legs)
        let summed = outing.perSport.reduce(0) { $0 + $1.totals.elapsed }
        // A breakdown that did not add up would be worse than none: the reader
        // would have no way to know which figure to believe.
        #expect(summed == WatchActivityTotals.of(legs, at: start).elapsed)
        #expect(summed == 1_800)
    }
}

/// When the current sport's own totals earn their place on screen (issue #299).
///
/// The block used to appear as soon as HealthKit had measured anything, which
/// on a sortie that has not changed sport means it repeats the clock and the
/// tiles above it — the same figures twice. It also made the page overflow a
/// 40 mm once the capture seed stopped photographing a shorter version of it.
@Suite("Activity breakdown visibility")
struct WatchActivityBreakdownTests {
    private let base = Date(timeIntervalSince1970: 1_754_000_000)

    private func leg(
        _ activity: SessionActivity,
        from: TimeInterval,
        to: TimeInterval,
        metres: Double
    ) -> WatchWorkoutSegment {
        WatchWorkoutSegment(
            id: UUID(),
            activity: activity,
            start: base.addingTimeInterval(from),
            end: base.addingTimeInterval(to),
            steps: 100,
            distanceMeters: metres,
            activeCalories: 10
        )
    }

    private func metrics(_ legs: [WatchWorkoutSegment]) -> WatchWorkoutMetrics {
        var metrics = WatchWorkoutMetrics.zero
        metrics.legs = legs
        metrics.activity = legs.last?.activity ?? .walking
        metrics.activityTotals = WatchActivityTotals.of(metrics.activity, in: legs, at: .distantPast)
        return metrics
    }

    /// One leg: this sport's totals *are* the outing's, so the block would say
    /// « Course · 18:24 » under an 18:24 clock and repeat the four tiles.
    @Test("A sortie that has not changed sport shows the sport, and nothing more")
    func oneLegNamesTheSportOnly() {
        let outing = metrics([leg(.running, from: 0, to: 1_104, metres: 1_830)])

        #expect(outing.showsActivityBreakdown == false)
        #expect(outing.activityHeadlineText == "Course")
        #expect(outing.activitySummaryText == "Course")
    }

    /// Two legs: the running sport's share is genuinely not the outing's.
    @Test("Once the outing is split, the sport's own share appears")
    func twoLegsEarnTheBreakdown() {
        let outing = metrics([
            leg(.walking, from: 0, to: 724, metres: 1_000),
            leg(.running, from: 724, to: 1_104, metres: 830)
        ])

        #expect(outing.showsActivityBreakdown)
        #expect(outing.activityHeadlineText == "Course · 06:20")
        #expect(outing.activitySummaryText.hasPrefix("Course : 06:20"))
    }

    /// A leg with nothing measured in it yet says nothing either — the guard is
    /// on both halves, not just the count.
    @Test("Two legs with nothing measured still show only the sport")
    func nothingMeasuredShowsNothing() {
        var outing = metrics([
            leg(.walking, from: 0, to: 600, metres: 800),
            leg(.running, from: 600, to: 900, metres: 500)
        ])
        outing.activityTotals = .zero

        #expect(outing.showsActivityBreakdown == false)
        #expect(outing.activityHeadlineText == "Course")
    }
}
