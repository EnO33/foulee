import Dependencies
import Foundation
import Testing
@testable import Foulee

/// The Connect IQ overlay where it meets the Today pass (issue #189): what
/// reaches the screen, and — the part that matters — what reaches the app group.
///
/// Asserted through `widgetPublication(stored:)`, the pure projection
/// `publishToWidgets()` performs, for the same reason as the #200/#201 suites:
/// `SharedStore` lives in the process-global app group, so seeding it and
/// reading it back would race every other suite running in parallel.
@Suite("TodayStore Garmin overlay")
struct TodayStoreGarminOverlayTests {
    private struct MetricsDown: Error, LocalizedError {
        var errorDescription: String? { "Santé verrouillée" }
    }

    private static let calendar = Calendar.current

    /// Local noon today — the fixed clock every case runs against, so the
    /// day-stamp assertions can't flake near midnight.
    private static var noon: Date { calendar.startOfDay(for: .now).addingTimeInterval(12 * 60 * 60) }

    /// The overlay the Connect IQ store would hand this pass, built the way
    /// ingestion builds it — through the freshness gate, on the same clock the
    /// store reads. `daysAgo` puts the snapshot on another day, where the gate
    /// must refuse it outright.
    private static func watchOverlay(
        steps: Int = 0,
        distanceCm: Int = 0,
        activeMinutes: Int = 0,
        daysAgo: Int = 0
    ) -> @Sendable (Date) -> GarminSnapshotOverlay.Contribution? {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: noon) ?? noon
        let snapshot = GarminDailySnapshot(
            steps: steps, distanceCm: distanceCm, activeMinutes: activeMinutes,
            activeMinutesVigorous: 0, calories: 0,
            timestamp: day.addingTimeInterval(-2 * 60), generation: 5
        )
        return { now in GarminSnapshotOverlay.contribution(of: snapshot, now: now, calendar: calendar) }
    }

    /// The app group as a background wake left it earlier **today**.
    private static func storedToday() -> WidgetSnapshot {
        WidgetSnapshot(
            steps: 4_200, stepsGoal: 6_000, minutes: 21, minutesGoal: 20,
            distanceKm: 3.1, calories: 180, streak: 12, waterML: 750,
            day: calendar.startOfDay(for: .now)
        )
    }

    @Test("A fresh watch snapshot lifts today's counters — without ever adding them")
    @MainActor
    func freshSnapshotLiftsCountersWithoutAdding() async throws {
        try await withDependencies {
            $0.date = .constant(Self.noon)
            $0.healthKit.todayMetrics = {
                HealthMetrics(steps: 4_000, distanceKm: 3.0, activeMinutes: 18, activeCalories: 210)
            }
            $0.garminConnectIQ.todayOverlay = Self.watchOverlay(steps: 4_200, distanceCm: 320_000, activeMinutes: 24)
        } operation: {
            let store = try StreakTestSupport.everyDayStore()
            await store.refresh()

            // 4 000 in Santé and 4 200 on the watch are one day of 4 200 steps.
            #expect(store.snapshot?.steps == 4_200)
            #expect(store.snapshot?.steps != 8_200)
            #expect(store.snapshot?.distanceKm == 3.2)
            #expect(store.snapshot?.minutes == 24)
            // Garmin sends a *total* burn; calories stay HealthKit's.
            #expect(store.snapshot?.calories == 210)

            let publication = try #require(store.widgetPublication(stored: Self.storedToday()))
            #expect(publication.snapshot.steps == 4_200)
            #expect(publication.snapshot.minutes == 24)
        }
    }

    @Test("Santé catching up higher takes the display back — the overlay never latches")
    @MainActor
    func healthKitCatchingUpWins() async throws {
        try await withDependencies {
            $0.date = .constant(Self.noon)
            $0.healthKit.todayMetrics = {
                HealthMetrics(steps: 11_500, distanceKm: 8.4, activeMinutes: 46, activeCalories: 500)
            }
            $0.garminConnectIQ.todayOverlay = Self.watchOverlay(steps: 9_000, distanceCm: 700_000, activeMinutes: 30)
        } operation: {
            let store = try StreakTestSupport.everyDayStore()
            await store.refresh()
            #expect(store.snapshot?.steps == 11_500)
            #expect(store.snapshot?.distanceKm == 8.4)
            #expect(store.snapshot?.minutes == 46)
        }
    }

    @Test("A hybrid user's Apple Watch minutes are never replaced")
    @MainActor
    func appleMinutesSurviveTheOverlay() async throws {
        try await withDependencies {
            $0.date = .constant(Self.noon)
            // `todayMetrics` already merges appleExerciseTime with the workouts
            // (see ActiveMinutes) — 52 minutes here is Apple's own figure.
            $0.healthKit.todayMetrics = {
                HealthMetrics(steps: 12_400, distanceKm: 9.1, activeMinutes: 52, activeCalories: 430)
            }
            $0.garminConnectIQ.todayOverlay = Self.watchOverlay(steps: 8_000, distanceCm: 600_000, activeMinutes: 35)
        } operation: {
            let store = try StreakTestSupport.everyDayStore()
            await store.refresh()
            #expect(store.snapshot?.minutes == 52)
            #expect(store.snapshot?.steps == 12_400)
        }
    }

    @Test("A watch snapshot from yesterday contributes nothing to today")
    @MainActor
    func yesterdaysSnapshotContributesNothing() async throws {
        try await withDependencies {
            $0.date = .constant(Self.noon)
            $0.healthKit.todayMetrics = {
                HealthMetrics(steps: 300, distanceKm: 0.2, activeMinutes: 1, activeCalories: 12)
            }
            $0.garminConnectIQ.todayOverlay = Self.watchOverlay(steps: 14_000, distanceCm: 900_000, activeMinutes: 90, daysAgo: 1)
        } operation: {
            let store = try StreakTestSupport.everyDayStore()
            await store.refresh()

            // The overlay that bit #144, #152 and #203: yesterday's totals must
            // not ride into this morning, on screen or in the app group.
            #expect(store.snapshot?.steps == 300)
            #expect(store.snapshot?.minutes == 1)
            let publication = try #require(store.widgetPublication(stored: Self.storedToday()))
            #expect(publication.snapshot.steps == 300)
            #expect(publication.snapshot.minutes == 1)
        }
    }

    @Test("Counters never count down when the snapshot behind them expires")
    @MainActor
    func expiredOverlayStillFloorsTheCounters() async throws {
        try await withDependencies {
            $0.date = .constant(Self.noon)
            // A Garmin-only user whose Connect hasn't synced today: Santé
            // answers, and answers zero.
            $0.healthKit.todayMetrics = { .zero }
            // The watch went out of range hours ago, so no snapshot is fresh
            // enough to raise anything — but the day's floor still stands
            // (`GarminSnapshotOverlay.Floor`).
            $0.garminConnectIQ.todayOverlay = { _ in
                GarminSnapshotOverlay.Contribution(steps: 9_000, distanceKm: 7.0, activeMinutes: 40)
            }
        } operation: {
            let store = try StreakTestSupport.everyDayStore()
            await store.refresh()
            #expect(store.snapshot?.steps == 9_000)
            #expect(store.snapshot?.distanceKm == 7.0)
            #expect(store.snapshot?.minutes == 40)
            let publication = try #require(store.widgetPublication(stored: Self.storedToday()))
            #expect(publication.snapshot.steps == 9_000)
        }
    }

    @Test("A watch-only value never reaches the app group when the Santé leg is unknown")
    @MainActor
    func unknownMetricsLegPublishesNoWatchValue() async throws {
        try await withDependencies {
            $0.date = .constant(Self.noon)
            $0.healthKit.todayMetrics = { throw MetricsDown() }
            $0.garminConnectIQ.todayOverlay = Self.watchOverlay(steps: 9_000, distanceCm: 700_000, activeMinutes: 44)
        } operation: {
            let store = try StreakTestSupport.everyDayStore()
            await store.refresh()

            // Per-leg discipline (#200/#201): the overlay rides the metrics
            // leg, exactly like the post-walk one. The read was refused, so
            // this pass measured no counters at all — the on-screen snapshot
            // shows the zeros the failure computed (with the banner to explain
            // them), never the watch's own aggregate.
            #expect(store.snapshot?.steps == 0)
            #expect(store.snapshot?.minutes == 0)

            // …and what the widgets and the background wakes maintained for
            // today survives untouched in the app group.
            let publication = try #require(store.widgetPublication(stored: Self.storedToday()))
            #expect(publication.snapshot.steps == 4_200)
            #expect(publication.snapshot.minutes == 21)
            #expect(publication.snapshot.distanceKm == 3.1)
            #expect(store.lastError == "Santé verrouillée")
        }
    }

    @Test("With nothing stored either, a refused leg publishes zeros, not the watch's day")
    @MainActor
    func unknownMetricsLegOnFirstInstallPublishesZeros() async throws {
        try await withDependencies {
            $0.date = .constant(Self.noon)
            $0.healthKit.todayMetrics = { throw MetricsDown() }
            $0.garminConnectIQ.todayOverlay = Self.watchOverlay(steps: 9_000, distanceCm: 700_000, activeMinutes: 44)
        } operation: {
            let store = try StreakTestSupport.everyDayStore()
            await store.refresh()
            let publication = try #require(store.widgetPublication(stored: nil))
            #expect(publication.snapshot.steps == 0)
            #expect(publication.snapshot.minutes == 0)
        }
    }
}
