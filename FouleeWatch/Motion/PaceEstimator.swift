import Foundation

/// The wearer's recent speed, smoothed enough to be worth reading (issue #300).
///
/// **A pure value, driven by an explicit clock.** Everything here is arithmetic
/// over samples the session already produces, so all of it is testable — which
/// matters more than usual, because none of it can be checked by looking at a
/// wrist for ten seconds.
///
/// ## Why not simply distance ÷ time
///
/// Because the distance is estimated from wrist motion, not measured by GPS.
/// The error is large — published work on accelerometer speed estimation gives
/// double-digit percentages, and at 5'00"/km a tenth of that is already ±30 s
/// per kilometre. A figure refreshed every three seconds from that estimate is
/// noise wearing the typography of certainty.
///
/// ## The chain
///
/// 1. **A hybrid window: at least 30 m, at most 30 s.** The distance half bounds
///    the relative error when moving fast (≈ 6 s of window at 3'30"/km, ≈ 13 s
///    at 7'00"/km). The time half is the stillness detector: 30 m that take more
///    than 30 s is under 1 m/s, and the honest conclusion there is not « slow »
///    but « not moving ».
/// 2. **The smoothing runs on speed, never on pace.** This is the part that is
///    true regardless of any source: pace is an *inverse*. Averaging paces is a
///    harmonic mean of speeds — biased towards the slow — and one near-zero
///    sample sends the whole window to infinity. Speed is bounded between 0 and
///    about 7 m/s. The inversion happens once, at the very end.
/// 3. **An exponential moving average**, τ = 10 s. No buffer to fall out of, so
///    no step when an old sample leaves the window.
///
/// Total lag, stated rather than hidden: about **15 s** at 5'00"/km — half the
/// window plus the filter. That is what « récente » in the name is admitting.
struct PaceEstimator: Equatable, Sendable {
    /// The shortest distance worth dividing.
    static let windowDistance: Double = 30
    /// And the longest we will wait for it.
    static let windowDuration: TimeInterval = 30
    /// The filter's time constant.
    static let smoothing: TimeInterval = 10
    /// Past this much silence, there is no pace to state — see `pace(at:)`.
    static let staleAfter: TimeInterval = 20
    /// Slower than this is a pause somebody forgot to end, not a pace.
    static let slowestPace: TimeInterval = 30 * 60
    /// The least a reading must add for the wearer to count as moving. Over a
    /// three-second delivery even a slow stroll covers three metres, so this
    /// separates standing from walking without being fooled by a bursty
    /// delivery: one empty interval leaves the movement clock a few seconds
    /// back, far inside `staleAfter`.
    static let stillnessDistance: Double = 1

    /// Cumulative readings, oldest first. Trimmed to the window plus the one
    /// sample just outside it, which is what lets a window *span* the boundary
    /// instead of starting again at it.
    private var samples: [MovementSample] = []
    private var speed: Double?
    private var smoothedAt: Date?
    /// When the wearer was last seen to move. The staleness clock, and not the
    /// same thing as the last sample: samples keep arriving while standing.
    private var movedAt: Date?

    /// Take one cumulative reading of the session's counters.
    mutating func record(_ sample: MovementSample) {
        let previous = samples.last
        samples.append(sample)
        trim(before: sample.date)

        // **Judged on the latest interval, not on the window.** A window still
        // spanning the walk before a red light keeps producing a perfectly
        // plausible diluted speed long after the wearer has stopped — which is
        // exactly the « figure that is right and has stopped being true » this
        // whole type exists to avoid. Readings keep arriving while standing;
        // only the counters stop.
        //
        // The filter is *frozen* rather than fed a zero: zeros take twenty to
        // thirty seconds to climb out of, and that climb is the jump people
        // complain about when they set off again.
        let advanced = sample.distanceMeters - (previous?.distanceMeters ?? sample.distanceMeters)
        guard advanced >= Self.stillnessDistance else { return }

        // Setting off after a real stop: the window behind us describes an
        // effort that is over. Keeping it would blend a stroll before the
        // light with a run after it.
        if let movedAt, sample.date.timeIntervalSince(movedAt) > Self.staleAfter {
            samples = [previous, sample].compactMap { $0 }
            speed = nil
            smoothedAt = nil
        }

        guard let start = windowStart(endingAt: sample) else { return }
        let elapsed = sample.date.timeIntervalSince(start.date)
        let covered = sample.distanceMeters - start.distanceMeters
        guard elapsed > 0, covered > 0 else { return }

        movedAt = sample.date
        let raw = covered / elapsed
        guard let previous = speed, let previousAt = smoothedAt else {
            speed = raw
            smoothedAt = sample.date
            return
        }
        let step = sample.date.timeIntervalSince(previousAt)
        // Re-seed rather than converge after a long gap: the stored value
        // describes a pace from before the pause and is no evidence about now.
        guard step < Self.staleAfter else {
            speed = raw
            smoothedAt = sample.date
            return
        }
        let alpha = 1 - exp(-step / Self.smoothing)
        speed = previous + alpha * (raw - previous)
        smoothedAt = sample.date
    }

    /// Seconds per kilometre, or `nil` when there is nothing honest to say.
    ///
    /// Three ways to get nothing, and each is a different truth: nobody has
    /// moved recently, nothing has been measured yet, or the figure would be so
    /// slow that it describes a pause. A dash reads as information; « 47'12" »
    /// reads as a bug and takes the credibility of the figures beside it with
    /// it.
    func pace(at now: Date) -> TimeInterval? {
        guard let movedAt, now.timeIntervalSince(movedAt) <= Self.staleAfter else { return nil }
        guard let speed, speed > 0 else { return nil }
        let secondsPerKm = 1_000 / speed
        guard secondsPerKm <= Self.slowestPace else { return nil }
        return secondsPerKm
    }

    /// Everything inside the window, plus the first sample outside it.
    private mutating func trim(before now: Date) {
        let cutoff = now.addingTimeInterval(-Self.windowDuration)
        guard let firstInside = samples.firstIndex(where: { $0.date >= cutoff }) else {
            samples = Array(samples.suffix(1))
            return
        }
        // One before, deliberately: dropping it would shrink the window to
        // whatever happens to be inside, and a short window is a noisy one.
        samples.removeFirst(max(0, firstInside - 1))
    }

    /// The most recent sample that still puts `windowDistance` behind us — the
    /// **shortest** window that satisfies the distance, so the figure is as
    /// fresh as the accuracy allows. Falls back to the oldest sample held,
    /// which is the full 30 s.
    private func windowStart(endingAt current: MovementSample) -> MovementSample? {
        for sample in samples.reversed() where sample.date < current.date {
            if current.distanceMeters - sample.distanceMeters >= Self.windowDistance {
                return sample
            }
        }
        return samples.first.flatMap { $0.date < current.date ? $0 : nil }
    }
}
