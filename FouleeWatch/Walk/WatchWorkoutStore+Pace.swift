import Foundation

/// What the session's distance says about how fast the wearer is going
/// (issues #267, #300, #331).
///
/// Only the **pace** reads it now. The walk / run classifier used to read the
/// same stream, and that was the bug of issue #331: HealthKit delivers steps in
/// uneven batches, and a three-second window cut across one read a run as a
/// walk. It listens to `CMPedometer` instead (`WatchActivityDetection`). The
/// pace keeps this stream because it wants the opposite of a sharp window —
/// the longest one it can afford — and averages the batching out.
extension WatchWorkoutStore {
    /// Hand one batch's distance to the pace estimator.
    func recordMovement(distanceMeters: Double, at now: Date) {
        // Every sample, unconditionally: the estimator keeps its own window and
        // its own idea of what standing still looks like.
        paceEstimator.record(MovementSample(date: now, distanceMeters: distanceMeters))
    }

    /// « 5'25"/km », or nothing (issue #300).
    ///
    /// Rounded to five seconds a kilometre for a run, ten for a walk. The step
    /// does not make the measurement better — it stops the screen claiming a
    /// resolution the sensor does not have. Published error figures for
    /// accelerometer speed estimation run to double digits in percent; at
    /// 5'00"/km even a tenth of that is half a minute per kilometre. A display
    /// flicking between 5'07", 5'12" and 5'04" would be showing noise in the
    /// typography of certainty.
    func recentPaceText(at now: Date) -> String? {
        guard let pace = paceEstimator.pace(at: now) else { return nil }
        let step: TimeInterval = currentActivity == .running ? 5 : 10
        return paceText(secondsPerKm: pace, roundedTo: step)
    }
}
