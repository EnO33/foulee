import Foundation

/// Everything we surface for a single workout when the user taps a row
/// in the 7-day résumé. `WorkoutSummary` carries the row-level fields;
/// `heartRateSamples` and `stepsCount` are the extra signals we pull
/// from HealthKit on demand.
struct WorkoutDetail: Equatable, Sendable {
    var summary: WorkoutSummary
    var heartRateSamples: [HeartRateSample]
    var stepsCount: Int
    /// The outing's route, one segment per leg that has one (#319). Empty when
    /// nothing was recorded or Foulée may not read it — the detail then has no
    /// map. Defaulted so existing initialisers compile.
    var route: [RouteSegment] = []

    var averageHeartRate: Int? {
        guard !heartRateSamples.isEmpty else { return nil }
        let total = heartRateSamples.reduce(0) { $0 + $1.bpm }
        return total / heartRateSamples.count
    }

    var maxHeartRate: Int? {
        heartRateSamples.map(\.bpm).max()
    }

    /// The reading closest to `date`, for the finger on the curve (#319).
    /// Samples arrive sorted by date, so a binary search finds it.
    func heartRate(nearest date: Date) -> HeartRateSample? {
        let samples = heartRateSamples
        guard !samples.isEmpty else { return nil }
        var low = 0
        var high = samples.count - 1
        while low < high {
            let mid = (low + high) / 2
            if samples[mid].date < date { low = mid + 1 } else { high = mid }
        }
        guard low > 0 else { return samples[low] }
        let before = samples[low - 1]
        let after = samples[low]
        return date.timeIntervalSince(before.date) <= after.date.timeIntervalSince(date) ? before : after
    }

    var minHeartRate: Int? {
        heartRateSamples.map(\.bpm).min()
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
