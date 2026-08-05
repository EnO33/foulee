import Foundation
@preconcurrency import HealthKit
import os

/// Should a Health background wake pay for a streak recompute — and the
/// recompute itself.
///
/// `refreshSnapshotMetrics` only overlays *today's* counters onto the shared
/// snapshot and carries `streak` through untouched, so it holds whatever the
/// last foreground pass computed. A Garmin user whose J-1 sessions land at J
/// and who never opens the app keeps a pre-repair streak on the Série widget
/// and the watch complication (issue #194).
///
/// Recomputing means `mergedDailyMinutes` over
/// `StreakCalculator.historyWindowDays` — a ~379-bucket statistics collection
/// plus a workouts query — far too much to run on every hourly steps wake. The
/// rule, in order:
///
/// 1. **Today just crossed the goal** (last measured minutes below it, freshly
///    measured minutes at or above): today became a "done" day, so the streak
///    gained one. Edge-triggered on `lastMeasuredMinutesToday` — the write that
///    closes this wake lifts it over the goal — so it can only fire once a day
///    and deliberately ignores the throttle, which would otherwise swallow the
///    workout burst that caused the crossing.
/// 2. Everything below is skipped less than `throttle` after the last
///    successful recompute: one Garmin sync delivers a whole burst of workouts
///    within seconds, and each of them wakes this observer.
/// 3. **A crossing no recompute confirmed** — the edge above is consumed by
///    the write that closes its wake, so a recompute that HealthKit refused
///    (or that ran past `recomputeDeadline`) would lose today's +1 until
///    tomorrow's rollover. The crossing is persisted instead, and retried
///    until a recompute lands.
/// 4. **Day rollover** — the stored snapshot is stamped another day, or no
///    recompute landed today: yesterday's verdict is now final and today
///    restarts from zero, so both ends of the streak can have moved. (The
///    second half also retries after a recompute that HealthKit refused,
///    locked-phone style.)
/// 5. **A workout delivery** — workouts are what move a Garmin user's active
///    minutes, including yesterday's when the sync is late.
///
/// Any other wake (hourly steps, water, the BGAppRefresh task) skips and keeps
/// the stored streak.
enum BackgroundStreakRefresh {
    /// What woke the observer. Only the workout type is worth a recompute on
    /// its own; steps, water and the BGAppRefresh task share `.other`.
    enum Wake: Sendable {
        case workout
        case other
    }

    /// Floor between two recomputes (rules 3 to 5).
    static let throttle: TimeInterval = 10 * 60

    /// Wall-clock budget for the deep query. The observer's completion handler
    /// is held for the whole recompute and HealthKit throttles observers whose
    /// handlers consistently overrun, so a slow read has to degrade to the
    /// stored streak rather than keep the wake open.
    static let recomputeDeadline: TimeInterval = 8

    /// Goal + active days as the background process sees them. `UserPreferences`
    /// is `@MainActor` and owns no background-readable accessor, so the values
    /// are read straight from the same defaults keys it writes — same approach
    /// as the hydration observer (issue #169) — with the same fallbacks.
    struct Preferences: Sendable {
        var goalMinutes: Int
        var activeDays: Set<Weekday>
    }

    private static let minutesGoalKey = "preferences.minutesGoal"
    private static let activeDaysKey = "preferences.activeDays"
    private static let lastRecomputeKey = "streak.lastBackgroundRecomputeAt"
    private static let pendingCrossingKey = "streak.pendingGoalCrossingAt"
    private static let measuredMinutesKey = "streak.lastMeasuredMinutes"
    private static let measuredMinutesDayKey = "streak.lastMeasuredMinutesAt"

    static func preferences(defaults: UserDefaults) -> Preferences {
        let goal = (defaults.object(forKey: minutesGoalKey) as? Int) ?? 20
        let days = (defaults.object(forKey: activeDaysKey) as? Int).map(Set<Weekday>.init(bitmask:))
        return Preferences(goalMinutes: goal, activeDays: days ?? Weekday.workWeek)
    }

