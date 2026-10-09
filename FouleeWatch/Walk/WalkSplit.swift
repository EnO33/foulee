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
    /// The next boundary still ahead. Also the high-water mark: a distance
    /// that dips and climbs again cannot re-cross a boundary already passed.
    private var nextKilometre = 1
    /// Kilometres this device did not time whole (issue #335). Their
    /// boundaries are still passed — the numbering is the outing's — but they
    /// are not recorded: a duration the wrist half-measured is not one.
    private var untimedThrough = 0

    init() {}

    /// Carry on an outing that already covered `distanceMeters` in `elapsed`
    /// on another device — the phone, before it handed over (issue #335).
    ///
    /// The kilometres before were the phone's, and one in progress is part
    /// phone, part wrist: neither is timed here. Timing starts with the first
    /// kilometre run whole on the wrist — the very next one when the handoff
    /// falls on a boundary, or covered nothing — numbered as the outing's.
    init(continuingFrom distanceMeters: Double, elapsed: TimeInterval) {
        let whole = Int(distanceMeters / 1_000)
        previous = (distanceMeters, elapsed)
        lastBoundaryElapsed = elapsed
        nextKilometre = whole + 1
        untimedThrough = Double(whole) * 1_000 == distanceMeters ? whole : nextKilometre
    }

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

        while distanceMeters >= Double(nextKilometre) * 1_000 {
            let boundary = Double(nextKilometre) * 1_000
            let reached = previous.elapsed + (boundary - previous.distanceMeters) * took / covered
            if nextKilometre > untimedThrough {
                splits.append(WalkSplit(kilometre: nextKilometre, duration: reached - lastBoundaryElapsed))
            }
            lastBoundaryElapsed = reached
            nextKilometre += 1
        }
    }
}
