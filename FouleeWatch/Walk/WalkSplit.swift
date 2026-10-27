import FouleeKit
import Foundation

/// One kilometre of an outing, and what it cost (issue #301).
struct WalkSplit: Equatable, Sendable, Identifiable {
    /// 1 for the first kilometre, 2 for the second — the boundary that was
    /// crossed, not an index.
    var kilometre: Int
    /// This kilometre's own time. What « temps intermédiaire » means.
    var duration: TimeInterval
    /// The steps taken over this kilometre, interpolated at both ends like its
    /// time (issue #382).
    var steps = 0
    /// Every sport recorded while this kilometre was run — both, when it
    /// straddles a change (issue #382).
    var activities: Set<SessionActivity> = []

    var id: Int { kilometre }

    /// « 6'12"/km ». A kilometre's pace is its own time, said the way runners
    /// read it.
    var paceText: String? { duration.paceText(overKm: 1) }

    /// « 160 pas/min », or `nil` when no step was counted.
    var cadenceText: String? { FouleeKit.cadenceText(steps: steps, over: duration) }

    /// « Course », « Marche », or « Marche et course » for a kilometre that
    /// changed sport on the way.
    var activityText: String {
        switch activities.count {
        case 0: ""
        case 1: activities.first?.label ?? ""
        default: String(localized: "Marche et course")
        }
    }

    /// The sport's figure, or `nil` for a mixed kilometre.
    var activity: SessionActivity? { activities.count == 1 ? activities.first : nil }
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
    /// One reading of the outing's counters.
    private struct Reading: Equatable, Sendable {
        var distanceMeters: Double
        var elapsed: TimeInterval
        var steps: Int
    }

    /// The last reading, kept to interpolate across the boundary.
    private var previous: Reading?
    /// When the last recorded kilometre was reached — the base of the next
    /// one's duration.
    private var lastBoundaryElapsed: TimeInterval = 0
    /// The step count at that same instant (issue #382).
    private var lastBoundarySteps: Double = 0
    /// The sports seen since that boundary.
    private var activitiesSinceBoundary: Set<SessionActivity> = []

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
    ///
    /// `steps` and `activity` are what the outing has counted and what it is
    /// doing at this reading (issue #382): a kilometre's steps come from the
    /// same interpolation as its time, and its sport is every sport seen
    /// between its two boundaries.
    mutating func record(
        distanceMeters: Double,
        elapsed: TimeInterval,
        steps: Int = 0,
        activity: SessionActivity? = nil
    ) {
        defer { previous = Reading(distanceMeters: distanceMeters, elapsed: elapsed, steps: steps) }
        if let activity { activitiesSinceBoundary.insert(activity) }
        guard let previous else { return }
        let covered = distanceMeters - previous.distanceMeters
        let took = elapsed - previous.elapsed
        // A distance revised downwards, or a clock that did not move. Neither
        // is a kilometre.
        guard covered > 0, took > 0 else { return }

        // The count of recorded kilometres *is* the high-water mark: a distance
        // that dips and climbs again cannot re-cross a boundary already noted.
        let stepped = Double(steps - previous.steps)
        while distanceMeters >= Double(splits.count + 1) * 1_000 {
            let boundary = Double(splits.count + 1) * 1_000
            let fraction = (boundary - previous.distanceMeters) / covered
            let reached = previous.elapsed + fraction * took
            let stepsAtBoundary = Double(previous.steps) + fraction * stepped
            splits.append(
                WalkSplit(
                    kilometre: splits.count + 1,
                    duration: reached - lastBoundaryElapsed,
                    steps: max(Int((stepsAtBoundary - lastBoundarySteps).rounded()), 0),
                    activities: activitiesSinceBoundary
                )
            )
            lastBoundaryElapsed = reached
            lastBoundarySteps = stepsAtBoundary
            // The reading that crossed the line is already in the next one.
            activitiesSinceBoundary = activity.map { [$0] } ?? []
        }
    }
}
