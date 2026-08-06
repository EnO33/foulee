import Dependencies
import Foundation
import Observation
import UserNotifications
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

    /// Error captured by `runOrTrap` during the current pass. Published into
    /// `lastError` only at the end of `refresh()` so a transient failure
    /// doesn't pin the banner forever, and a pass in progress doesn't make
    /// it flicker off/on.
    @ObservationIgnored private var passError: String?

    /// Guards against an older in-flight `refresh()` overwriting a newer one's
    /// snapshot or error verdict — overlaps happen (observer-triggered +
    /// foreground). Same pattern as `WatchTodayStore.loadGeneration`.
    @ObservationIgnored private var refreshGeneration = 0

    /// System-level notification permission, so the hero bell can surface
    /// "refusées dans Réglages" instead of a lying "activés".
    private(set) var notificationsAuthorizationStatus: UNAuthorizationStatus = .notDetermined

    /// Garmin-only setup whose day looks behind — see `GarminFreshness`. The
    /// screen then shows "Ouvre Garmin Connect" instead of Apple-Watch-flavoured
    /// copy, which would be useless advice for this user.
    private(set) var showsGarminSyncHint = false

    @ObservationIgnored
    @Dependency(\.healthKit) private var healthKit

    @ObservationIgnored
    @Dependency(\.notifications) private var notifications

    @ObservationIgnored
    @Dependency(\.location) private var location

    @ObservationIgnored
    @Dependency(\.weather) private var weather

    @ObservationIgnored
    @Dependency(\.date) private var date

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

    /// Whether the streak currently on screen was measured at all: the history
    /// was read, or an earlier read left a cache to carry forward. False on a
    /// cold launch whose first read is refused — the 0 the calculator answers
    /// there is nobody's measurement, so it must not be published outside the
    /// app (issue #200). A successful *empty* read is knowledge: it publishes
    /// an honest 0.
    @ObservationIgnored private(set) var isHistoryKnown = false

    /// Whether today's counters on screen were measured at all. False when the
    /// metrics read was refused: the `.zero` fallback below is nobody's
    /// measurement either, so it must not overwrite the counters the widgets
    /// and the background wakes maintain (issue #201). No cache to fall back
    /// on here — unlike the history, the carry-forward source is the stored
    /// snapshot itself.
    @ObservationIgnored private(set) var isMetricsKnown = false

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
        /// startOfDay when the walk was registered — the overlay is only
        /// meaningful for that day's totals.
        var day: Date
        var registeredAt: Date
    }
    @ObservationIgnored private var pendingWalk: PendingWalk?

    /// The totals the post-walk overlay is currently holding up, or nil when no
    /// walk is pending. Read by `widgetPublication(stored:)`: the overlay lifts
    /// the published counters above raw HealthKit exactly like the Connect IQ
    /// one, so the widget process has to be told about it or it would drop the
    /// walk on its very next render (#214). The overlay itself stays private —
    /// only the two numbers the widget may not fall below travel.
    var pendingWalkFloor: (steps: Int, distanceKm: Double)? {
        pendingWalk.map { (steps: $0.targetSteps, distanceKm: $0.targetDistanceKm) }
    }

    @ObservationIgnored private var walkBaselineSteps = 0
    @ObservationIgnored private var walkBaselineDistanceKm = 0.0

    /// Last raw HealthKit totals (no overlay applied), so `walkWillStart`
    /// baselines on real data — a snapshot-based baseline would compound the
    /// previous walk's overlay into the next walk's target.
    @ObservationIgnored private var lastRawMetrics: HealthMetrics = .zero

    /// The day `lastRawMetrics` was measured on. Kept because that baseline
    /// survives failed reads (issue #203): without a stamp, an evening total
    /// would baseline a walk taken after midnight and the overlay would show
    /// yesterday's steps plus the walk as today's — for as long as the reads
    /// keep failing, and beyond, since a caught-up read can't retire a target
    /// that high.
    @ObservationIgnored private var lastRawMetricsDay: Date?

    /// The overlay is a short-lived patch while HealthKit reconciles a walk,
    /// not a durable state — past this, trust HealthKit even if it never
    /// reaches the target.
    private static let pendingWalkLifetime: TimeInterval = 60 * 60

    private var fallbackWeather: WeatherSnapshot {
        WeatherSnapshot(temperatureCelsius: 0, condition: "—", advice: "")
    }

    /// Copy goal + window from the user's preferences. Re-derives the
    /// snapshot from the cached HealthKit history if any of them changed
    /// so the ring, streak and countdown update immediately — no need to
    /// wait for the next refresh.
    ///
    /// `preferences.activityMode` is absent below on purpose (issue #220):
    /// this method is the one place where a preference becomes a streak, so
    /// mirroring the walk/run choice here — even just into `changed` — is
    /// exactly how an existing user's series would start moving when they
    /// pick "Course". The streak stays activity-agnostic; the mode only
    /// steers what the app proposes.
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
                    activeDays: activeDays,
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
        guard let publication = widgetPublication(stored: SharedStore.read()) else { return }
        SharedStore.write(publication.snapshot)
        WidgetCenter.shared.reloadAllTimelines()

        // Push the phone-computed streak (+ goals) to the Watch. The watch's
        // local HealthKit only keeps a few days of history, so it can't
        // recompute long streaks correctly — it just displays this value.
        guard let payload = publication.watchPayload else { return }
        PhoneWatchSync.shared.send(payload)
    }

    /// Ask for HealthKit + Location authorization and trigger an initial
    /// refresh. Idempotent — safe to call from `.task` on every appear.
    /// Always refreshes regardless of whether authorization succeeded, so
    /// the UI never gets stuck on the placeholder.
    func bootstrap() async {
        // Auth errors are seeded into the refresh below rather than written
        // to the shared slot: refresh() starts each pass from a clean slate,
        // which would otherwise wipe them before publication.
        var authError: String?
        do {
            _ = try await healthKit.requestAuthorization()
        } catch {
            authError = error.localizedDescription
        }
        _ = await location.requestWhenInUse()
        await refresh(seedError: authError)
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
    ///
    /// A baseline measured on another day is worth no more than an unmeasured
    /// one: today starts at 0, and the overlay covers the walk alone.
    func walkWillStart() {
        guard lastRawMetricsDay == Calendar.current.startOfDay(for: date.now) else {
            walkBaselineSteps = 0
            walkBaselineDistanceKm = 0
            return
        }
        walkBaselineSteps = lastRawMetrics.steps
        walkBaselineDistanceKm = lastRawMetrics.distanceKm
    }

    /// A walk just finished: overlay its steps + distance immediately (see
    /// `PendingWalk`) and refresh so the home, widgets and Watch reflect it
    /// without waiting for the iPhone to flush the walk into HealthKit.
    func registerFinishedWalk(_ session: WalkSession) async {
        let now = date.now
        pendingWalk = PendingWalk(
            targetSteps: walkBaselineSteps + session.steps,
            targetDistanceKm: walkBaselineDistanceKm + session.distanceKm,
            day: Calendar.current.startOfDay(for: now),
            registeredAt: now
        )
        await refresh()
    }

    /// Re-fetches today's metrics + midday weather + the full streak history
    /// (`StreakCalculator.historyWindowDays` — same window as the calendar
    /// sheet, so the record here can't diverge from the one shown there) in
    /// parallel. Always sets `snapshot` — falling back to zeros for
    /// metrics and to the last known history when a fetch fails — so the
    /// UI renders even when HealthKit/WeatherKit are unavailable (sim, free
    /// dev signing, denied perms). Failures are surfaced via `lastError`
    /// for an in-screen banner.
    func refresh(seedError: String? = nil) async {
        refreshGeneration += 1
        let generation = refreshGeneration
        // Clean slate for this pass (a superseded pass may have left its
        // verdict behind); bootstrap seeds its auth error here.
        passError = seedError
        isLoading = true
        defer { isLoading = false }

        // Runs on bootstrap and on every return to foreground, so a trip
        // to iOS Settings is reflected as soon as the user comes back.
        notificationsAuthorizationStatus = await notifications.authorizationStatus()

        async let metricsTask: HealthMetrics? = runOrTrap(generation: generation) {
            try await healthKit.todayMetrics()
        }
        async let weatherTask: WeatherSnapshot? = fetchWeatherIfAuthorized()
        async let historyTask: [DailyMinutes]? = runOrTrap(generation: generation) {
            try await healthKit.dailyMinutes(StreakCalculator.historyWindowDays)
        }
        // Non-throwing by design: a missing verdict only means "no adapted
        // hint", never a data error worth showing the user.
        async let garminTask = healthKit.garminStatus()

        let fetchedMetrics = await metricsTask
        let metrics = metricsWithGarminOverlay(fetchedMetrics)
        // Metrics return first (local HealthKit); commit the walk baseline
        // and overlay verdict promptly — weather can take seconds, and
        // walkWillStart() must not read a stale baseline in the meantime.
        if generation == refreshGeneration {
            // Same rule for the metrics leg as for the history (issue #201): a
            // refused read means "no new counters", not "zero steps". The
            // `.zero` above still renders the screen — with the banner to
            // explain it — but only a leg that answered may rewrite the
            // counters the widgets read.
            isMetricsKnown = fetchedMetrics != nil
            // …and only such a leg may move the walk baseline (issue #203):
            // baselining the next walk on an unmeasured 0 would make the
            // post-walk overlay target far too low, so it would dissolve at
            // once instead of covering the HealthKit lag it exists for. Stamped
            // with the day it was measured on, so it can't outlive it.
            if let fetchedMetrics {
                lastRawMetrics = fetchedMetrics
                lastRawMetricsDay = Calendar.current.startOfDay(for: date.now)
            }
            dropPendingWalkIfStale(metrics: fetchedMetrics)
        }
        let weatherSnapshot = await weatherTask
        let fetchedHistory = await historyTask
        let garmin = await garminTask
        // A newer refresh() started while these fetches were in flight — let
        // it publish; this pass's data (and error verdict) is already stale.
        guard generation == refreshGeneration else { return }
        // A failed history read is "no new data", not "no days": an empty
        // history computes a 0 streak, which publishToWidgets would push to
        // the app group and the Watch (issue #200). Same policy as the
        // background path. A successful *empty* read still means 0 — only the
        // failure carries the last known history forward, and it carries
        // everything derived from it: the streak, the record and the week
        // bars. Today's bar can therefore lag the hero card's minutes (which
        // come from the metrics leg) until a history read succeeds again.
        // With nothing cached, nothing is known — `isHistoryKnown` then keeps
        // the computed 0 inside the app instead of publishing it.
        isHistoryKnown = fetchedHistory != nil || !cachedHistory.isEmpty
        let history = fetchedHistory ?? cachedHistory
        cachedHistory = history
        // Short-circuited on purpose: the freshness verdict is only computed
        // once a Garmin source exists, so a refresh on an Apple-only setup
        // decides nothing from the clock beyond the baseline's day stamp — as
        // it did before this hint existed.
        showsGarminSyncHint = garmin.hasGarminSource
            && GarminFreshness.needsSyncHint(status: garmin, now: date.now)
        snapshot = makeSnapshot(from: metrics, weather: weatherSnapshot, history: history)
        publishToWidgets()
        // Publish this pass's verdict last: a transient failure must not pin
        // the banner for the whole process lifetime, and clearing it mid-pass
        // would make it flicker. Bootstrap's auth errors land here too, since
        // bootstrap always ends in a refresh.
        lastError = passError
        passError = nil
    }

    /// Drop the post-walk overlay once HealthKit's own step count reaches the
    /// expected total — from there real data is complete, and keeping the
    /// overlay could mask a later edit/deletion in the Health app. The target
    /// gets a small tolerance because CMPedometer (which measured the walk)
    /// usually counts a bit more than the coprocessor total HealthKit reports —
    /// and the app deliberately never writes steps itself. Also drop it when
    /// the day changes or after `pendingWalkLifetime`: a stale overlay would
    /// show yesterday's post-walk totals as today's, in the app and widgets.
    ///
    /// `metrics` is nil when the read was refused (issue #203). Only a measured
    /// total can prove HealthKit caught up — a `.zero` fallback would clear a
    /// short walk's overlay outright, its target sitting inside the tolerance.
    /// The two clock-based reasons need no measurement and keep running: an
    /// overlay from yesterday must expire even if today's read fails, or it
    /// would ride the new day for as long as the reads keep failing.
    private func dropPendingWalkIfStale(metrics: HealthMetrics?) {
        guard let pending = pendingWalk else { return }
        let now = date.now
        let tolerance = max(50, pending.targetSteps / 50)
        let caughtUp = metrics.map { $0.steps >= pending.targetSteps - tolerance } ?? false
        let dayChanged = Calendar.current.startOfDay(for: now) != pending.day
        let expired = now.timeIntervalSince(pending.registeredAt) >= Self.pendingWalkLifetime
        if caughtUp || dayChanged || expired {
            pendingWalk = nil
        }
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
            activeDays: activeDays,
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

}

// MARK: - Error boundary

private extension TodayStore {
    func runOrTrap<T: Sendable>(
        generation: Int? = nil,
        _ body: () async throws -> T
    ) async -> T? {
        do {
            return try await body()
        } catch {
            // A superseded pass's failure is as stale as its data — only the
            // pass that will publish may record its verdict.
            if generation == nil || generation == refreshGeneration {
                passError = error.localizedDescription
            }
            return nil
        }
    }
}
