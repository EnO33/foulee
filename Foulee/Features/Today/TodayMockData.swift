import Foundation

/// Static mock used while PR#4 wires HealthKit. The shape mirrors what the
/// real `TodaySnapshot` will provide so the view doesn't need to change.
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

extension TodaySnapshot {
    static let mockPending = TodaySnapshot(
        date: .now,
        steps: 1_342,
        stepsGoal: 6_000,
        minutes: 0,
        minutesGoal: 20,
        distanceKm: 0.6,
        calories: 48,
        streak: 11,
        bestStreak: 18,
        weather: WeatherSnapshot(
            temperatureCelsius: 21,
            condition: "Ensoleillé",
            advice: "idéal"
        ),
        weekMinutes: [22, 18, 0, 0, 0, 0, 0],
        weekGoal: 20,
        walkWindowStart: DateComponents(hour: 12, minute: 0),
        hasWalkedToday: false
    )

    static let mockCompleted = TodaySnapshot(
        date: .now,
        steps: 4_218,
        stepsGoal: 6_000,
        minutes: 24,
        minutesGoal: 20,
        distanceKm: 1.8,
        calories: 142,
        streak: 12,
        bestStreak: 18,
        weather: WeatherSnapshot(
            temperatureCelsius: 21,
            condition: "Ensoleillé",
            advice: "idéal"
        ),
        weekMinutes: [22, 18, 24, 0, 0, 0, 0],
        weekGoal: 20,
        walkWindowStart: DateComponents(hour: 12, minute: 0),
        hasWalkedToday: true
    )
}
