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
    /// What counts as the distance having advanced at all.
    static let advanceDistance: Double = 1
    /// No advance for this long and the wearer has stopped.
    ///
    /// **Judged over a horizon, never per delivery.** Two earlier versions of
    /// this were wrong in the same way, and the second one shipped:
    ///
    /// - comparing raw metres between two deliveries to a metre assumed the
    ///   deliveries were about three seconds apart. Nothing guarantees that;
    ///   `ingest` fires for *any* collected type, heart rate included.
    /// - so did comparing their *speed* to a threshold — and worse, the time of
    ///   every delivery that fell short was dropped from the divisor while its
    ///   distance turned up in the next one. HealthKit delivers distance in
    ///   **bursts**: several readings carrying nothing, then one that catches
    ///   up. On a wrist that made a 11'09"/km walk read **4'30"/km**.
    ///
    /// A horizon does not care how the distance arrives, only whether it does.
    static let stillnessHorizon: TimeInterval = 10

    /// Cumulative readings, oldest first. Trimmed to the window plus the one
    /// sample just outside it, which is what lets a window *span* the boundary
    /// instead of starting again at it.
    private var samples: [MovementSample] = []
    /// The last reading at which the distance actually grew.
    private var lastAdvance: MovementSample?
    /// Whether the wearer was standing at the previous reading.
    private var wasStopped = false
    /// The newest reading date seen, to refuse anything that does not advance.
    private var lastReadingAt: Date?
    private var speed: Double?
    private var smoothedAt: Date?
    /// When the wearer was last seen to move. The staleness clock, and not the
    /// same thing as the last sample: samples keep arriving while standing.
    private var movedAt: Date?

    /// Take one cumulative reading of the session's counters.
    mutating func record(_ sample: MovementSample) {
        // A reading that does not advance the clock — a duplicate stamp, or a
        // clock that stepped back — is not evidence about speed.
        if let lastReadingAt, sample.date <= lastReadingAt { return }
        lastReadingAt = sample.date

        guard let known = lastAdvance else {
            lastAdvance = sample
            samples = [sample]
            return
        }
        // Advancing is a fact about the distance, not about this delivery: a
        // reading that carries nothing is not evidence of standing when the
        // next one may carry five metres at once.
        if sample.distanceMeters - known.distanceMeters >= Self.advanceDistance {
            lastAdvance = sample
            movedAt = sample.date
        }
        guard let advance = lastAdvance,
              sample.date.timeIntervalSince(advance.date) < Self.stillnessHorizon
        else {
            // Standing. The filter is **frozen**, never fed a zero: zeros take
            // twenty to thirty seconds to climb out of, and that climb is the
            // jump people complain about when they set off again.
            wasStopped = true
            return
        }

        // Off again after a real stop. Everything behind us describes an effort
        // that is over — its standing seconds would sit in the divisor, and its
        // speed says nothing about now.
        if wasStopped {
            wasStopped = false
            samples = []
            speed = nil
            smoothedAt = nil
        }

        samples.append(sample)
        trim(before: sample.date)

        guard let window = windowBounds(endingAt: sample) else { return }
        // **Wall time.** An earlier version divided by a « moving time » built
        // from per-delivery judgements, and bursty deliveries made it far too
        // small — a 11'09"/km walk read 4'30" on a wrist. Wall time cannot be
        // fooled by how the distance arrives; what it needs is a window that
        // does not span a stop, which is what the reset above guarantees.
        let elapsed = window.end.date.timeIntervalSince(window.start.date)
        let distance = window.end.distanceMeters - window.start.distanceMeters
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

    /// The two ends of the window, each anchored on the instant its distance
    /// was **first** seen.
    ///
    /// The distance only moves when HealthKit delivers, so several consecutive
    /// readings carry the same value and form a plateau. The instant a value
    /// was reached is the *earliest* reading carrying it — anchoring on the
    /// latest instead shortens the window at the start (pace too fast, 12 % on
    /// a five-second delivery) or lengthens it at the end (pace too slow, by
    /// the same amount). Anchoring both ends the same way cancels the bias
    /// rather than trading one for the other.
    ///
    /// The start is the most recent reading that still puts `windowDistance`
    /// behind us — the **shortest** window the accuracy allows — falling back
    /// to the oldest held, which is the full 30 s.
    private func windowBounds(
        endingAt current: MovementSample
    ) -> (start: MovementSample, end: MovementSample)? {
        let end = samples.first { $0.distanceMeters == current.distanceMeters } ?? current
        let candidate = samples.reversed().first {
            $0.date < end.date && end.distanceMeters - $0.distanceMeters >= Self.windowDistance
        } ?? samples.first.flatMap { $0.date < end.date ? $0 : nil }
        guard let candidate else { return nil }
        let start = samples.first { $0.distanceMeters == candidate.distanceMeters } ?? candidate
        return (start, end)
    }
}
