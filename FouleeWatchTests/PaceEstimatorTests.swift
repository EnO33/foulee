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
