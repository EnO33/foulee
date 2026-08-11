import Foundation
import Testing
@testable import FouleeWatch

/// Telling a walk from a run by how fast the wearer is moving (issue #267).
///
/// The reason this exists is a measurement, not a preference:
/// `CMMotionActivityManager` took **under thirty seconds** to change its mind
/// on a real wrist (#248), and its smoothing is its purpose — no setting of
/// ours makes it quicker. Cadence changes within one window, and it costs
/// nothing new: these are the counters already driving the screen.
@Suite("Movement classifier")
struct MovementClassifierTests {
    private let start = Date(timeIntervalSince1970: 1_754_000_000)

    private func sample(_ offset: TimeInterval, steps: Int, metres: Double) -> MovementSample {
        MovementSample(date: start.addingTimeInterval(offset), steps: steps, distanceMeters: metres)
    }

    // MARK: - The rule, in the units a reader thinks in

    @Test("A running cadence at a running speed reads as a run")
    func aClearRunIsRead() {
        // 2,8 steps/s at 2,8 m/s — an unambiguous jog.
        #expect(MovementClassifier.reading(cadence: 2.8, speed: 2.8) == .activity(.running))
    }

    @Test("A walking cadence reads as a walk")
    func aClearWalkIsRead() {
        #expect(MovementClassifier.reading(cadence: 1.8, speed: 1.4) == .activity(.walking))
    }

    @Test("Between the two thresholds, nothing is claimed")
    func theGreyBandSaysNothing() {
        // A fast walker and a slow jogger overlap here, and a single threshold
        // would make every reading in the overlap a verdict. CoreMotion
        // arbitrates instead — slower, but right more often.
        #expect(MovementClassifier.walkingCadence < MovementClassifier.runningCadence)
        #expect(MovementClassifier.reading(cadence: 2.25, speed: 2.0) == .noEvidence)
    }

    @Test("A running cadence going nowhere is not a run")
    func armSwingIsVetoedBySpeed() {
        // The watch measures a *wrist*. Arms swing while standing, gesturing,
        // or pushing a pram over rough ground — and a cadence read off that is
        // not a run.
        #expect(MovementClassifier.reading(cadence: 2.9, speed: 0.3) == .noEvidence)
        #expect(MovementClassifier.reading(cadence: 2.9, speed: 0.3) != .activity(.running))
    }

    // MARK: - Reading two counters apart

    @Test("A run is recognised from one window of the session's own counters")
    func aWindowOfCountersIsEnough() throws {
        // Six seconds: 18 steps (3/s), 18 m (3 m/s).
        let observation = try #require(
            MovementClassifier.observation(
                from: sample(0, steps: 100, metres: 80),
                to: sample(6, steps: 118, metres: 98)
            )
        )
        #expect(observation.reading == .activity(.running))
        // Six seconds, not thirty. That gap is the whole issue.
        #expect(observation.observed.timeIntervalSince(observation.began) == 6)
    }

    @Test("The boundary is dated from the start of the window, not its end")
    func theBoundaryErrsEarly() throws {
        let observation = try #require(
            MovementClassifier.observation(
                from: sample(300, steps: 100, metres: 80),
                to: sample(306, steps: 118, metres: 98)
            )
        )
        // The pace held across the window, so the window's *start* is when it
        // began. Erring early is the right side: a late boundary puts running
        // inside the walk, and issue #265 will make that permanent.
        #expect(observation.began == start.addingTimeInterval(300))
    }

    @Test("A window too short to divide by is refused, not guessed")
    func aShortWindowIsRefused() {
        // `nil` and `.noEvidence` are different answers: this one means « ask
        // me again later », so the caller keeps its older sample and lets the
        // window widen instead of restarting.
        #expect(MovementClassifier.observation(
            from: sample(0, steps: 100, metres: 80),
            to: sample(1, steps: 105, metres: 84)
        ) == nil)
    }

    @Test("A long window with almost no steps is refused too")
    func aStillWindowIsRefused() {
        // Standing at a crossing for a minute: the window is wide, and there is
        // nothing in it to measure a cadence from.
        #expect(MovementClassifier.observation(
            from: sample(0, steps: 100, metres: 80),
            to: sample(60, steps: 102, metres: 81)
        ) == nil)
    }

    @Test("A distance that goes backwards cannot produce a negative speed")
    func distanceNeverRunsBackwards() throws {
        // HealthKit statistics can be revised downwards between two reads.
        let observation = try #require(
            MovementClassifier.observation(
                from: sample(0, steps: 100, metres: 90),
                to: sample(6, steps: 118, metres: 80)
            )
        )
        // Speed clamps to zero, so a running cadence is vetoed rather than
        // believed at an impossible pace.
        #expect(observation.reading == .noEvidence)
    }

    // MARK: - Both sources speak the same words

    @Test("A fast observation and a slow one drive the same decision")
    func bothSourcesFeedOneDetector() throws {
        var detector = ActivitySwitchDetector(startedAs: .walking, at: start)

        // What the cadence classifier produces, six seconds in.
        let fast = try #require(
            MovementClassifier.observation(
                from: sample(0, steps: 100, metres: 80),
                to: sample(6, steps: 118, metres: 98)
            )
        )
        let switched = detector.observe(fast)

        #expect(switched?.activity == .running)
        // Dated from the start of the window — so the segment boundary lands
        // where the running began, not where it was noticed.
        #expect(switched?.date == start)
        #expect(detector.current == .running)
    }
}
