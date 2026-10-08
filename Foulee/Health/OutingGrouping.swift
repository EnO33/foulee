import Foundation

/// Ties the legs of one outing back into one row of the 7-day résumé
/// (issue #317).
///
/// A change of sport on the watch ends one `HKWorkout` and opens another
/// (#265) — HealthKit refuses two sports in one session (#256) — so a walk →
/// run → walk outing is three records in Santé. `WorkoutDeduplication` cannot
/// rejoin them: it merges sessions that *overlap*, and legs only *touch* — one
/// ends at the very instant the next begins.
///
/// Runs **before** the deduplication, so an outing regrouped here meets a
/// Strava or Garmin copy of itself as one session against one, and the
/// overlap rule does the rest.
///
/// Pure and total: same input, same output, always.
enum OutingGrouping {
    /// How far apart two legs may be and still read as one outing, when the
    /// watch did not say so.
    ///
    /// The watch closes a leg and opens the next at **the same date** — the
    /// boundary it detected — so legs from before #316 touch exactly. One
    /// second absorbs any rounding on the way through HealthKit and nothing
    /// more: two separate outings are never that close.
    static let contiguityTolerance: TimeInterval = 1

    /// One row per outing, the others untouched.
    ///
    /// Two workouts are legs of the same outing when:
    /// - **the watch said so** — they carry the same outing identifier (#316).
    ///   The exact rule, and the only one for every outing recorded since;
    /// - **or, for older ones, they look it**: same source, a different sport,
    ///   and the second starts where the first ended. A change of sport is what
    ///   makes a leg, so two touching sessions of the *same* sport are two
    ///   sessions, not one outing.
    ///
    /// Two workouts carrying **different** identifiers are never joined, however
    /// close: the watch has already said they are two outings.
    static func groupingLegs(_ workouts: [WorkoutSummary]) -> [WorkoutSummary] {
        var outings: [[WorkoutSummary]] = []
        for workout in workouts.sorted(by: startsFirst) {
            if let index = outings.firstIndex(where: { continues($0, with: workout) }) {
                outings[index].append(workout)
            } else {
                outings.append([workout])
            }
        }
        return outings.compactMap(row(for:))
    }

    private static func continues(_ outing: [WorkoutSummary], with workout: WorkoutSummary) -> Bool {
        guard let last = outing.last else { return false }
        if let id = workout.outing?.outingID {
            if outing.contains(where: { $0.outing?.outingID == id }) { return true }
            if let lastID = last.outing?.outingID, lastID != id { return false }
        }
        return last.sourceName == workout.sourceName
            && last.activity != workout.activity
            && abs(workout.startedAt.timeIntervalSince(last.endedAt)) <= contiguityTolerance
    }

    /// The row an outing shows: the outing's whole span and the **sum** of its
    /// legs.
    ///
    /// Summed, unlike a deduplicated group (#218): duplicates describe the same
    /// effort twice, legs describe two halves of one. Duration is the sum of
    /// the legs' own durations, so a paused leg still counts its pause out.
    ///
    /// The row takes its id from the first leg — stable between two renders,
    /// which `NavigationLink(value:)` relies on — and its activity from the
    /// sport done longest, which is what an outing « was » when one word has to
    /// stand for it.
    private static func row(for legs: [WorkoutSummary]) -> WorkoutSummary? {
        guard var row = legs.first else { return nil }
        guard legs.count > 1, let last = legs.last else { return row }
        row.endedAt = last.endedAt
        row.durationSeconds = legs.map(\.durationSeconds).reduce(0, +)
        row.distanceKm = legs.map(\.distanceKm).reduce(0, +)
        row.activeCalories = legs.map(\.activeCalories).reduce(0, +)
        row.steps = legs.map(\.steps).reduce(0, +)
        row.elevationMeters = legs.map(\.elevationMeters).reduce(0, +)
        row.activity = dominantActivity(of: legs)
        row.legs = legs
        return row
    }

    /// The sport with the most time; on a tie, the one done first.
    private static func dominantActivity(of legs: [WorkoutSummary]) -> RecordedActivity {
        var time: [RecordedActivity: TimeInterval] = [:]
        for leg in legs { time[leg.activity, default: 0] += leg.durationSeconds }
        let order = legs.map(\.activity)
        return time.max { lhs, rhs in
            lhs.value != rhs.value
                ? lhs.value < rhs.value
                : (order.firstIndex(of: lhs.key) ?? 0) > (order.firstIndex(of: rhs.key) ?? 0)
        }?.key ?? .other
    }

    /// Start order, with the sample id as a tie-break so the sweep is
    /// reproducible.
    private static func startsFirst(_ lhs: WorkoutSummary, _ rhs: WorkoutSummary) -> Bool {
        (lhs.startedAt, lhs.id.uuidString) < (rhs.startedAt, rhs.id.uuidString)
    }
}
