import Dependencies
import Foundation
import Testing
@testable import Foulee

/// A refused metrics read is "no new counters", not "zero steps" (issue #201).
/// `refresh()` coalesced the failure to `.zero`, so `publishToWidgets()` wrote
/// 0 steps / 0 minutes / 0 km / 0 kcal into the app group and reloaded the
/// widgets on them — the counters flip-flopped between the real value and 0
/// depending on whether the last writer was a failed foreground pass or a
/// successful background wake. The background path keeps the stored value per
/// leg since #199; these pin the same policy on the foreground one.
///
/// Asserted through `widgetPublication(stored:)`, the pure projection
/// `publishToWidgets()` performs — same reason as the history suite:
/// `SharedStore` lives in the process-global app group, so seeding it and
/// reading it back would race with every other suite running in parallel.
@Suite("TodayStore metrics failure")
struct TodayStoreMetricsFailureTests {
    private struct MetricsDown: Error, LocalizedError {
        var errorDescription: String? { "Santé verrouillée" }
    }

    @Test("A failing metrics read carries the stored counters forward")
    @MainActor
    func failedMetricsCarriesStoredCountersForward() async throws {
        try await withDependencies {
            $0.healthKit.todayMetrics = { throw MetricsDown() }
        } operation: {
            let store = try StreakTestSupport.everyDayStore()
            await store.refresh()

            // In-app: the honest local state is zeros plus the banner.
            #expect(store.snapshot?.steps == 0)
            #expect(store.lastError == "Santé verrouillée")

            // Shared: what the widgets and the background wakes maintained for
            // today survives this pass untouched.
            let publication = try #require(store.widgetPublication(stored: Self.storedToday()))
            #expect(publication.snapshot.steps == 4_200)
            #expect(publication.snapshot.minutes == 21)
            #expect(publication.snapshot.distanceKm == 3.1)
            #expect(publication.snapshot.calories == 180)
            #expect(publication.snapshot.waterML == 750)
        }
    }

    @Test("A failing metrics read still pushes the streak to the Watch")
    @MainActor
    func failedMetricsStillPushesWatchPayload() async throws {
        try await withDependencies {
            $0.healthKit.todayMetrics = { throw MetricsDown() }
            $0.healthKit.dailyMinutes = StreakTestSupport.windowed {
                StreakTestSupport.walkedDays(Array(0...10))
            }
        } operation: {
            let store = try StreakTestSupport.everyDayStore()
            await store.refresh()

            // The payload carries the streak, the goals and the hydration
            // prefs — no counters — so a broken metrics leg says nothing about
            // its trustworthiness. The history leg answered; push it.
            let publication = try #require(store.widgetPublication(stored: Self.storedToday()))
            #expect(publication.watchPayload?.streak == 11)
        }
    }

    @Test("A failing metrics read doesn't resurrect yesterday's counters")
    @MainActor
    func failedMetricsDoesNotResurrectYesterdaysCounters() async throws {
        try await withDependencies {
            $0.healthKit.todayMetrics = { throw MetricsDown() }
            $0.healthKit.dailyMinutes = { _ in throw MetricsDown() }
        } operation: {
            let store = try StreakTestSupport.everyDayStore()
            await store.refresh()

            // The stored snapshot predates midnight: it holds no knowledge of
            // today, so carrying it forward must yield zeros, not last night's
            // totals stamped as today's (issues #144, #152).
            let publication = try #require(store.widgetPublication(stored: Self.storedYesterday()))
            #expect(publication.snapshot.steps == 0)
            #expect(publication.snapshot.minutes == 0)
            #expect(publication.snapshot.distanceKm == 0)
            #expect(publication.snapshot.calories == 0)
            #expect(publication.snapshot.waterML == 0)
            // Only the counters go stale: the history leg is down too, and the
            // streak it carries forward is not a "today" value — it survives
            // midnight untouched.
            #expect(publication.snapshot.streak == 12)
        }
    }

    @Test("A read metrics wins over the stored counters, downwards too")
    @MainActor
    func measuredMetricsWinOverStoredCounters() async throws {
        try await withDependencies {
            $0.healthKit.todayMetrics = {
                HealthMetrics(steps: 1_100, distanceKm: 0.8, activeMinutes: 6, activeCalories: 40)
            }
        } operation: {
            let store = try StreakTestSupport.everyDayStore()
            await store.refresh()

            // Carrying forward is a fallback, never a latch: a measured value
            // overwrites the stored one even when it is smaller (Santé edits,
            // a deleted sample).
            let publication = try #require(store.widgetPublication(stored: Self.storedToday()))
            #expect(publication.snapshot.steps == 1_100)
            #expect(publication.snapshot.minutes == 6)
            #expect(publication.snapshot.distanceKm == 0.8)
            #expect(publication.snapshot.calories == 40)
        }
    }

    @Test("Both legs failing on a cold launch invents nothing")
    @MainActor
    func bothLegsFailingOnColdLaunchInventsNothing() async throws {
        try await withDependencies {
            $0.healthKit.todayMetrics = { throw MetricsDown() }
            $0.healthKit.dailyMinutes = { _ in throw MetricsDown() }
        } operation: {
            let store = try StreakTestSupport.everyDayStore()
            await store.refresh()
            #expect(store.snapshot != nil)

            // Nothing stored (first install), nothing read: the zeros go out
            // because they can't overwrite a value anyone measured, and no
            // unmeasured streak reaches the Watch.
            let firstEver = try #require(store.widgetPublication(stored: nil))
            #expect(firstEver.snapshot.steps == 0)
            #expect(firstEver.snapshot.streak == 0)
            #expect(firstEver.watchPayload == nil)

            // With a stored snapshot from today, every leg keeps its value.
            let publication = try #require(store.widgetPublication(stored: Self.storedToday()))
            #expect(publication.snapshot.steps == 4_200)
            #expect(publication.snapshot.streak == 12)
            #expect(publication.watchPayload == nil)
        }
    }

    /// The app group as a background wake left it earlier **today**.
    private static func storedToday() -> WidgetSnapshot {
        WidgetSnapshot(
            steps: 4_200, stepsGoal: 6_000, minutes: 21, minutesGoal: 20,
            distanceKm: 3.1, calories: 180, streak: 12, waterML: 750,
            day: Calendar.current.startOfDay(for: .now)
        )
    }

    /// The same snapshot, last written before midnight.
    private static func storedYesterday() -> WidgetSnapshot {
        var snapshot = storedToday()
        snapshot.day = Calendar.current.date(
            byAdding: .day,
            value: -1,
            to: Calendar.current.startOfDay(for: .now)
        )
        return snapshot
    }
}
