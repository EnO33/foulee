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
}

struct WeatherSnapshot: Equatable {
    var temperatureCelsius: Int
    var condition: String
    var advice: String
}