    /// When the last recompute succeeded, or nil when none ever did. A stamp
    /// in the future — clock pushed forward then back, bad RTC on first boot —
    /// counts as none: honouring it would wedge every rule under the throttle
    /// until wall-clock time catches up, which is unbounded rather than the
    /// ten minutes the throttle promises.
    static func lastRecomputeAt(defaults: UserDefaults, now: Date = .now) -> Date? {
        let stamp = defaults.double(forKey: lastRecomputeKey)
        guard stamp > 0 else { return nil }
        let date = Date(timeIntervalSince1970: stamp)
        return date <= now ? date : nil
    }

    static func markRecomputed(at date: Date, defaults: UserDefaults) {
        defaults.set(date.timeIntervalSince1970, forKey: lastRecomputeKey)
    }

    /// A goal crossing seen on an earlier wake that no recompute confirmed.
    /// Day-stamped: a crossing left over from another day is void, the
    /// rollover rule already forces a recompute there.
    static func pendingGoalCrossing(
        defaults: UserDefaults,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        let stamp = defaults.double(forKey: pendingCrossingKey)
        guard stamp > 0 else { return false }
        return calendar.isDate(Date(timeIntervalSince1970: stamp), inSameDayAs: now)
    }

    static func markGoalCrossing(at date: Date, defaults: UserDefaults) {
        defaults.set(date.timeIntervalSince1970, forKey: pendingCrossingKey)
    }

    static func clearGoalCrossing(defaults: UserDefaults) {
        defaults.removeObject(forKey: pendingCrossingKey)
    }

