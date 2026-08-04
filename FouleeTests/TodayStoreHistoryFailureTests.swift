import Dependencies
import Foundation
import Testing
@testable import Foulee

/// A failed history read is "no new data", not "no days" (issue #200).
/// `refresh()` used to coalesce the failure to `[]`, so `StreakCalculator`
/// answered 0 and `publishToWidgets()` pushed that 0 into the app group and to
/// the Watch — the widget then flip-flopped between 0 and N depending on
/// whether the last writer was a failed foreground pass or a successful
/// background wake. The background path keeps the stored value on a refused
/// read; these pin the same policy here.
///
/// What the app group and the Watch receive is asserted through
/// `widgetPublication(stored:)`, the pure projection `publishToWidgets()`
/// performs: `SharedStore` lives in the app group, process-global and shared by
/// every suite running in parallel, so seeding it and reading it back would
/// race with any other test's refresh. Feeding the "stored" snapshot in as an
/// argument makes the same scenario deterministic, and still covers the wiring
/// — the store answers from the history knowledge its own `refresh()` recorded.
@Suite("TodayStore history failure")
struct TodayStoreHistoryFailureTests {
    private struct HistoryDown: Error, LocalizedError {
        var errorDescription: String? { "Santé verrouillée" }
    }

    /// Walked days over the goal, plus a `dailyMinutes` stub that starts
    /// answering and then throws once `failing` flips.
    private static func failableHistory(
        _ failing: LockedRef<Bool>,
        offsets: [Int]
    ) -> @Sendable (Int) async throws -> [DailyMinutes] {
        let windowed = StreakTestSupport.windowed { StreakTestSupport.walkedDays(offsets) }
        return { daysBack in
            if failing.value { throw HistoryDown() }
            return try await windowed(daysBack)
        }
    }

    @Test("A failing history keeps the last known streak, record and week bars")
    @MainActor
    func failedHistoryKeepsLastKnownValues() async throws {
        let failing = LockedRef(false)
        try await withDependencies {
            $0.date = .constant(.now)
            $0.healthKit.dailyMinutes = Self.failableHistory(failing, offsets: Array(0...10))
        } operation: {
            let store = try StreakTestSupport.everyDayStore()
            await store.refresh()
            #expect(store.snapshot?.streak == 11)
            #expect(store.snapshot?.bestStreak == 11)
            let weekBars = store.snapshot?.weekMinutes

            // The phone locks mid-read: values hold, and the failure is still
            // surfaced for the in-screen banner.
            failing.set(true)
            await store.refresh()
            #expect(store.snapshot?.streak == 11)
            #expect(store.snapshot?.bestStreak == 11)
            #expect(store.snapshot?.weekMinutes == weekBars)
            #expect(store.lastError == "Santé verrouillée")
        }
    }

    @Test("A failing history doesn't blank today's steps and minutes")
    @MainActor
    func failedHistoryKeepsTodaysMetrics() async throws {
        let failing = LockedRef(false)
        try await withDependencies {
            $0.date = .constant(.now)
            $0.healthKit.dailyMinutes = Self.failableHistory(failing, offsets: Array(0...10))
            $0.healthKit.todayMetrics = {
                HealthMetrics(steps: 8_120, distanceKm: 5.4, activeMinutes: 32, activeCalories: 240)
            }
        } operation: {
            let store = try StreakTestSupport.everyDayStore()
            await store.refresh()

            // Metrics and history fail independently — the metrics leg
            // succeeded here, so today's counters stand.
            failing.set(true)
            await store.refresh()
            #expect(store.snapshot?.steps == 8_120)
            #expect(store.snapshot?.minutes == 32)
            #expect(store.snapshot?.hasWalkedToday == true)
        }
    }

    @Test("A failing history doesn't destroy the cache apply(preferences:) re-derives from")
    @MainActor
    func failedHistoryKeepsCacheForPreferenceChanges() async throws {
        let failing = LockedRef(false)
        try await withDependencies {
            $0.date = .constant(.now)
            $0.healthKit.dailyMinutes = Self.failableHistory(failing, offsets: Array(0...10))
        } operation: {
            let store = try StreakTestSupport.everyDayStore()
            await store.refresh()
            failing.set(true)
            await store.refresh()

            // Lowering the goal re-derives the streaks from the cached history:
            // a wiped cache would answer 0 here.
            let preferences = try Self.everyDayPreferences(minutesGoal: 10)
            store.apply(preferences: preferences)
            #expect(store.snapshot?.streak == 11)
            #expect(store.snapshot?.bestStreak == 11)
        }
    }

