import Foundation

/// Plain Codable bundle of the HealthKit values that Today consumes.
///
/// Kept independent of HKQuantity so previews and tests can build these
/// without touching the real HealthKit framework.
nonisolated public struct HealthMetrics: Equatable, Sendable {
    public var steps: Int
    public var distanceKm: Double
    public var activeMinutes: Int
    public var activeCalories: Int

    public static let zero = HealthMetrics(
        steps: 0,
        distanceKm: 0,
        activeMinutes: 0,
        activeCalories: 0
    )

    public init(
        steps: Int,
        distanceKm: Double,
        activeMinutes: Int,
        activeCalories: Int
    ) {
        self.steps = steps
        self.distanceKm = distanceKm
        self.activeMinutes = activeMinutes
        self.activeCalories = activeCalories
    }
}
