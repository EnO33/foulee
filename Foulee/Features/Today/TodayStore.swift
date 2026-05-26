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

    /// Defaults that don't (yet) come from HealthKit — overridable later
    /// by the onboarding goal (PR#6).
    var stepsGoal = 6_000
    var minutesGoal = 20

    /// Ask for authorization and trigger an initial refresh. Idempotent —
    /// safe to call from `.task` on every appear.
    func bootstrap() async {
        let granted = await runOrTrap { try await healthKit.requestAuthorization() }
        guard granted == true else { return }
        await refresh()
    }

    /// Re-fetches today's metrics. Surfaces failure via `lastError`.
    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        let metrics = await runOrTrap { try await healthKit.todayMetrics() }
        guard let metrics else { return }
        snapshot = makeSnapshot(from: metrics)
    }

    private func makeSnapshot(from metrics: HealthMetrics) -> TodaySnapshot {
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
            weather: WeatherSnapshot(temperatureCelsius: 21, condition: "—", advice: ""),
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
