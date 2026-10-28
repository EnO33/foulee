import FouleeKit
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
        distanceTrail.record(MovementSample(date: now, distanceMeters: distanceMeters))
    }

    /// Slower than this, a « run » is a walk — 6,5 km/h, 9'14"/km (issue #390).
    ///
    /// Below any run a wearer of this app would call one, and well above a
    /// brisk walk. The phantom that prompted it measured 2,6 km/h.
    static let runningSpeedFloor: Double = 1.8

    /// Whether the stretch since `start` was covered at a running speed. `true`
    /// when the trail cannot say: no distance is no evidence against a run, and
    /// the pedometer has already vouched for it.
    func isPlausibleRun(since start: Date, until now: Date) -> Bool {
        guard let speed = distanceTrail.speed(from: start, to: now) else { return true }
        return speed >= Self.runningSpeedFloor
    }

    /// Leave the leg whole and start detecting again from what it is recording
    /// — the screen goes back to the walk it never stopped being.
    func dropImplausibleRun(at now: Date) {
        FouleeLog.detection.notice("course écartée : allure de marche")
        currentActivity = legActivity
        beginActivityDetection(from: legActivity)
        refreshActivityTotals(at: now)
    }

    /// The live pace in seconds a kilometre, or nothing (issue #300).
    ///
    /// Rounded to five seconds a kilometre for a run, ten for a walk. The step
    /// does not make the measurement better — it stops the screen claiming a
    /// resolution the sensor does not have. Published error figures for
    /// accelerometer speed estimation run to double digits in percent; at
    /// 5'00"/km even a tenth of that is half a minute per kilometre. A display
    /// flicking between 5'07", 5'12" and 5'04" would be showing noise in the
    /// typography of certainty.
    func recentPace(at now: Date) -> TimeInterval? {
        paceEstimator.pace(at: now).map { Self.quantised(pace: $0, for: currentActivity) }
    }

    /// The live pace rounded to the step its sport can honestly claim.
    nonisolated static func quantised(pace secondsPerKm: TimeInterval, for activity: SessionActivity) -> TimeInterval {
        let step: TimeInterval = activity == .running ? 5 : 10
        return (secondsPerKm / step).rounded() * step
    }
}
