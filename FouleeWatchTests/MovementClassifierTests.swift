import Foundation
import Testing
@testable import FouleeWatch

/// Telling a walk from a run by how fast the wearer is moving (issues #267,
/// #331).
///
/// The reason this exists is a measurement, not a preference:
/// `CMMotionActivityManager` took **under thirty seconds** to change its mind
/// on a real wrist (#248), and its smoothing is its purpose — no setting of
/// ours makes it quicker. The pedometer's own cadence changes within seconds,
/// and needs no permission beyond the one detection already asks for.
@Suite("Movement classifier")
struct MovementClassifierTests {
    private let start = Date(timeIntervalSince1970: 1_754_000_000)

    /// One pedometer update: `cadence` in steps/s, `speed` in m/s.
    private func reading(_ offset: TimeInterval, cadence: Double?, speed: Double? = nil) -> PedometerReading {
        PedometerReading(
            date: start.addingTimeInterval(offset),
            cadence: cadence,
            pace: speed.map { 1 / $0 }
        )
    }

    private func at(_ offset: TimeInterval) -> Date { start.addingTimeInterval(offset) }

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

    @Test("Standing still is not walking", arguments: [0.0, 0.4, 0.99])
    func standingIsNotWalking(cadence: Double) {
        // A red light on a run used to read as a walk, and became a walking
        // segment in Santé (issue #331). Below a step a second the wearer is
        // stopping, and saying so would be a guess.
        #expect(MovementClassifier.reading(cadence: cadence, speed: 0) == .noEvidence)
    }

    @Test("A slow walk is still a walk")
    func theWalkingFloorIsLow() {
        #expect(MovementClassifier.reading(cadence: MovementClassifier.minimumWalkingCadence, speed: 0.8)
            == .activity(.walking))
    }

    // MARK: - Reading the pedometer

    @Test("A run is recognised from one pedometer update")
    func oneUpdateIsEnough() throws {
        let observation = try #require(
            MovementClassifier.observation(reading(6, cadence: 2.8, speed: 3), since: at(3))
        )
        #expect(observation.reading == .activity(.running))
        #expect(observation.observed == at(6))
    }

    /// The bug of issue #331, as the classifier used to see it: two seconds of
    /// strides in a three-second HealthKit batch read a 2,8 steps/s run as 1,8.
    /// The pedometer reports the rhythm itself, whatever the batching.
    @Test("The pedometer's cadence is read as is, not rebuilt from counters")
    func theCadenceIsTheDevices() throws {
        let observation = try #require(
            MovementClassifier.observation(reading(3.3, cadence: 2.8, speed: 3), since: at(0))
        )
        #expect(observation.reading == .activity(.running))
    }

    @Test("The boundary is dated from the previous update, not this one")
    func theBoundaryErrsEarly() throws {
        let observation = try #require(
            MovementClassifier.observation(reading(306, cadence: 2.8, speed: 3), since: at(303))
        )
        // Erring early is the right side: a late boundary puts running inside
        // the walk, permanently.
        #expect(observation.began == at(303))
    }

    @Test("A boundary never reaches further back than the lookback")
    func aQuietStreamDoesNotStretchTheBoundary() throws {
        // A minute without an update says nothing about when this pace began.
        let observation = try #require(
            MovementClassifier.observation(reading(360, cadence: 2.8, speed: 3), since: at(300))
        )
        #expect(observation.began == at(360 - MovementClassifier.maximumLookback))
    }

    @Test("The first update dates itself")
    func theFirstUpdateHasNoWindow() throws {
        let observation = try #require(
            MovementClassifier.observation(reading(5, cadence: 1.8, speed: 1.4), since: nil)
        )
        #expect(observation.began == at(5))
        #expect(observation.reading == .activity(.walking))
    }

    @Test("An update without a cadence is not an observation")
    func noCadenceNoObservation() {
        // `nil`, not `.noEvidence`: nothing was measured, so nothing — not
        // even a stale candidate — should move.
        #expect(MovementClassifier.observation(reading(6, cadence: nil, speed: 3), since: at(3)) == nil)
    }

    @Test("A running cadence without a pace is not believed")
    func aMissingPaceVetoesARun() throws {
        let observation = try #require(
            MovementClassifier.observation(reading(6, cadence: 2.9, speed: nil), since: at(3))
        )
        #expect(observation.reading == .noEvidence)
    }

    @Test("A non-positive pace has no speed")
    func aZeroPaceIsNotInfinitelyFast() {
        #expect(PedometerReading(date: start, cadence: 2.8, pace: 0).speed == nil)
        #expect(PedometerReading(date: start, cadence: 2.8, pace: -1).speed == nil)
        #expect(PedometerReading(date: start, cadence: 2.8, pace: 0.5).speed == 2)
    }

    // MARK: - Both sources speak the same words

    @Test("A fast observation and a slow one drive the same decision")
    func bothSourcesFeedOneDetector() throws {
        var detector = ActivitySwitchDetector(startedAs: .walking, at: start)

        // What the pedometer says, six seconds in.
        let fast = try #require(
            MovementClassifier.observation(reading(6, cadence: 3, speed: 3), since: at(0))
        )
        let switched = detector.observe(fast)

        #expect(switched?.activity == .running)
        // Dated from the previous update — so the segment boundary lands where
        // the running began, not where it was noticed.
        #expect(switched?.date == start)
        #expect(switched?.confirmedAt == at(6))
        #expect(detector.current == .running)
    }
}
