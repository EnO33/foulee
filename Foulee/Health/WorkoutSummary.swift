import Foundation

/// Plain bag describing a walking `HKWorkout` for the summary sheet —
/// keeps `HKWorkout` (non-`Sendable`, framework-specific) out of view code.
struct WorkoutSummary: Equatable, Sendable, Identifiable {
    var id: UUID
    var startedAt: Date
    var endedAt: Date
    var durationSeconds: TimeInterval
    var distanceKm: Double
    var activeCalories: Int
    /// "Foulée", "Forme", "Apple Watch", etc. — read from
    /// `HKWorkout.sourceRevision.source.name`.
    var sourceName: String
}