    @Test("First launch with no cache and a failing history yields an honest zero")
    @MainActor
    func firstLaunchWithoutCacheYieldsZero() async throws {
        try await withDependencies {
            $0.date = .constant(.now)
            $0.healthKit.dailyMinutes = { _ in throw HistoryDown() }
        } operation: {
            let store = try StreakTestSupport.everyDayStore()
            await store.refresh()

            // Nothing is known yet — 0 is the honest answer, not a regression.
            #expect(store.snapshot != nil)
            #expect(store.snapshot?.streak == 0)
            #expect(store.snapshot?.bestStreak == 0)
            #expect(store.snapshot?.weekMinutes == Array(repeating: 0, count: 7))
            #expect(store.lastError == "Santé verrouillée")
        }
    }

    @Test("A cold launch with a failing history publishes no streak of its own")
    @MainActor
    func coldLaunchWithFailingHistoryKeepsPublishedStreak() async throws {
        try await withDependencies {
            $0.date = .constant(.now)
            $0.healthKit.dailyMinutes = { _ in throw HistoryDown() }
        } operation: {
            // Fresh process: the cache is empty and the very first read is
            // refused, so this pass measures no streak at all.
            let store = try StreakTestSupport.everyDayStore()
            await store.refresh()
            #expect(store.snapshot?.streak == 0)

            // The app group still holds what the widget and the background
            // wakes maintained — that value must survive this pass, and no
            // unmeasured streak may reach the Watch.
            let publication = try #require(store.widgetPublication(stored: Self.stored(streak: 12)))
            #expect(publication.snapshot.streak == 12)
            #expect(publication.watchPayload == nil)

            // Nothing stored either (first install): the honest 0 goes out,
            // since it can't overwrite a value anyone measured.
            let firstEver = try #require(store.widgetPublication(stored: nil))
            #expect(firstEver.snapshot.streak == 0)
            #expect(firstEver.watchPayload == nil)
        }
    }

    @Test("A read history publishes its own streak, over the stored one, and to the Watch")
    @MainActor
    func readHistoryPublishesItsOwnStreak() async throws {
        try await withDependencies {
            $0.date = .constant(.now)
            $0.healthKit.dailyMinutes = StreakTestSupport.windowed {
                StreakTestSupport.walkedDays(Array(0...10))
            }
        } operation: {
            let store = try StreakTestSupport.everyDayStore()
            await store.refresh()

            // Carrying forward is scoped to the unknown case: a measured
            // streak overwrites the stored one and rides to the Watch.
            let publication = try #require(store.widgetPublication(stored: Self.stored(streak: 12)))
            #expect(publication.snapshot.streak == 11)
            #expect(publication.watchPayload?.streak == 11)
        }
    }

    @Test("A recovered history overrides the carried-forward one, downwards too")
    @MainActor
    func recoveredHistoryOverridesCarriedValues() async throws {
        let history = LockedRef(StreakTestSupport.walkedDays(Array(0...10)))
        let failing = LockedRef(false)
        let windowed = StreakTestSupport.windowed { history.value }
        try await withDependencies {
            $0.date = .constant(.now)
            $0.healthKit.dailyMinutes = { daysBack in
                if failing.value { throw HistoryDown() }
                return try await windowed(daysBack)
            }
        } operation: {
            let store = try StreakTestSupport.everyDayStore()
            await store.refresh()
            failing.set(true)
            await store.refresh()
            #expect(store.snapshot?.streak == 11)

            // Carrying forward is a fallback, never a latch: once Santé answers
            // again, a shorter history must shorten the streak.
            history.set(StreakTestSupport.walkedDays([0, 1, 2]))
            failing.set(false)
            await store.refresh()
            #expect(store.snapshot?.streak == 3)
            #expect(store.snapshot?.bestStreak == 3)
            #expect(store.lastError == nil)
        }
    }

    @Test("A successful but empty history still reads as zero")
    @MainActor
    func successfulEmptyHistoryStillZeroes() async throws {
        let history = LockedRef(StreakTestSupport.walkedDays(Array(0...10)))
        try await withDependencies {
            $0.date = .constant(.now)
            $0.healthKit.dailyMinutes = StreakTestSupport.windowed { history.value }
        } operation: {
            let store = try StreakTestSupport.everyDayStore()
            await store.refresh()
            #expect(store.snapshot?.streak == 11)

            // Santé answered "no days" — the user deleted their history, which
            // is data, not a failure.
            history.set([:])
            await store.refresh()
            #expect(store.snapshot?.streak == 0)
            #expect(store.snapshot?.bestStreak == 0)
        }
    }

    /// The app group as a previous run (foreground pass, background wake or
    /// widget intent) left it.
    private static func stored(streak: Int) -> WidgetSnapshot {
        WidgetSnapshot(
            steps: 4_200, stepsGoal: 6_000, minutes: 21, minutesGoal: 20,
            distanceKm: 3.1, calories: 180, streak: streak
        )
    }

    @MainActor
    private static func everyDayPreferences(minutesGoal: Int) throws -> UserPreferences {
        let suiteName = "TodayStoreHistoryFailure-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = UserPreferences(defaults: defaults)
        preferences.activeDays = Set(Weekday.allCases)
        preferences.minutesGoal = minutesGoal
        return preferences
    }
}
