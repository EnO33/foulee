import Dependencies
import Foundation
import Observation
import WidgetKit

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

    /// Mirror of the user's preferences. TodayScreen calls
    /// `apply(preferences:)` on mount and on every change so the hero
    /// card, streak threshold and walk-window countdown stay in sync
    /// with what the user picked in Onboarding / Settings.
    private(set) var stepsGoal = 6_000
    private(set) var minutesGoal = 20
    private(set) var walkWindowStart = DateComponents(hour: 12, minute: 0)

    private var fallbackWeather: WeatherSnapshot {
        WeatherSnapshot(temperatureCelsius: 0, condition: "—", advice: "")
    }

    /// Copy goal + window from the user's preferences. Re-derives the
    /// snapshot from the cached HealthKit history if any of them changed
    /// so the ring, streak and countdown update immediately — no need to
    /// wait for the next refresh.
    func apply(preferences: UserPreferences) {
        let newStepsGoal = preferences.stepsGoal
        let newMinutesGoal = preferences.minutesGoal
        let newWindow = DateComponents(
            hour: preferences.walkWindowStart.hour,
            minute: preferences.walkWindowStart.minute
        )
        let changed = newStepsGoal != stepsGoal
            || newMinutesGoal != minutesGoal
            || newWindow != walkWindowStart
        stepsGoal = newStepsGoal
        minutesGoal = newMinutesGoal
        walkWindowStart = newWindow
        if changed, let snapshot {
            self.snapshot = TodaySnapshot(
                date: snapshot.date,
                steps: snapshot.steps,
                stepsGoal: stepsGoal,
                minutes: snapshot.minutes,
                minutesGoal: minutesGoal,
                distanceKm: snapshot.distanceKm,
                calories: snapshot.calories,
                streak: snapshot.streak,
                bestStreak: snapshot.bestStreak,
                weather: snapshot.weather,
                weekMinutes: snapshot.weekMinutes,
                weekGoal: minutesGoal,
                walkWindowStart: walkWindowStart,
                hasWalkedToday: snapshot.minutes >= minutesGoal
            )
        }
    }

    /// Ask for HealthKit + Location authorization and trigger an initial
    /// refresh. Idempotent — safe to call from `.task` on every appear.
    /// Always refreshes regardless of whether authorization succeeded, so
    /// the UI never gets stuck on the placeholder.
    func bootstrap() async {
        _ = await runOrTrap { try await healthKit.requestAuthorization() }
        _ = await location.requestWhenInUse()
        await refresh()
    }

    /// Re-fetches today's metrics + midday weather + 30-day history in
    /// parallel. Always sets `snapshot` — falling back to zeros for
    /// metrics and an empty history when a fetch fails — so the UI
    /// renders even when HealthKit/WeatherKit are unavailable (sim, free
    /// dev signing, denied perms). Failures are surfaced via `lastError`
    /// for an in-screen banner.
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

        let metrics = await metricsTask ?? .zero
        let weatherSnapshot = await weatherTask
        let history = await historyTask ?? []
        snapshot = makeSnapshot(from: metrics, weather: weatherSnapshot, history: history)

        // Force the streak widgets (iPhone Lock Screen + Home Screen +
        // Watch complication) to refresh their timelines now that we
        // have fresh history — otherwise they sit on the cached 0 for
        // up to an hour after a walk.
        WidgetCenter.shared.reloadAllTimelines()
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
            weekMinutes: currentWeekMinutes(history: history),
            weekGoal: minutesGoal,
            walkWindowStart: walkWindowStart,
            hasWalkedToday: metrics.activeMinutes >= minutesGoal
        )
    }

    /// Minutes for Monday → Sunday of the **current** ISO week, aligned with
    /// the labels `L M M J V S D` in `TodayWeekBars`. Days that haven't
    /// happened yet (and days missing from the history) come out as 0.
    private func currentWeekMinutes(history: [DailyMinutes]) -> [Int] {
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2 // Monday (defensive: matches ISO 8601)
        let today = calendar.startOfDay(for: .now)
        let weekday = calendar.component(.weekday, from: today)
        // ISO weekday: 1 = Sunday → offset 6 days back. 2 = Monday → 0. etc.
        let mondayOffset = -((weekday + 5) % 7)
        guard let monday = calendar.date(byAdding: .day, value: mondayOffset, to: today) else {
            return Array(repeating: 0, count: 7)
        }
        let byDay = Dictionary(uniqueKeysWithValues: history.map {
            (calendar.startOfDay(for: $0.date), $0.minutes)
        })
        return (0..<7).map { offset in
            let dayStart = calendar.date(byAdding: .day, value: offset, to: monday) ?? monday
            return byDay[dayStart] ?? 0
        }
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
