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

    /// Re-fetches today's metrics + midday weather in parallel.
    /// Weather failure is non-fatal: snapshot keeps the previous value
    /// (or fallback) and `lastError` records the message.
    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        async let metricsTask: HealthMetrics? = runOrTrap {
            try await healthKit.todayMetrics()
        }
        async let weatherTask: WeatherSnapshot? = fetchWeatherIfAuthorized()

        let metrics = await metricsTask
        let weatherSnapshot = await weatherTask
        guard let metrics else { return }
        snapshot = makeSnapshot(from: metrics, weather: weatherSnapshot)
    }

    private func fetchWeatherIfAuthorized() async -> WeatherSnapshot? {
        guard let coordinate = await location.currentLocation() else { return nil }
        return await runOrTrap { try await weather.middayForecast(coordinate) }
    }

    private func makeSnapshot(
        from metrics: HealthMetrics,
        weather: WeatherSnapshot?
    ) -> TodaySnapshot {
        TodaySnapshot(
            date: .now,
            steps: metrics.steps,
            stepsGoal: stepsGoal,
            minutes: metrics.activeMinutes,
            minutesGoal: minutesGoal,
            distanceKm: metrics.distanceKm,
            calories: metrics.activeCalories,
            streak: 0,
            bestStreak: 0,
            weather: weather ?? snapshot?.weather ?? fallbackWeather,
            weekMinutes: [0, 0, 0, 0, 0, 0, 0],
            weekGoal: minutesGoal,
            walkWindowStart: DateComponents(hour: 12, minute: 0),
            hasWalkedToday: metrics.activeMinutes >= minutesGoal
        )
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
