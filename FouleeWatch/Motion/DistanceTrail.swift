import Foundation

/// The outing's distance over the last few minutes, to answer « how fast was
/// that stretch, really? » (issue #390).
///
/// The pace on screen (`PaceEstimator`) is a smoothed *live* figure over thirty
/// seconds. The question here is about a stretch that is over: from where a run
/// was said to begin to the moment it is about to be recorded. Two distances
/// and two dates — the plainest measure there is, and the one a sensor cannot
/// argue with.
struct DistanceTrail: Equatable, Sendable {
    /// Longer than any stretch that is still waiting to be recorded.
    static let horizon: TimeInterval = 600
    /// Under this, two readings say more about how they were delivered than
    /// about the speed between them.
    static let shortestSpan: TimeInterval = 10

    private var samples: [MovementSample] = []

    mutating func record(_ sample: MovementSample) {
        if let last = samples.last, sample.date <= last.date { return }
        samples.append(sample)
        let cutoff = sample.date.addingTimeInterval(-Self.horizon)
        // One before the cutoff stays, so a stretch that began just past the
        // horizon can still be interpolated.
        if let firstInside = samples.firstIndex(where: { $0.date >= cutoff }), firstInside > 1 {
            samples.removeFirst(firstInside - 1)
        }
    }

    /// Metres per second between two instants, or `nil` when the trail cannot
    /// say: a span too short, or one that began before anything was recorded.
    func speed(from start: Date, to end: Date) -> Double? {
        let span = end.timeIntervalSince(start)
        guard span >= Self.shortestSpan,
              let from = distance(at: start),
              let to = distance(at: end)
        else { return nil }
        return max(0, to - from) / span
    }

    /// Interpolated between the two readings around `date`; the last one for a
    /// date past it, since nothing has been covered that we know of.
    private func distance(at date: Date) -> Double? {
        guard let first = samples.first, date >= first.date else { return nil }
        guard let afterIndex = samples.firstIndex(where: { $0.date >= date }) else {
            return samples.last?.distanceMeters
        }
        let after = samples[afterIndex]
        guard afterIndex > 0 else { return after.distanceMeters }
        let before = samples[afterIndex - 1]
        let fraction = date.timeIntervalSince(before.date) / after.date.timeIntervalSince(before.date)
        return before.distanceMeters + fraction * (after.distanceMeters - before.distanceMeters)
    }
}
