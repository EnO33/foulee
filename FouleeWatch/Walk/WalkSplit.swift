import Foundation

/// One kilometre of an outing, and what it cost (issue #301).
struct WalkSplit: Equatable, Sendable, Identifiable {
    /// 1 for the first kilometre, 2 for the second — the boundary that was
    /// crossed, not an index.
    var kilometre: Int
    /// This kilometre's own time. What « temps intermédiaire » means.
    var duration: TimeInterval

    var id: Int { kilometre }
}

/// Notes each kilometre as the outing's distance grows past it (issue #301).
///
/// **It belongs to the outing, never to a leg.** `splitLeg` resets everything
/// the leg carries, and a kilometre routinely spans a change of sport — kept on
/// the leg, this would restart at « km 1 » every time the wearer broke into a
/// run, and no kilometre that straddled a boundary would ever be recorded.
///
/// A pure value, driven by the caller's clock: every rule below is arithmetic
/// over the two numbers `applyOutingTotals` already computes.
struct SplitRecorder: Equatable, Sendable {
    private(set) var splits: [WalkSplit] = []
    /// The last reading, kept to interpolate across the boundary.
    private var previous: (distanceMeters: Double, elapsed: TimeInterval)?
    /// When the last recorded kilometre was reached — the base of the next
    /// one's duration.
    private var lastBoundaryElapsed: TimeInterval = 0

    static func == (lhs: SplitRecorder, rhs: SplitRecorder) -> Bool {
        lhs.splits == rhs.splits && lhs.lastBoundaryElapsed == rhs.lastBoundaryElapsed
    }

    /// Take the outing's cumulative distance and elapsed time.
    ///
    /// Deliveries are far apart compared to a stride, so a boundary is almost
    /// never crossed exactly on a reading. **Interpolating is not polish**: a
    /// kilometre marked at the next delivery carries that delivery's lateness
    /// into its duration, and the error lands on two kilometres at once — one
    /// too long, the next too short.
    mutating func record(distanceMeters: Double, elapsed: TimeInterval) {
        defer { previous = (distanceMeters, elapsed) }
        guard let previous else { return }
        let covered = distanceMeters - previous.distanceMeters
        let took = elapsed - previous.elapsed
        // A distance revised downwards, or a clock that did not move. Neither
        // is a kilometre.
        guard covered > 0, took > 0 else { return }

        // The count of recorded kilometres *is* the high-water mark: a distance
        // that dips and climbs again cannot re-cross a boundary already noted.
        while distanceMeters >= Double(splits.count + 1) * 1_000 {
            let boundary = Double(splits.count + 1) * 1_000
            let reached = previous.elapsed + (boundary - previous.distanceMeters) * took / covered
            splits.append(
                WalkSplit(kilometre: splits.count + 1, duration: reached - lastBoundaryElapsed)
            )
            lastBoundaryElapsed = reached
        }
    }
}
