import Foundation

/// Custom `HKWorkout` metadata keys where Foulée stores a walk's *own* measured
/// totals. We don't write step / distance / energy **samples** (they'd
/// double-count the daily totals the Today screen sums back from HealthKit), so
/// these keys let the résumé and detail show the walk's real numbers without
/// touching any daily sum. Walks from other sources (Watch, Apple Workouts)
/// don't carry them, so readers fall back to the workout's statistics.
enum FouleeWorkoutMetadata {
    static let steps = "com.eno33.foulee.workout.steps"
    static let distanceMeters = "com.eno33.foulee.workout.distanceMeters"
    static let calories = "com.eno33.foulee.workout.calories"
}

/// Plain bag describing a walking `HKWorkout` for the summary sheet —
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
}
