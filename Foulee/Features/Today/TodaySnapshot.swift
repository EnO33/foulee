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
    /// True when today isn't one of the user's active days — no walk planned,
    /// so the hero shows a rest state instead of the window countdown.
    var isRestDay: Bool = false
}

struct WeatherSnapshot: Equatable {
    var temperatureCelsius: Int
    var condition: String
    var advice: String

    /// Whether real WeatherKit data is present (vs the "—" placeholder used
    /// when location isn't authorised). Drives the Apple Weather attribution.
    var isAvailable: Bool { condition != "—" }
}