    /// Today's active minutes as the last background wake **measured** them —
    /// HealthKit only, no Connect IQ overlay — or nil when none did today.
    ///
    /// The shared snapshot can no longer answer this question: since #189 its
    /// `minutes` carry the Garmin overlay, and the crossing below decides a
    /// streak whose history comes from HealthKit alone. Judging the edge
    /// against an overlaid value would consume it before HealthKit ever
    /// crossed the goal (or fire it on minutes HealthKit never saw). Same
    /// shape, and the same reason, as the hydration observer's own
    /// `hydration.observedWaterML` baseline: day-stamped, so yesterday's
    /// measurement is never today's "before".
    static func lastMeasuredMinutesToday(
        defaults: UserDefaults,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int? {
        let stamp = defaults.double(forKey: measuredMinutesDayKey)
        guard stamp > 0,
              calendar.isDate(Date(timeIntervalSince1970: stamp), inSameDayAs: now)
        else { return nil }
        return defaults.integer(forKey: measuredMinutesKey)
    }

    static func markMeasuredMinutes(_ minutes: Int, at date: Date, defaults: UserDefaults) {
        defaults.set(minutes, forKey: measuredMinutesKey)
        defaults.set(date.timeIntervalSince1970, forKey: measuredMinutesDayKey)
    }

    /// Everything the decision looks at: the streak the shared snapshot
    /// carries, what this wake just measured, and when the last recompute
    /// landed.
    struct Trigger: Sendable {
        /// Day stamp of the stored snapshot (nil on snapshots from older
        /// builds — treated as another day).
        var storedDay: Date?
        /// Today's minutes as the last wake measured them — HealthKit only,
        /// day-stamped (`lastMeasuredMinutesToday`), never the shared
        /// snapshot's overlaid value.
        var storedMinutes: Int
        /// Today's freshly measured minutes, about to be written.
        var todayMinutes: Int
        var goalMinutes: Int
        var wake: Wake
        var lastRecomputeAt: Date?
        /// An earlier crossing today that no recompute confirmed (rule 3).
        var pendingCrossing: Bool
        var now: Date
    }

    /// Today's minutes reached the goal on this very wake (rule 1) — the edge
    /// the persisted crossing is derived from.
    static func crossedGoal(_ trigger: Trigger) -> Bool {
        trigger.goalMinutes > 0
            && trigger.storedMinutes < trigger.goalMinutes
            && trigger.todayMinutes >= trigger.goalMinutes
    }

    /// The rule documented above, pure so it can be tested without HealthKit.
    static func shouldRecompute(_ trigger: Trigger, calendar: Calendar = .current) -> Bool {
        if crossedGoal(trigger) { return true }
        if let last = trigger.lastRecomputeAt, trigger.now.timeIntervalSince(last) < throttle { return false }
        if trigger.pendingCrossing { return true }
        let today = calendar.startOfDay(for: trigger.now)
        func isToday(_ date: Date?) -> Bool { date.map { calendar.startOfDay(for: $0) == today } ?? false }
        if !isToday(trigger.storedDay) || !isToday(trigger.lastRecomputeAt) { return true }
        switch trigger.wake {
        case .workout: return true
        case .other: return false
        }
    }
}

/// One deep query at a time. The rule above is check-then-act — the stamp only
/// lands once the history came back — so a Garmin sync delivering a dozen
/// workouts within seconds would otherwise start a dozen concurrent
/// 379-bucket queries, exactly the cost the throttle exists to avoid. A wake
/// that can't claim it keeps the stored streak. Same shape as
/// `backgroundObserversStarted`.
private let recomputeInFlight = OSAllocatedUnfairLock(initialState: false)

/// The streak to publish with this wake's snapshot, or nil to keep the stored
/// one — either the wake can't have changed it, another wake is already
/// recomputing, or HealthKit refused to answer (a locked phone must not
/// publish a zero streak).
///
/// Same history window, same merge and the same `StreakCalculator` entry point
/// as `TodayStore.makeSnapshot`, so the background value can't drift from the
/// one the app shows.
func recomputedBackgroundStreak(
    store: HKHealthStore,
    storedDay: Date?,
    storedMinutes: Int,
    todayMinutes: Int,
    wake: BackgroundStreakRefresh.Wake
) async -> Int? {
    let defaults = UserDefaults.standard
    let preferences = BackgroundStreakRefresh.preferences(defaults: defaults)
    let now = Date.now
    let trigger = BackgroundStreakRefresh.Trigger(
        storedDay: storedDay,
        storedMinutes: storedMinutes,
        todayMinutes: todayMinutes,
        goalMinutes: preferences.goalMinutes,
        wake: wake,
        lastRecomputeAt: BackgroundStreakRefresh.lastRecomputeAt(defaults: defaults, now: now),
        pendingCrossing: BackgroundStreakRefresh.pendingGoalCrossing(defaults: defaults, now: now),
        now: now
    )
    // Persist the crossing before anything below can fail: the write that
    // closes this wake lifts the stored minutes over the goal, so the edge is
    // gone by the next one.
    if BackgroundStreakRefresh.crossedGoal(trigger) {
        BackgroundStreakRefresh.markGoalCrossing(at: now, defaults: defaults)
    }
    guard BackgroundStreakRefresh.shouldRecompute(trigger) else { return nil }
    let claimed = recomputeInFlight.withLock { running -> Bool in
        guard !running else { return false }
        running = true
        return true
    }
    guard claimed else { return nil }
    defer { recomputeInFlight.withLock { $0 = false } }
    guard let history = await historyWithinDeadline(store: store) else { return nil }
    BackgroundStreakRefresh.markRecomputed(at: .now, defaults: defaults)
    BackgroundStreakRefresh.clearGoalCrossing(defaults: defaults)
    return StreakCalculator.current(
        history: history,
        goalMinutes: preferences.goalMinutes,
        activeDays: preferences.activeDays,
        today: .now
    )
}

/// The streak history, given up on past `recomputeDeadline` so the wake hands
/// HealthKit its completion handler back on time. A HealthKit continuation
/// can't be interrupted: the query the deadline abandoned finishes unobserved
/// and the next wake retries.
private func historyWithinDeadline(store: HKHealthStore) async -> [DailyMinutes]? {
    let settled = OSAllocatedUnfairLock(initialState: false)
    return await withCheckedContinuation { continuation in
        @Sendable func settle(_ history: [DailyMinutes]?) {
            let isFirst = settled.withLock { done -> Bool in
                guard !done else { return false }
                done = true
                return true
            }
            guard isFirst else { return }
            continuation.resume(returning: history)
        }
        let deadline = Task {
            try? await Task.sleep(for: .seconds(BackgroundStreakRefresh.recomputeDeadline))
            settle(nil)
        }
        Task {
            settle(try? await mergedDailyMinutes(
                store: store,
                minutesType: HKQuantityType(.appleExerciseTime),
                daysBack: StreakCalculator.historyWindowDays
            ))
            deadline.cancel()
        }
    }
}
