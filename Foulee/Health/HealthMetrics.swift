import Foundation

/// Plain Codable bundle of the HealthKit values that Today consumes.
///
/// Kept independent of HKQuantity so previews and tests can build these
/// without touching the real HealthKit framework.
struct HealthMetrics: Equatable, Sendable {
    var steps: Int
    var distanceKm: Double
    var activeMinutes: Int
    var activeCalories: Int

    static let zero = HealthMetrics(
        steps: 0,
        distanceKm: 0,
        activeMinutes: 0,
        activeCalories: 0
    )
}
