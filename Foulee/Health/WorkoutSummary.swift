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
}
