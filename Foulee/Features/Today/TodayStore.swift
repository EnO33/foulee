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
    private(set) var activeDays: Set<Weekday> = Weekday.workWeek
    /// Mirrored hydration prefs — only used to keep the Watch in sync (the
    /// home hydration card reads `UserPreferences` directly).
    private(set) var hydrationEnabled = false
    private(set) var hydrationGoalML = 2_000
    private(set) var hydrationGlassML = 250

    /// Last fetched history, kept so `apply(preferences:)` can re-derive the
    /// streaks immediately when the goal or active days change.
    @ObservationIgnored private var cachedHistory: [DailyMinutes] = []

    /// Long-lived subscription to HealthKit changes (live step updates).
    @ObservationIgnored private var observerTask: Task<Void, Never>?

    /// Optimistic overlay applied right after a walk so the home + widgets show
    /// it instantly. The iPhone takes up to a minute to flush a walk's steps and
    /// distance into HealthKit, and waiting for that is what made the dashboard
    /// feel stale. `target` is the total we expect once HealthKit catches up
    /// (pre-walk baseline + the walk's own measurement); we display
    /// `max(healthKit, target)`, so the overlay dissolves by itself the moment
    /// HealthKit reaches it — it can never double-count. Only steps + distance,
    /// which the walk measures directly; minutes/calories stay HealthKit-driven
    /// (faking exercise minutes could falsely complete a streak).
    private struct PendingWalk {
        var targetSteps: Int
        var targetDistanceKm: Double
    }
    @ObservationIgnored private var pendingWalk: PendingWalk?
    @ObservationIgnored private var walkBaselineSteps = 0
    @ObservationIgnored private var walkBaselineDistanceKm = 0.0

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
            || preferences.activeDays != activeDays
            || preferences.hydrationEnabled != hydrationEnabled
            || preferences.hydrationGoalML != hydrationGoalML
            || preferences.hydrationGlassML != hydrationGlassML
        stepsGoal = newStepsGoal
        minutesGoal = newMinutesGoal
        walkWindowStart = newWindow
        activeDays = preferences.activeDays
        hydrationEnabled = preferences.hydrationEnabled
        hydrationGoalML = preferences.hydrationGoalML
        hydrationGlassML = preferences.hydrationGlassML
        // Re-derive from the cached history: changing the goal or the active
        // days changes both the ring threshold and which missed days break the
        // streak, so recompute the streaks rather than copying the old ones.
        if changed, let snapshot {
            self.snapshot = TodaySnapshot(
                date: snapshot.date,
                steps: snapshot.steps,
                stepsGoal: stepsGoal,
                minutes: snapshot.minutes,
                minutesGoal: minutesGoal,
                distanceKm: snapshot.distanceKm,
                calories: snapshot.calories,
                streak: StreakCalculator.current(
                    history: cachedHistory,
                    goalMinutes: minutesGoal,
                    activeWeekdays: activeDays.calendarWeekdays,
                    today: .now
                ),
                bestStreak: StreakCalculator.best(
                    history: cachedHistory,
                    goalMinutes: minutesGoal,
                    activeWeekdays: activeDays.calendarWeekdays
                ),
                weather: snapshot.weather,
                weekMinutes: snapshot.weekMinutes,
                weekGoal: minutesGoal,
                walkWindowStart: walkWindowStart,
                hasWalkedToday: snapshot.minutes >= minutesGoal,
                isRestDay: isTodayRestDay
            )
            publishToWidgets()
        }
    }

    /// Mirror the current snapshot into the shared app group and refresh the
    /// widgets. Widgets can't read HealthKit while the phone is locked, so they
    /// read this snapshot instead — which keeps the Lock Screen from dropping to
    /// zero. Cheap; safe to call on every refresh / goal change.
    private func publishToWidgets() {
        guard let snapshot else { return }
        SharedStore.write(WidgetSnapshot(
            steps: snapshot.steps,
            stepsGoal: snapshot.stepsGoal,
            minutes: snapshot.minutes,
            minutesGoal: snapshot.minutesGoal,
            distanceKm: snapshot.distanceKm,
            calories: snapshot.calories,
            streak: snapshot.streak,
            // Water intake is owned by the hydration flow — carry the stored
            // value forward so this full rewrite doesn't reset the ring.
            waterML: SharedStore.read()?.waterML ?? 0,
            waterGoalML: hydrationGoalML,
            hydrationEnabled: hydrationEnabled
        ))
        WidgetCenter.shared.reloadAllTimelines()

        // Push the phone-computed streak (+ goals) to the Watch. The watch's
        // local HealthKit only keeps a few days of history, so it can't
        // recompute long streaks correctly — it just displays this value.
        PhoneWatchSync.shared.send(WatchSyncPayload(
            streak: snapshot.streak,
            minutesGoal: minutesGoal,
            stepsGoal: stepsGoal,
            hydrationEnabled: hydrationEnabled,
            hydrationGoalML: hydrationGoalML,
            hydrationGlassML: hydrationGlassML
        ))
    }

    /// Ask for HealthKit + Location authorization and trigger an initial
    /// refresh. Idempotent — safe to call from `.task` on every appear.
    /// Always refreshes regardless of whether authorization succeeded, so
    /// the UI never gets stuck on the placeholder.
    func bootstrap() async {
        _ = await runOrTrap { try await healthKit.requestAuthorization() }
        _ = await location.requestWhenInUse()
        await refresh()
        startObservingHealthChanges()
        // Hourly background wakes keep the widget snapshot fresh even when
        // the app stays closed all day.
        await healthKit.enableBackgroundDelivery()
    }

    /// Refresh the dashboard whenever HealthKit reports new data, so passive
    /// steps/distance/calories show up live without reopening the app.
    private func startObservingHealthChanges() {
        guard observerTask == nil else { return }
        let changes = healthKit.observeChanges()
        observerTask = Task { [weak self] in
            for await _ in changes {
                await self?.refresh()
            }
        }
    }

    /// Snapshot today's totals just before a walk begins, so when it finishes
    /// we can show the walk's contribution on top of the right baseline.
    func walkWillStart() {
        walkBaselineSteps = snapshot?.steps ?? 0
        walkBaselineDistanceKm = snapshot?.distanceKm ?? 0
    }

    /// A walk just finished: overlay its steps + distance immediately (see
    /// `PendingWalk`) and refresh so the home, widgets and Watch reflect it
    /// without waiting for the iPhone to flush the walk into HealthKit.
    func registerFinishedWalk(_ session: WalkSession) async {
        pendingWalk = PendingWalk(
            targetSteps: walkBaselineSteps + session.steps,
            targetDistanceKm: walkBaselineDistanceKm + session.distanceKm
        )
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
        // Drop the post-walk overlay once HealthKit's own step count reaches the
        // expected total — from there real data is complete, and keeping the
        // overlay could mask a later edit/deletion in the Health app.
        if let pending = pendingWalk, metrics.steps >= pending.targetSteps {
            pendingWalk = nil
        }
        let weatherSnapshot = await weatherTask
        let history = await historyTask ?? []
        cachedHistory = history
        snapshot = makeSnapshot(from: metrics, weather: weatherSnapshot, history: history)
        publishToWidgets()
    }

    private func fetchWeatherIfAuthorized() async -> WeatherSnapshot? {
        guard let coordinate = await location.currentLocation() else { return nil }
        // Weather is non-critical and self-evident — its card just hides when
        // unavailable. Don't route a transient WeatherKit failure (rate limits,
        // flaky network) through `lastError`: that raises the Health-data banner
        // which wrongly tells the user to check their Santé permissions.
        return try? await weather.middayForecast(coordinate)
    }

    private func makeSnapshot(
        from metrics: HealthMetrics,
        weather: WeatherSnapshot?,
        history: [DailyMinutes]
    ) -> TodaySnapshot {
        let currentStreak = StreakCalculator.current(
            history: history,
            goalMinutes: minutesGoal,
            activeWeekdays: activeDays.calendarWeekdays,
            today: .now
        )
        let bestStreak = StreakCalculator.best(
            history: history,
            goalMinutes: minutesGoal,
            activeWeekdays: activeDays.calendarWeekdays
        )
        // Apply the optimistic post-walk overlay: show the freshly-walked steps
        // and distance until HealthKit's own totals reach them (see PendingWalk).
        let displaySteps = max(metrics.steps, pendingWalk?.targetSteps ?? 0)
        let displayDistanceKm = max(metrics.distanceKm, pendingWalk?.targetDistanceKm ?? 0)
        return TodaySnapshot(
            date: .now,
            steps: displaySteps,
            stepsGoal: stepsGoal,
            minutes: metrics.activeMinutes,
            minutesGoal: minutesGoal,
            distanceKm: displayDistanceKm,
            calories: metrics.activeCalories,
            streak: currentStreak,
            bestStreak: bestStreak,
            weather: weather ?? snapshot?.weather ?? fallbackWeather,
            weekMinutes: currentWeekMinutes(history: history),
            weekGoal: minutesGoal,
            walkWindowStart: walkWindowStart,
            hasWalkedToday: metrics.activeMinutes >= minutesGoal,
            isRestDay: isTodayRestDay
        )
    }

    /// Today isn't one of the user's active weekdays — no walk is planned.
    private var isTodayRestDay: Bool {
        let weekday = Calendar.current.component(.weekday, from: .now)
        return !activeDays.calendarWeekdays.contains(weekday)
    }

    /// Minutes for Monday → Sunday of the **current** ISO week, aligned with
    /// the labels `L M M J V S D` in `TodayWeekBars`. Days that haven't
    /// happened yet (and days missing from the history) come out as 0.
    private func currentWeekMinutes(history: [DailyMinutes]) -> [Int] {
        let calendar = Calendar.iso8601Monday
        let byDay = Dictionary(uniqueKeysWithValues: history.map {
            (calendar.startOfDay(for: $0.date), $0.minutes)
        })
        let days = ISOWeek.days(containing: .now, calendar: calendar)
        guard days.count == 7 else { return Array(repeating: 0, count: 7) }
        return days.map { byDay[$0] ?? 0 }
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
