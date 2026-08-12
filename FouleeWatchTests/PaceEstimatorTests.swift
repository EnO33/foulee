import Foundation
import Testing
@testable import FouleeWatch

/// The arithmetic behind « allure récente » (issue #300).
///
/// A pure value driven by an explicit clock, which is the only reason any of
/// this is checkable: smoothing cannot be verified by looking at a wrist for
/// ten seconds, and the wrong window or the wrong filter looks exactly like the
/// right one until the wearer changes pace.
@Suite("Pace estimator")
struct PaceEstimatorTests {
    private let base = Date(timeIntervalSince1970: 1_754_000_000)

    /// Walk `speed` m/s for `seconds`, one reading every 3 s — roughly what
    /// HealthKit delivers.
    private func run(
        _ estimator: inout PaceEstimator,
        at speed: Double,
        for seconds: TimeInterval,
        from start: TimeInterval = 0,
        distance: Double = 0
    ) -> (end: TimeInterval, distance: Double) {
        var elapsed = start
        var covered = distance
        while elapsed < start + seconds {
            elapsed += 3
            covered += speed * 3
            estimator.record(
                MovementSample(date: base.addingTimeInterval(elapsed), steps: 0, distanceMeters: covered)
            )
        }
        return (elapsed, covered)
    }

    private func minutesAndSeconds(_ pace: TimeInterval?) -> String {
        guard let pace else { return "—" }
        return String(format: "%d'%02d\"", Int(pace) / 60, Int(pace) % 60)
    }

    // MARK: - Nothing to say

    @Test("Before anything is recorded there is no pace")
    func nothingYet() {
        let estimator = PaceEstimator()
        #expect(estimator.pace(at: base) == nil)
    }

    @Test("A single reading is not a window")
    func oneSampleIsNotAWindow() {
        var estimator = PaceEstimator()
        estimator.record(MovementSample(date: base, steps: 0, distanceMeters: 0))
        #expect(estimator.pace(at: base) == nil)
    }

    // MARK: - Steady state

    /// 3 m/s is 5'33"/km. A constant speed must come out as itself — an EMA
    /// that drifts on constant input is a broken EMA.
    @Test("A steady speed reads as its own pace")
    func steadySpeedIsExact() {
        var estimator = PaceEstimator()
        let end = run(&estimator, at: 3, for: 60)
        let pace = estimator.pace(at: base.addingTimeInterval(end.end))

        #expect(minutesAndSeconds(pace) == "5'33\"")
    }

    @Test("A slow walk reads as a slow walk")
    func aWalkReadsAsAWalk() {
        var estimator = PaceEstimator()
        // 1,3 m/s — an ordinary stroll, 12'49"/km.
        let end = run(&estimator, at: 1.3, for: 120)
        #expect(minutesAndSeconds(estimator.pace(at: base.addingTimeInterval(end.end))) == "12'49\"")
    }

    // MARK: - The lag is real, and it is the point

    /// The filter is what makes the figure readable, and it is also what makes
    /// it late. Both halves are asserted here so neither can be tuned away by
    /// accident.
    @Test("A change of pace is followed, but not instantly")
    func aChangeIsFollowedWithLag() {
        var estimator = PaceEstimator()
        let steady = run(&estimator, at: 3, for: 120)
        let before = estimator.pace(at: base.addingTimeInterval(steady.end))

        // Half speed from here on.
        let slowed = run(&estimator, at: 1.5, for: 6, from: steady.end, distance: steady.distance)
        let justAfter = estimator.pace(at: base.addingTimeInterval(slowed.end))

        // It has started to move — but nowhere near the new pace yet.
        #expect((justAfter ?? 0) > (before ?? 0), "the pace must respond")
        #expect((justAfter ?? 0) < 1_000 / 1.5, "and must not jump straight to it")

        // Given long enough, it arrives.
        let settled = run(&estimator, at: 1.5, for: 120, from: slowed.end, distance: slowed.distance)
        #expect(minutesAndSeconds(estimator.pace(at: base.addingTimeInterval(settled.end))) == "11'06\"")
    }

    // MARK: - Standing still

    /// The rule that keeps « 47'12"/km » off the screen. Readings keep arriving
    /// while standing — the counters simply stop moving — so silence has to be
    /// measured in *movement*, not in samples.
    @Test("Standing still withholds the pace rather than inventing a slow one")
    func standingStillGoesQuiet() {
        var estimator = PaceEstimator()
        let end = run(&estimator, at: 3, for: 60)

        // Same distance, again and again: a red light.
        var still = end.end
        for _ in 0..<10 {
            still += 3
            estimator.record(
                MovementSample(
                    date: base.addingTimeInterval(still),
                    steps: 0,
                    distanceMeters: end.distance
                )
            )
        }
        #expect(estimator.pace(at: base.addingTimeInterval(still)) == nil)
    }

    /// And the filter must not have been fed zeros while standing: doing so
    /// takes twenty to thirty seconds to climb out of, which is the jump people
    /// complain about when they set off again.
    @Test("Setting off again is immediate, not a climb out of zero")
    func settingOffAgainIsImmediate() {
        var estimator = PaceEstimator()
        let end = run(&estimator, at: 3, for: 60)

        var still = end.end
        for _ in 0..<10 {
            still += 3
            estimator.record(
                MovementSample(date: base.addingTimeInterval(still), steps: 0, distanceMeters: end.distance)
            )
        }

        // Six seconds of walking after the light turns green.
        let again = run(&estimator, at: 1.5, for: 6, from: still, distance: end.distance)
        let pace = estimator.pace(at: base.addingTimeInterval(again.end))

        #expect(pace != nil, "a pace must come back at once")
        // Re-seeded rather than converged: after that much silence the stored
        // speed described a pace from before the pause.
        #expect(minutesAndSeconds(pace) == "11'06\"")
    }

