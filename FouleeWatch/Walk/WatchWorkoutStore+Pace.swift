import Foundation

/// What the session's counters say about how fast the wearer is going
/// (issues #267, #300).
///
/// Two readers of one stream, and they want different things from it. The
/// **classifier** wants the sharpest possible window — three seconds is enough
/// to tell a walk from a run, and waiting longer would put running inside the
/// walk. The **pace** wants the longest window it can afford, because a figure
/// on screen is read as a measurement and the underlying distance is estimated
/// from wrist motion, not measured by GPS.
///
/// So they are fed the same samples and left to disagree about the window.
extension WatchWorkoutStore {
    /// Hand one batch of counters to both readers.
    func classifyMovement(steps: Int, distanceMeters: Double, at now: Date) {
        let sample = MovementSample(date: now, steps: steps, distanceMeters: distanceMeters)
        // Every sample, unconditionally: the estimator keeps its own window and
        // its own idea of what standing still looks like, and skipping the ones
        // the classifier cannot read would hide exactly the intervals where the
        // wearer stopped.
        paceEstimator.record(sample)

        guard let previous = lastMovementSample else {
            lastMovementSample = sample
            return
        }
        guard let observation = MovementClassifier.observation(from: previous, to: sample) else {
            // Not enough of a change to read. Keep the older sample so the
            // window keeps widening rather than restarting on every batch.
            return
        }
        lastMovementSample = sample
        detection.ingest(observation)
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
