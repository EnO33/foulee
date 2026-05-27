import Foundation

/// Live snapshot from `HKLiveWorkoutBuilder` — the view binds against
/// this. Heart rate is `nil` until the first sensor reading lands.
struct WatchWorkoutMetrics: Equatable, Sendable {
    var elapsed: TimeInterval
    var steps: Int
    var distanceMeters: Double
    var activeCalories: Int
    var heartRate: Int?

    static let zero = WatchWorkoutMetrics(
        elapsed: 0,
        steps: 0,
        distanceMeters: 0,
        activeCalories: 0,
        heartRate: nil
    )

    var distanceKm: Double { distanceMeters / 1_000 }
}
