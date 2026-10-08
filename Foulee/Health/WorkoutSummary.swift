import Foundation

/// Plain bag describing an `HKWorkout` for the summary sheet —
/// keeps `HKWorkout` (non-`Sendable`, framework-specific) out of view code.
struct WorkoutSummary: Equatable, Hashable, Sendable, Identifiable {
    var id: UUID
    var startedAt: Date
    var endedAt: Date
    var durationSeconds: TimeInterval
    var distanceKm: Double
    var activeCalories: Int
    /// Steps for the walk. From Foulée's own metadata for walks it recorded; 0
    /// for other sources (the detail then falls back to a window query).
    /// Defaulted so existing initialisers compile.
    var steps: Int = 0
    /// Elevation gain (metres) from `HKMetadataKeyElevationAscended` — 0 when
    /// the source didn't record it. Defaulted so existing initialisers compile.
    var elevationMeters: Double = 0
    /// "Foulée", "Forme", "Apple Watch", etc. — read from
    /// `HKWorkout.sourceRevision.source.name`.
    var sourceName: String
    /// What the session was recorded as (issue #245).
    ///
    /// Defaulted to `.other` and **not** to `.walking`, though a walk is by far
    /// the commoner case: a call site that forgets this field then shows the
    /// neutral « Séance » instead of asserting a walk that may have been a run.
    /// Issue #223 is what a silent `.walking` default costs — it stamped every
    /// session the app had ever written, permanently.
    var activity: RecordedActivity = .other
    /// Where this workout sits in a watch outing, when the watch said so
    /// (issue #316). Read by `OutingGrouping`, which ties legs back together.
    var outing: OutingLeg?
    /// The workouts this row stands for, oldest first, when it is an outing
    /// regrouped from several legs (issue #317). Empty for an ordinary row.
    ///
    /// Kept rather than folded away: the detail (#318) and the map (#319) show
    /// the outing leg by leg.
    var legs: [WorkoutSummary] = []
}

extension WorkoutSummary {
    /// Every activity the row covers, in the order they were first done.
    ///
    /// One for an ordinary row. For a regrouped outing, each sport once:
    /// walk → run → walk → run is « Marche et course », not a list of four.
    var activities: [RecordedActivity] {
        guard !legs.isEmpty else { return [activity] }
        var seen: [RecordedActivity] = []
        for leg in legs where !seen.contains(leg.activity) {
            seen.append(leg.activity)
        }
        return seen
    }

    /// How the row names what was done: « Course », or « Marche et course » for
    /// an outing that changed sport. French grammar, not a list format: the
    /// app speaks French only, and a locale-driven formatter would write
    /// « Marche and course » on an English device.
    var activityLabel: String {
        let labels = activities.enumerated().map { index, activity in
            index == 0 ? activity.label : activity.label.lowercased()
        }
        guard let last = labels.last, labels.count > 1 else { return labels.first ?? activity.label }
        return labels.dropLast().joined(separator: ", ") + " et " + last
    }

    /// The figure drawn next to the row: the sport's own, or the walk-and-run
    /// figure once an outing mixes them — what `ActivityGlyph.mixedCardio`
    /// stands for.
    var activityIcon: String {
        activities.count > 1 ? ActivityGlyph.mixedCardio : activity.icon
    }
}
