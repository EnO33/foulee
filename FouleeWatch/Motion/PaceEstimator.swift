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
    /// Below this speed the wearer is standing, not walking.
    ///
    /// **A speed, not a distance.** The first version of this compared the raw
    /// metres between two deliveries against a metre, on the assumption that
    /// deliveries arrive about every three seconds. Nothing guarantees that:
    /// `ingest` fires for *any* collected type, heart rate included, and this
    /// repository's own notes say HealthKit delivers « far more often than
    /// there is movement to measure ». At two deliveries a second, a metre
    /// demands more than 2 m/s — so every ordinary walk would have shown no
    /// pace at all, for the whole outing, silently.
    ///
    /// 0,3 m/s is about 1 km/h: slower than any walk, faster than the drift of
    /// a wrist held still.
    static let stillnessSpeed: Double = 0.3

    /// One reading, plus how much of the outing had been spent **moving** when
    /// it arrived.
    ///
    /// That second axis is what keeps a red light out of the divisor. Wall time
    /// counts the standing; moving time does not, so a window that happens to
    /// span a pause still divides a distance by the time it actually took.
    private struct Reading: Equatable {
        var date: Date
        var distanceMeters: Double
        var movingTime: TimeInterval
    }

    /// Cumulative readings, oldest first. Trimmed to the window plus the one
    /// sample just outside it, which is what lets a window *span* the boundary
    /// instead of starting again at it.
    private var samples: [Reading] = []
    /// Seconds spent moving since the estimator was made.
    private var movingTime: TimeInterval = 0
    private var speed: Double?
    private var smoothedAt: Date?
    /// When the wearer was last seen to move. The staleness clock, and not the
    /// same thing as the last sample: samples keep arriving while standing.
    private var movedAt: Date?

    /// Take one cumulative reading of the session's counters.
    mutating func record(_ sample: MovementSample) {
        guard let previous = samples.last else {
            samples = [Reading(date: sample.date, distanceMeters: sample.distanceMeters, movingTime: 0)]
            return
        }
        let step = sample.date.timeIntervalSince(previous.date)
        // Two readings stamped alike, or a clock that went backwards. Neither
        // is evidence about speed.
        guard step > 0 else { return }
        let covered = sample.distanceMeters - previous.distanceMeters

        // **Judged on the latest interval, not on the window.** A window still
        // spanning the walk before a red light keeps producing a perfectly
        // plausible diluted speed long after the wearer has stopped — which is
        // exactly the « figure that is right and has stopped being true » this
        // whole type exists to avoid. Readings keep arriving while standing;
        // only the counters stop.
        let moving = covered / step >= Self.stillnessSpeed
        if moving {
            movingTime += step
            movedAt = sample.date
        }
        samples.append(
            Reading(date: sample.date, distanceMeters: sample.distanceMeters, movingTime: movingTime)
        )
        trim(before: sample.date)

        // The filter is *frozen* while standing rather than fed a zero: zeros
        // take twenty to thirty seconds to climb out of, and that climb is the
        // jump people complain about when they set off again.
        guard moving else { return }

        // Setting off after a real stop: the window behind us describes an
        // effort that is over. Keeping it would blend a stroll before the light
        // with a run after it. The moving-time axis already keeps the standing
        // seconds out of the divisor — this is about the *effort*, not the
        // arithmetic.
        if let smoothedAt, sample.date.timeIntervalSince(smoothedAt) > Self.staleAfter {
            samples = Array(samples.suffix(2))
            speed = nil
            self.smoothedAt = nil
        }

        guard let start = windowStart(endingAt: samples[samples.count - 1]) else { return }
        // Moving time, never wall time: this is the whole point of the second
        // axis. A fifteen-second stop used to count as fifteen seconds of
        // running and doubled the pace on screen for half a minute afterwards.
        let elapsed = samples[samples.count - 1].movingTime - start.movingTime
        let distance = sample.distanceMeters - start.distanceMeters
        guard elapsed > 0, distance > 0 else { return }

        let raw = distance / elapsed
        guard let previousSpeed = speed, let previousAt = smoothedAt else {
            speed = raw
            smoothedAt = sample.date
            return
        }
        let alpha = 1 - exp(-sample.date.timeIntervalSince(previousAt) / Self.smoothing)
        speed = previousSpeed + alpha * (raw - previousSpeed)
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
    private func windowStart(endingAt current: Reading) -> Reading? {
        for sample in samples.reversed() where sample.date < current.date {
            if current.distanceMeters - sample.distanceMeters >= Self.windowDistance {
                return sample
            }
        }
        return samples.first.flatMap { $0.date < current.date ? $0 : nil }
    }
}
