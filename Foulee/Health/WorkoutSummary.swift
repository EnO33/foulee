import Foundation

/// Plain bag describing a walking `HKWorkout` for the summary sheet —
/// keeps `HKWorkout` (non-`Sendable`, framework-specific) out of view code.
struct WorkoutSummary: Equatable, Hashable, Sendable, Identifiable {
    var id: UUID
    var startedAt: Date
    var endedAt: Date
    var durationSeconds: TimeInterval
    var distanceKm: Double
    var activeCalories: Int
    /// Elevation gain (metres) from `HKMetadataKeyElevationAscended` — 0 when
    /// the source didn't record it. Defaulted so existing initialisers compile.
    var elevationMeters: Double = 0
    /// "Foulée", "Forme", "Apple Watch", etc. — read from
    /// `HKWorkout.sourceRevision.source.name`.
    var sourceName: String
}
