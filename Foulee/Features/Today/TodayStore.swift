import Dependencies
import Foundation
import Observation

/// Owns the Today snapshot and refreshes it from HealthKit.
///
/// Single error boundary (`runOrTrap`) keeps the rest of the store
/// try-catch free — every call site reads as a happy-path narrative.
@MainActor
@Observable
final class TodayStore {
    private(set) var snapshot: TodaySnapshot?
    private(set) var isLoading = false
    private(set) var lastError: String?

    @ObservationIgnored
    @Dependency(\.healthKit) private var healthKit

    @ObservationIgnored
    @Dependency(\.location) private var location

    @ObservationIgnored
    @Dependency(\.weather) private var weather

    /// Defaults that don't (yet) come from HealthKit — overridable later
    /// by the onboarding goal (PR#6).
    var stepsGoal = 6_000
    var minutesGoal = 20

    private var fallbackWeather: WeatherSnapshot {
        WeatherSnapshot(temperatureCelsius: 0, condition: "—", advice: "")
    }

    /// Ask for HealthKit + Location authorization and trigger an initial
    /// refresh. Idempotent — safe to call from `.task` on every appear.
    func bootstrap() async {
        let healthGranted = await runOrTrap { try await healthKit.requestAuthorization() }
        guard healthGranted == true else { return }
        _ = await location.requestWhenInUse()
        await refresh()
    }

    /// Re-fetches today's metrics + midday weather + 30-day history in
    /// parallel. Weather and history failures are non-fatal: snapshot
    /// keeps the previous value (or fallback) and `lastError` records the
    /// message.
    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        async let metricsTask: HealthMetrics? = runOrTrap {
            try await healthKit.todayMetrics()
        }
        async let weatherTask: WeatherSnapshot? = fetchWeatherIfAuthorized()
        async let historyTask: [DailyMinutes]? = runOrTrap {
            try await healthKit.dailyMinutes(30)
        }

        let metrics = await metricsTask
        let weatherSnapshot = await weatherTask
        let history = await historyTask ?? []
        guard let metrics else { return }
        snapshot = makeSnapshot(from: metrics, weather: weatherSnapshot, history: history)
    }

    private func fetchWeatherIfAuthorized() async -> WeatherSnapshot? {
        guard let coordinate = await location.currentLocation() else { return nil }
        return await runOrTrap { try await weather.middayForecast(coordinate) }
    }

    private func makeSnapshot(
        from metrics: HealthMetrics,
        weather: WeatherSnapshot?,
        history: [DailyMinutes]
    ) -> TodaySnapshot {
        let currentStreak = StreakCalculator.current(
            history: history,
            goalMinutes: minutesGoal,
            today: .now
        )
        let bestStreak = StreakCalculator.best(
            history: history,
            goalMinutes: minutesGoal
        )
        return TodaySnapshot(
            date: .now,
            steps: metrics.steps,
            stepsGoal: stepsGoal,
            minutes: metrics.activeMinutes,
            minutesGoal: minutesGoal,
            distanceKm: metrics.distanceKm,
            calories: metrics.activeCalories,
            streak: currentStreak,
            bestStreak: bestStreak,
            weather: weather ?? snapshot?.weather ?? fallbackWeather,
            weekMinutes: lastSevenMinutes(history: history),
            weekGoal: minutesGoal,
            walkWindowStart: DateComponents(hour: 12, minute: 0),
            hasWalkedToday: metrics.activeMinutes >= minutesGoal
        )
    }

    private func lastSevenMinutes(history: [DailyMinutes]) -> [Int] {
        let tail = Array(history.suffix(7))
        let padding = Array(repeating: 0, count: max(0, 7 - tail.count))
        return padding + tail.map(\.minutes)
    }

    private func runOrTrap<T: Sendable>(_ body: () async throws -> T) async -> T? {
        do {
            return try await body()
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }
}
