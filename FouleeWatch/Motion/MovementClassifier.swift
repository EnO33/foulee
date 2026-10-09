import Foundation

/// Tells a walk from a run by how fast the wearer is moving (issues #267, #331).
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
///
/// ## Where the cadence comes from
///
/// From `CMPedometer` — Apple's own instantaneous cadence and pace
/// (`PedometerReading`). It used to be derived here by dividing two
/// `HKLiveWorkoutBuilder` sums read when they were *delivered*, and that was
/// wrong by construction (issue #331): HealthKit delivers steps in uneven
/// batches, so a three-second window could hold two seconds of strides and read
/// a run at 2,8 steps/s as a walk at 1,8 — on a stretch the wearer ran.
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
    /// Below this, the wearer is stopping or standing — not walking (#331).
    ///
    /// One step a second is a shuffle, well under any walk. Calling it a walk
    /// turned every red light on a run into a walking segment; « no evidence »
    /// leaves the session as it is.
    static let minimumWalkingCadence = 1.0
    /// A cadence that says « running » is not believed below this speed.
    ///
    /// The veto exists because the watch measures a *wrist*. Arms swing while
    /// standing, gesturing, or pushing a stroller over rough ground, and a
    /// cadence read from that is not a run.
    static let runningSpeedFloor = 1.6
    /// How far before a reading its boundary may be dated (#331).
    ///
    /// A reading's pace began when the previous one was taken — but when the
    /// stream went quiet for a while, that previous reading says nothing about
    /// when this pace started. Ten seconds covers any regular cadence of
    /// updates, and stops a boundary from claiming a minute it never saw.
    static let maximumLookback: TimeInterval = 10

    /// Read one pedometer update, or `nil` when it carries no rhythm at all.
    ///
    /// `nil` and `.noEvidence` are different answers on purpose. `nil` means
    /// « nothing was measured » and changes nothing. `.noEvidence` means « I
    /// looked and cannot tell », which is a real observation and expires a
    /// stale candidate.
    ///
    /// - Parameter previous: the date of the last reading, if any. The pace in
    ///   this reading was held since then, so its start dates the boundary —
    ///   early rather than late: a late boundary puts running inside the walk.
    static func observation(_ reading: PedometerReading, since previous: Date?) -> ActivityObservation? {
        guard let cadence = reading.cadence else { return nil }
        let earliest = reading.date.addingTimeInterval(-maximumLookback)
        let began = min(max(previous ?? reading.date, earliest), reading.date)
        return ActivityObservation(
            reading: self.reading(cadence: cadence, speed: reading.speed ?? 0),
            began: began,
            observed: reading.date
        )
    }

    /// The rule, separated from the plumbing so it can be stated in the units
    /// a reader thinks in.
    static func reading(cadence: Double, speed: Double) -> MotionActivityReading {
        if cadence >= runningCadence {
            return speed >= runningSpeedFloor ? .activity(.running) : .noEvidence
        }
        if cadence <= walkingCadence, cadence >= minimumWalkingCadence {
            return .activity(.walking)
        }
        return .noEvidence
    }
}
