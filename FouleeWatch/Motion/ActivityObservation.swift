import Foundation

/// One thing observed about what the wearer is doing, whatever produced it
/// (issue #267).
///
/// Two sources feed the same decision, and they are good at opposite things:
///
/// | | Answers in | Good at |
/// |---|---|---|
/// | `CMMotionActivityManager` | ~30 s | being right |
/// | Cadence and speed, from the live builder's own counters | ~3 s | being quick |
///
/// The second is not a replacement. CoreMotion is built for coarse, low-power
/// context and its heavy smoothing *is* its purpose — measured at under 30 s in
/// issue #248, and no setting of ours changes that. Cadence jumps the instant
/// the wearer starts running, but its thresholds are personal and a wrist
/// swings for reasons other than running.
///
/// So both speak, in the same words, into `ActivitySwitchDetector`.
struct ActivityObservation: Equatable, Sendable {
    var reading: MotionActivityReading
    /// When the source says the activity began.
    ///
    /// Not when we were told. CoreMotion carries its own `startDate`; a
    /// cadence window began when the window did. This is what dates a segment
    /// boundary, and dating it from the moment of *noticing* would put the tail
    /// of a walk inside a run — permanently, once issue #265 lands.
    var began: Date
    /// When this process was handed the observation. Bounds the boundary above,
    /// and drives the staleness of a half-confirmed candidate.
    var observed: Date
}

extension MotionActivityEstimate {
    /// Read one CoreMotion estimate as an observation.
    func observation(minimumConfidence: MotionActivityConfidence) -> ActivityObservation {
        ActivityObservation(
            reading: reading(minimumConfidence: minimumConfidence),
            began: startDate,
            observed: receivedAt
        )
    }
}
