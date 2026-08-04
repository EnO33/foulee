import Foundation
import Testing
@testable import Foulee

/// The recompute decision (issue #194). Only the pure rule is covered: the
/// HealthKit path around it (`recomputedBackgroundStreak`) needs a live
/// `HKHealthStore` and a background delivery, neither of which exists in a
/// unit test.
@Suite struct BackgroundStreakRefreshTests {
    /// Fixed UTC calendar so the day boundaries are deterministic anywhere.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: day, hour: hour))!
    }

    private func decide(
        storedDay: Date?,
        storedMinutes: Int = 0,
        todayMinutes: Int = 0,
        goalMinutes: Int = 20,
        wake: BackgroundStreakRefresh.Wake = .other,
        lastRecomputeAt: Date?,
        pendingCrossing: Bool = false,
        now: Date
    ) -> Bool {
        BackgroundStreakRefresh.shouldRecompute(
            BackgroundStreakRefresh.Trigger(
                storedDay: storedDay,
                storedMinutes: storedMinutes,
                todayMinutes: todayMinutes,
                goalMinutes: goalMinutes,
                wake: wake,
                lastRecomputeAt: lastRecomputeAt,
                pendingCrossing: pendingCrossing,
                now: now
            ),
            calendar: calendar
        )
    }

    private func cleanDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.streak.\(UUID().uuidString)")!
    }

    // MARK: - Day rollover

    @Test func snapshotFromAnotherDayRecomputes() {
        // Yesterday's verdict is now final and today restarts from zero.
        #expect(decide(
            storedDay: date(11, 0), lastRecomputeAt: date(11, 22), now: date(12, 8)
        ))
    }

    @Test func firstWakeEverRecomputes() {
        #expect(decide(storedDay: nil, lastRecomputeAt: nil, now: date(12, 8)))
    }

    @Test func failedRecomputeEarlierTodayIsRetried() {
        // Snapshot stamped today (the write happens even when the streak read
        // failed), but no recompute landed today — retry, throttle permitting.
        #expect(decide(
            storedDay: date(12, 0), lastRecomputeAt: date(11, 22), now: date(12, 8)
        ))
    }

    // MARK: - Workout deliveries

    @Test func workoutWakeRecomputes() {
        #expect(decide(
            storedDay: date(12, 0), wake: .workout,
            lastRecomputeAt: date(12, 6), now: date(12, 8)
        ))
    }

    @Test func throttleSuppressesABurstOfWorkouts() {
        // One Garmin sync delivers a dozen workouts within seconds.
        #expect(!decide(
            storedDay: date(12, 0), wake: .workout,
            lastRecomputeAt: date(12, 8).addingTimeInterval(-60), now: date(12, 8)
        ))
    }

    @Test func workoutRecomputesAgainOnceTheThrottleElapsed() {
        #expect(decide(
            storedDay: date(12, 0), wake: .workout,
            lastRecomputeAt: date(12, 8).addingTimeInterval(-BackgroundStreakRefresh.throttle),
            now: date(12, 8)
        ))
    }

    // MARK: - Goal crossing

    @Test func todayCrossingTheGoalRecomputes() {
        #expect(decide(
            storedDay: date(12, 0), storedMinutes: 12, todayMinutes: 25,
            lastRecomputeAt: date(12, 6), now: date(12, 8)
        ))
    }

    @Test func goalCrossingIgnoresTheThrottle() {
        // The burst that pushed today over the goal must not be swallowed by
        // the recompute an earlier workout of the same burst just did.
        #expect(decide(
            storedDay: date(12, 0), storedMinutes: 12, todayMinutes: 25, wake: .workout,
            lastRecomputeAt: date(12, 8).addingTimeInterval(-30), now: date(12, 8)
        ))
    }

    @Test func minutesGrowingBelowTheGoalDoesNotRecompute() {
        #expect(!decide(
            storedDay: date(12, 0), storedMinutes: 5, todayMinutes: 12,
            lastRecomputeAt: date(12, 6), now: date(12, 8)
        ))
    }

    @Test func aDayAlreadyDoneDoesNotRecomputeAgain() {
        // Stored minutes already meet the goal — the +1 landed on an earlier
        // wake, more minutes can't change the streak.
        #expect(!decide(
            storedDay: date(12, 0), storedMinutes: 25, todayMinutes: 40,
            lastRecomputeAt: date(12, 6), now: date(12, 8)
        ))
    }

    // MARK: - Quiet wakes

    @Test func quietHourlyStepsWakeSkips() {
        #expect(!decide(
            storedDay: date(12, 0), storedMinutes: 4, todayMinutes: 6,
            lastRecomputeAt: date(12, 6), now: date(12, 8)
        ))
    }

    // MARK: - An unconfirmed crossing

    @Test func aCrossingWhoseRecomputeFailedIsRetried() {
        // Mid-day: a recompute landed this morning and the snapshot is stamped
        // today, so no other rule fires — without the persisted crossing the
        // +1 would wait for tomorrow's rollover.
        #expect(decide(
            storedDay: date(12, 0), storedMinutes: 25, todayMinutes: 25,
            lastRecomputeAt: date(12, 6), pendingCrossing: true, now: date(12, 8)
        ))
    }

    @Test func aPendingCrossingStillObeysTheThrottle() {
        // The retry must not turn every wake of a burst into a deep query.
        #expect(!decide(
            storedDay: date(12, 0), storedMinutes: 25, todayMinutes: 25,
            lastRecomputeAt: date(12, 8).addingTimeInterval(-60),
            pendingCrossing: true, now: date(12, 8)
        ))
    }

    // MARK: - Preferences read from the background process

    @Test func preferencesFallBackToTheAppDefaults() {
        let preferences = BackgroundStreakRefresh.preferences(defaults: cleanDefaults())
        #expect(preferences.goalMinutes == 20)
        #expect(preferences.activeDays == Weekday.workWeek)
    }

    /// Through the writer rather than the raw keys: pinning literals here
    /// would let a rename in `UserPreferences.Keys` pass while the background
    /// path silently fell back to 20 / workWeek for every user with custom
    /// settings — the app-vs-widget divergence this design exists to prevent.
    @MainActor
    @Test func preferencesReadWhatUserPreferencesWrote() {
        let defaults = cleanDefaults()
        let prefs = UserPreferences(defaults: defaults)
        prefs.minutesGoal = 45
        prefs.activeDays = [.saturday, .sunday]
        let preferences = BackgroundStreakRefresh.preferences(defaults: defaults)
        #expect(preferences.goalMinutes == 45)
        #expect(preferences.activeDays == [.saturday, .sunday])
    }

    @Test func recomputeStampRoundTrips() {
        let defaults = cleanDefaults()
        #expect(BackgroundStreakRefresh.lastRecomputeAt(defaults: defaults, now: date(12, 9)) == nil)
        BackgroundStreakRefresh.markRecomputed(at: date(12, 8), defaults: defaults)
        #expect(BackgroundStreakRefresh.lastRecomputeAt(defaults: defaults, now: date(12, 9)) == date(12, 8))
    }

    @Test func aStampInTheFutureCountsAsNoStamp() {
        // Clock pushed forward then back: honouring it would suspend the
        // throttled rules until wall-clock time caught up, not ten minutes.
        let defaults = cleanDefaults()
        BackgroundStreakRefresh.markRecomputed(at: date(20, 8), defaults: defaults)
        #expect(BackgroundStreakRefresh.lastRecomputeAt(defaults: defaults, now: date(12, 8)) == nil)
    }

    @Test func goalCrossingIsRememberedForTheDayItHappened() {
        let defaults = cleanDefaults()
        #expect(!BackgroundStreakRefresh.pendingGoalCrossing(
            defaults: defaults, now: date(12, 8), calendar: calendar
        ))
        BackgroundStreakRefresh.markGoalCrossing(at: date(12, 8), defaults: defaults)
        #expect(BackgroundStreakRefresh.pendingGoalCrossing(
            defaults: defaults, now: date(12, 22), calendar: calendar
        ))
        // Tomorrow the rollover rule takes over — a leftover crossing is void.
        #expect(!BackgroundStreakRefresh.pendingGoalCrossing(
            defaults: defaults, now: date(13, 8), calendar: calendar
        ))
        BackgroundStreakRefresh.clearGoalCrossing(defaults: defaults)
        #expect(!BackgroundStreakRefresh.pendingGoalCrossing(
            defaults: defaults, now: date(12, 22), calendar: calendar
        ))
    }
}
