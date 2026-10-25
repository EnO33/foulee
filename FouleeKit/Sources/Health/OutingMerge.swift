import Foundation

/// Two outings or more the wearer said were one (issue #549): a sortie cut in
/// two by an app relaunched mid-walk, a session that failed, a stop pressed by
/// mistake.
///
/// **A link, not a rewrite of Santé.** HealthKit only lets an app delete the
/// samples it wrote itself, and the Garmin Connect or Strava copies of the
/// outing would stay anyway. The merge is kept on the iPhone and applied when
/// the workouts are read: the parts become the legs of one outing, the way the
/// watch's legs are (#317).
nonisolated public struct OutingMerge: Codable, Hashable, Sendable, Identifiable {
    /// Stamped as the outing identifier of every part (`OutingLeg`).
    public var id: UUID
    /// The Santé workouts the outing is made of, whichever row showed them.
    public var workoutIDs: Set<UUID>
    /// When the first part began: what a merge is forgotten by, once no read
    /// can reach it any more.
    public var startedAt: Date

    public init(id: UUID = UUID(), workoutIDs: Set<UUID>, startedAt: Date) {
        self.id = id
        self.workoutIDs = workoutIDs
        self.startedAt = startedAt
    }
}

/// The rules of `OutingMerge`. Pure and total, like `OutingGrouping`.
nonisolated public enum OutingMerges {
    /// How long a stop may last between two parts of one outing. Beyond an
    /// hour, two outings are two outings: a walk to work and the walk back.
    public static let maximumGap: TimeInterval = 60 * 60

    /// A merge older than this is forgotten: the Bilan reads twelve months
    /// back, and a merge nothing reads only weighs on the store.
    public static let retention: TimeInterval = 400 * 24 * 60 * 60

    /// Whether `first` and `second`, in either order, can be one outing.
    ///
    /// They must follow each other without overlapping — an overlap is a copy
    /// from another writer, which `WorkoutDeduplication` already folds — and
    /// with at most `maximumGap` between them. A Garmin outing Santé doesn't
    /// have yet (#479) is refused: its id changes the day Garmin Connect
    /// writes it, and the merge would silently come undone.
    public static func canMerge(_ first: WorkoutSummary, _ second: WorkoutSummary) -> Bool {
        let (earlier, later) = first.startedAt <= second.startedAt ? (first, second) : (second, first)
        guard !GarminPendingOutings.isPending(earlier), !GarminPendingOutings.isPending(later) else { return false }
        let gap = later.startedAt.timeIntervalSince(earlier.endedAt)
        return gap >= 0 && gap <= maximumGap
    }

    /// The outings `outing` can be merged with, among the rows of the same
    /// list: the one right before it and the one right after, when close
    /// enough. Never one further away — merging across another outing would
    /// swallow it.
    public static func neighbours(
        of outing: WorkoutSummary,
        among outings: [WorkoutSummary]
    ) -> (previous: WorkoutSummary?, next: WorkoutSummary?) {
        let others = outings.filter { $0.id != outing.id }
        let previous = others.filter { $0.startedAt < outing.startedAt }.max { $0.startedAt < $1.startedAt }
        let next = others.filter { $0.startedAt > outing.startedAt }.min { $0.startedAt < $1.startedAt }
        return (
            previous.flatMap { canMerge($0, outing) ? $0 : nil },
            next.flatMap { canMerge(outing, $0) ? $0 : nil }
        )
    }

    /// `merges` once `first` and `second` are one outing.
    ///
    /// A part that already belongs to a merge brings it whole: merging a third
    /// outing into two already merged leaves one merge of three, never two
    /// merges sharing a workout.
    public static func merging(
        _ first: WorkoutSummary,
        _ second: WorkoutSummary,
        in merges: [OutingMerge],
        id: UUID = UUID()
    ) -> [OutingMerge] {
        let parts = workoutIDs(of: first).union(workoutIDs(of: second))
        let absorbed = merges.filter { !$0.workoutIDs.isDisjoint(with: parts) }
        let merged = OutingMerge(
            id: id,
            workoutIDs: absorbed.reduce(parts) { $0.union($1.workoutIDs) },
            startedAt: ([first.startedAt, second.startedAt] + absorbed.map(\.startedAt)).min() ?? first.startedAt
        )
        return merges.filter { $0.workoutIDs.isDisjoint(with: parts) } + [merged]
    }

    /// `merges` without the one `outing` belongs to: its parts read back as
    /// the outings they were.
    public static func separating(_ outing: WorkoutSummary, in merges: [OutingMerge]) -> [OutingMerge] {
        let parts = workoutIDs(of: outing)
        return merges.filter { $0.workoutIDs.isDisjoint(with: parts) }
    }

    /// Whether `outing` is one the wearer merged — what « Séparer » is offered
    /// for. A watch outing regrouped from its legs is not: nothing can undo it.
    public static func isMerged(_ outing: WorkoutSummary, in merges: [OutingMerge]) -> Bool {
        let parts = workoutIDs(of: outing)
        return merges.contains { !$0.workoutIDs.isDisjoint(with: parts) }
    }

    /// `workouts`, each part of a merge stamped as a leg of it, in start order,
    /// so `OutingGrouping` joins them — even two parts of the same sport, which
    /// contiguity alone keeps apart.
    ///
    /// The stamp replaces a watch outing's own: every leg of it belongs to the
    /// merge too, and one identifier is what ties them all together. Nothing
    /// is lost, since the stamp only lives in what was read.
    public static func applying(_ merges: [OutingMerge], to workouts: [WorkoutSummary]) -> [WorkoutSummary] {
        var legs: [UUID: OutingLeg] = [:]
        for merge in merges {
            let parts = workouts
                .filter { merge.workoutIDs.contains($0.id) }
                .sorted { ($0.startedAt, $0.id.uuidString) < ($1.startedAt, $1.id.uuidString) }
            for (index, part) in parts.enumerated() {
                legs[part.id] = OutingLeg(outingID: merge.id, index: index)
            }
        }
        guard !legs.isEmpty else { return workouts }
        return workouts.map { workout in
            guard let leg = legs[workout.id] else { return workout }
            var stamped = workout
            stamped.outing = leg
            return stamped
        }
    }

    /// `merges` without those begun more than `retention` before `now`.
    public static func kept(_ merges: [OutingMerge], now: Date) -> [OutingMerge] {
        merges.filter { now.timeIntervalSince($0.startedAt) < retention }
    }

    /// The Santé workouts a row stands for: its legs, or itself.
    private static func workoutIDs(of outing: WorkoutSummary) -> Set<UUID> {
        outing.legs.isEmpty ? [outing.id] : Set(outing.legs.map(\.id))
    }
}