    /// **The defect the first version shipped with, swept over its whole
    /// range.** A stop shorter than the re-seed threshold used to stay inside
    /// the window, so its standing seconds counted as running seconds: a 15 s
    /// red light doubled the displayed pace for about half a minute afterwards.
    ///
    /// The curve was worse than merely wrong — it was **not monotonic**. A 15 s
    /// stop was handled far worse than a 21 s one, which is the signature of an
    /// uncovered interval rather than of a trade-off. Hence a sweep: a single
    /// case would have left the cliff somewhere between two of them.
    @Test(
        "A stop of any length leaves the pace unharmed",
        arguments: [3.0, 6.0, 9.0, 12.0, 15.0, 18.0, 21.0, 24.0, 27.0]
    )
    func aStopOfAnyLengthIsSurvived(stop: TimeInterval) {
        var estimator = PaceEstimator()
        let before = run(&estimator, at: 3, for: 120)

        var still = before.end
        while still < before.end + stop {
            still += 3
            estimator.record(
                MovementSample(
                    date: base.addingTimeInterval(still),
                    steps: 0,
                    distanceMeters: before.distance
                )
            )
        }

        // Off again at the very same speed, reading the pace **as it happens**.
        //
        // Sampling the finished estimator at earlier dates would prove nothing:
        // `pace(at:)` returns the stored speed and only checks staleness, so the
        // transient right after the restart is invisible that way. The first
        // version of this test did exactly that, and a deliberate regression
        // walked straight through it.
        var elapsed = still
        var covered = before.distance
        var worst: TimeInterval = 0
        while elapsed < still + 30 {
            elapsed += 3
            covered += 9
            estimator.record(
                MovementSample(date: base.addingTimeInterval(elapsed), steps: 0, distanceMeters: covered)
            )
            if let pace = estimator.pace(at: base.addingTimeInterval(elapsed)) {
                worst = max(worst, pace)
            }
        }
        // 5'33"/km is 333 s. Anything past 360 is standing time leaking into
        // the divisor.
        #expect(worst < 360, "a \(Int(stop)) s stop must not inflate the pace")
    }

    // MARK: - Deliveries we do not control

    /// `ingest` fires for **any** collected type, heart rate included, so the
    /// interval between two readings is not ours to choose. The first version
    /// compared raw metres against a metre and assumed three-second deliveries:
    /// at two a second, that demanded more than 2 m/s, and every ordinary walk
    /// showed no pace at all — for the whole outing, silently.
    @Test("A slow walk reported twice a second still has a pace")
    func fastDeliveriesDoNotHideAWalk() {
        var estimator = PaceEstimator()
        var elapsed: TimeInterval = 0
        var covered = 0.0
        // 1,2 m/s — an ordinary walk — sampled every half second, so each
        // reading adds 0,6 m.
        while elapsed < 120 {
            elapsed += 0.5
            covered += 0.6
            estimator.record(
                MovementSample(date: base.addingTimeInterval(elapsed), steps: 0, distanceMeters: covered)
            )
        }
        #expect(minutesAndSeconds(estimator.pace(at: base.addingTimeInterval(elapsed))) == "13'53\"")
    }

    /// Two readings stamped alike, or a clock that stepped backwards. Neither
    /// is evidence about speed, and dividing by either is a crash or a
    /// nonsense.
    @Test("Readings that do not advance the clock are ignored")
    func aStillClockIsIgnored() {
        var estimator = PaceEstimator()
        let end = run(&estimator, at: 3, for: 60)
        let stated = estimator.pace(at: base.addingTimeInterval(end.end))

        estimator.record(
            MovementSample(
                date: base.addingTimeInterval(end.end),
                steps: 0,
                distanceMeters: end.distance + 50
            )
        )
        estimator.record(
            MovementSample(
                date: base.addingTimeInterval(end.end - 30),
                steps: 0,
                distanceMeters: end.distance + 100
            )
        )
        #expect(estimator.pace(at: base.addingTimeInterval(end.end)) == stated)
    }

    // MARK: - Refusing to state a figure

    @Test("A crawl slower than thirty minutes a kilometre is withheld")
    func aCrawlIsWithheld() {
        var estimator = PaceEstimator()
        // 0,5 m/s over a long window: 33'20"/km, past the floor.
        let end = run(&estimator, at: 0.5, for: 120)
        #expect(estimator.pace(at: base.addingTimeInterval(end.end)) == nil)
    }

    /// The staleness clock runs on the reader's time, not on the last sample:
    /// a session whose deliveries stop entirely must go quiet too.
    @Test("A pace goes stale when nothing arrives at all")
    func silenceGoesStale() {
        var estimator = PaceEstimator()
        let end = run(&estimator, at: 3, for: 60)

        #expect(estimator.pace(at: base.addingTimeInterval(end.end + 19)) != nil)
        #expect(estimator.pace(at: base.addingTimeInterval(end.end + 21)) == nil)
    }
}
