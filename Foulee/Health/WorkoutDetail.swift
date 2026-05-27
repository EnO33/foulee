import Foundation

/// Everything we surface for a single workout when the user taps a row
/// in the 7-day résumé. `WorkoutSummary` carries the row-level fields;
/// `heartRateSamples` and `stepsCount` are the extra signals we pull
/// from HealthKit on demand.
struct WorkoutDetail: Equatable, Sendable {
    var summary: WorkoutSummary
    var heartRateSamples: [HeartRateSample]
    var stepsCount: Int

    var averageHeartRate: Int? {
        guard !heartRateSamples.isEmpty else { return nil }
        let total = heartRateSamples.reduce(0) { $0 + $1.bpm }
        return total / heartRateSamples.count
    }

    var maxHeartRate: Int? {
        heartRateSamples.map(\.bpm).max()
    }

    var minHeartRate: Int? {
        heartRateSamples.map(\.bpm).min()
    }

    /// Average pace in km/h. `nil` when distance or duration is zero.
    var paceKmH: Double? {
        guard summary.distanceKm > 0, summary.durationSeconds > 0 else { return nil }
        let hours = summary.durationSeconds / 3_600
        return summary.distanceKm / hours
    }

    /// Minutes per kilometer. `nil` when distance is zero.
    var paceMinPerKm: Double? {
        guard summary.distanceKm > 0 else { return nil }
        let minutes = summary.durationSeconds / 60
        return minutes / summary.distanceKm
    }
}

/// Single heart-rate reading during a workout.
struct HeartRateSample: Equatable, Sendable, Identifiable {
    var id: UUID
    var date: Date
    var bpm: Int
}
