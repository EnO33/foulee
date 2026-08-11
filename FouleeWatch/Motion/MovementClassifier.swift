import Foundation

/// The session's own counters at one instant, as `HKLiveWorkoutBuilder` hands
/// them over — cumulative, not deltas.
struct MovementSample: Equatable, Sendable {
    var date: Date
    var steps: Int
    var distanceMeters: Double
}

/// Tells a walk from a run by how fast the wearer is moving (issue #267).
///
/// **This adds no sensor and no permission.** Steps and distance already flow
/// into `WatchWorkoutStore.ingest` every few seconds — they are what makes the
/// counters move on screen, so they are data we have already watched arrive on
/// a wrist. Two consecutive readings give a cadence and a speed, and between
/// walking and running both jump:
///
/// | | Walking | Running |
/// |---|---|---|
/// | Cadence | ~1,8 steps/s | ~2,8 steps/s |
/// | Speed | ~1,4 m/s | ~2,8 m/s |
///
/// It exists because `CMMotionActivityManager` cannot be made quick: its heavy
/// smoothing is its purpose, and issue #248 measured the result at under 30 s.
/// That is fine for « what is this person doing » and far too slow for « stop
/// crediting this stretch as a walk ».
enum MovementClassifier {
    /// Cadence at or above which this reads as running.
    ///
    /// A brisk walk tops out around 2,2 steps/s and a slow jog starts around
    /// 2,5 — the gap is narrow but real, and cadence is the sharper of the two
    /// signals. Speed varies far more: running uphill can fall under 2 m/s.
    static let runningCadence = 2.4
    /// Cadence at or below which this reads as walking.
    ///
    /// Deliberately *not* the same number. Between the two is a grey band where
    /// this classifier says nothing and lets CoreMotion arbitrate — a single
    /// threshold would make every reading a verdict, including the ones taken
    /// in the overlap between a fast walker and a slow jogger.
    static let walkingCadence = 2.1
    /// A cadence that says « running » is not believed below this speed.
    ///
    /// The veto exists because the watch measures a *wrist*. Arms swing while
    /// standing, gesturing, or pushing a stroller over rough ground, and a
    /// cadence read from that is not a run.
    static let runningSpeedFloor = 1.6

    /// The shortest window worth dividing by. Below it, one late sample turns
    /// into a wild cadence.
    static let minimumWindow: TimeInterval = 3
    /// And the fewest steps: a window can be long and nearly still.
    static let minimumSteps = 5

    /// Read the change between two samples, or `nil` when there is not enough
    /// of a change to read.
    ///
    /// `nil` and `.noEvidence` are different answers on purpose. `nil` means
    /// « ask me again later, I have not seen enough » — the caller keeps its
    /// previous sample and waits. `.noEvidence` means « I looked and cannot
    /// tell », which is a real observation and expires a stale candidate.
    static func observation(from previous: MovementSample, to current: MovementSample) -> ActivityObservation? {
        let window = current.date.timeIntervalSince(previous.date)
        let steps = current.steps - previous.steps
        guard window >= minimumWindow, steps >= minimumSteps else { return nil }

        let cadence = Double(steps) / window
        let speed = max(0, current.distanceMeters - previous.distanceMeters) / window

        return ActivityObservation(
            reading: reading(cadence: cadence, speed: speed),
            // The window is when this pace was held, so its *start* is when the
            // pace began — up to a few seconds early, which is the right side
            // to err on: a boundary that is late puts running inside the walk.
            began: previous.date,
            observed: current.date
        )
    }

    /// The rule, separated from the arithmetic so it can be stated in the units
    /// a reader thinks in.
    static func reading(cadence: Double, speed: Double) -> MotionActivityReading {
        if cadence >= runningCadence {
            return speed >= runningSpeedFloor ? .activity(.running) : .noEvidence
        }
        if cadence <= walkingCadence {
            return .activity(.walking)
        }
        return .noEvidence
    }
}
