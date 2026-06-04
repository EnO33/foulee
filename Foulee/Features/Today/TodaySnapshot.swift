import Foundation

/// Everything the Today screen renders in one value: today's metrics, the
/// goals they're measured against, the streak, the midday weather and the
/// current week's minutes. `TodayStore` builds it from HealthKit + WeatherKit.
struct TodaySnapshot: Equatable {
    var date: Date
    var steps: Int
    var stepsGoal: Int
    var minutes: Int
    var minutesGoal: Int
    var distanceKm: Double
    var calories: Int
    var streak: Int
    var bestStreak: Int
    var weather: WeatherSnapshot
    var weekMinutes: [Int]
    var weekGoal: Int
    var walkWindowStart: DateComponents
    var hasWalkedToday: Bool

    /// True when HealthKit returned nothing to show — fresh install, denied
    /// access, or simply no activity yet. Drives the empty-state card so the
    /// screen never reads as a wall of muted zeros.
    var hasNoActivity: Bool {
        steps == 0
            && minutes == 0
            && calories == 0
            && streak == 0
            && bestStreak == 0
            && weekMinutes.allSatisfy { $0 == 0 }
    }
}

struct WeatherSnapshot: Equatable {
    var temperatureCelsius: Int
    var condition: String
    var advice: String

    /// Whether real WeatherKit data is present (vs the "—" placeholder used
    /// when location isn't authorised). Drives the Apple Weather attribution.
    var isAvailable: Bool { condition != "—" }
}
