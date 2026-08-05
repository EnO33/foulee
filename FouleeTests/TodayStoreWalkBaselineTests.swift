import Dependencies
import Foundation
import Testing
@testable import Foulee

/// The post-walk overlay's baseline (issue #203). `refresh()` committed
/// `lastRawMetrics` from the `.zero` fallback of a refused read, so after a
/// failed pass `walkWillStart()` baselined the next walk on 0: the overlay
/// targeted the walk's own steps alone and dissolved on the first successful
/// read — exactly when the user opens the app to see their walk. This is the
/// in-app state, distinct from the shared-snapshot rules of #200/#201.
///
/// The rule pinned here: only a leg that answered may move the baseline, and
/// only a measured total may retire the overlay. Time still may — an overlay
/// from yesterday expires whatever HealthKit answers.
@Suite("TodayStore walk baseline")
struct TodayStoreWalkBaselineTests {
    private struct MetricsDown: Error, LocalizedError {
        var errorDescription: String? { "Santé verrouillée" }
    }

    @Test("A failed metrics read keeps the last known walk baseline")
    @MainActor
    func failedReadKeepsWalkBaseline() async {
        let failing = LockedRef(false)
        await withDependencies {
            $0.date = .constant(.now)
            $0.healthKit.todayMetrics = {
                if failing.value { throw MetricsDown() }
                return HealthMetrics(
                    steps: 3_000,
                    distanceKm: 2.0,
                    activeMinutes: 12,
                    activeCalories: 90
                )
            }
        } operation: {
            let store = TodayStore()
            await store.refresh()
            #expect(store.snapshot?.steps == 3_000)

            // Santé goes away (locked device, permission revoked): the screen
            // falls back to zeros plus the banner, but that 0 is nobody's
            // measurement — it must not become the next walk's starting point.
            failing.set(true)
            await store.refresh()
            #expect(store.lastError == "Santé verrouillée")

            store.walkWillStart()
            var session = WalkSession(startedAt: .now)
            session.steps = 1_200
            session.distanceMeters = 1_000
            await store.registerFinishedWalk(session)
            #expect(store.snapshot?.steps == 4_200)

            // HealthKit answers again but still lags the walk: the overlay has
            // to cover that gap. Targeted at 1 200 it would already be gone.
            failing.set(false)
            await store.refresh()
            #expect(store.snapshot?.steps == 4_200)
            #expect(store.snapshot?.distanceKm == 3.0)
        }
    }

    @Test("A successful read still moves the baseline, downwards too")
    @MainActor
    func successfulReadMovesBaselineBothWays() async {
        let hkSteps = LockedRef(3_000)
        await withDependencies {
            $0.date = .constant(.now)
            $0.healthKit.todayMetrics = {
                HealthMetrics(
                    steps: hkSteps.value,
                    distanceKm: 2.0,
                    activeMinutes: 12,
                    activeCalories: 90
                )
            }
        } operation: {
            let store = TodayStore()
            await store.refresh()
            hkSteps.set(5_000)
            await store.refresh()

            // Keeping the baseline on failure is a fallback, never a latch:
            // the walk starts from the freshest measurement.
            store.walkWillStart()
            var first = WalkSession(startedAt: .now)
            first.steps = 1_000
            first.distanceMeters = 800
            await store.registerFinishedWalk(first)
            #expect(store.snapshot?.steps == 6_000)

            // Samples deleted in Santé pull the baseline back down — a latched
            // 5 000 would keep targeting 6 000 here.
            hkSteps.set(2_000)
            await store.refresh()
            store.walkWillStart()
            var second = WalkSession(startedAt: .now)
            second.steps = 1_000
            second.distanceMeters = 800
            await store.registerFinishedWalk(second)
            #expect(store.snapshot?.steps == 3_000)
        }
    }

    @Test("An overlay from yesterday expires even when today's read fails")
    @MainActor
    func overlayExpiresAcrossMidnightWithoutMetrics() async {
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: .now)
        guard let nextMidnight = calendar.date(byAdding: .day, value: 1, to: midnight),
              let evening = calendar.date(byAdding: .minute, value: -10, to: nextMidnight),
              let morning = calendar.date(byAdding: .minute, value: 10, to: nextMidnight) else {
            Issue.record("could not derive dates around midnight")
            return
        }
        let now = LockedRef(evening)
        let failing = LockedRef(false)
        let hkSteps = LockedRef(6_000)
        await withDependencies {
            $0.date = DateGenerator { now.value }
            $0.healthKit.todayMetrics = {
                if failing.value { throw MetricsDown() }
                return HealthMetrics(
                    steps: hkSteps.value,
                    distanceKm: 4.0,
                    activeMinutes: 40,
                    activeCalories: 200
                )
            }
        } operation: {
            let store = TodayStore()
            await store.refresh()
            store.walkWillStart()
            var session = WalkSession(startedAt: now.value)
            session.steps = 1_000
            session.distanceMeters = 800
            await store.registerFinishedWalk(session)
            #expect(store.snapshot?.steps == 7_000)

            // The day rolls over and Santé is unreadable. Withholding the
            // catch-up verdict must not make the overlay immortal: the
            // clock-based reasons don't need a measurement, so yesterday's
            // post-walk totals still can't be shown as today's.
            now.set(morning)
            failing.set(true)
            await store.refresh()
            #expect(store.snapshot?.steps == 0)

            // Really retired, not just outranked by the max().
            failing.set(false)
            hkSteps.set(500)
            await store.refresh()
            #expect(store.snapshot?.steps == 500)
        }
    }

    @Test("A refused read can't retire a short walk's overlay through the tolerance")
    @MainActor
    func refusedReadKeepsShortWalkOverlay() async {
        await withDependencies {
            $0.date = .constant(.now)
            $0.healthKit.todayMetrics = { throw MetricsDown() }
        } operation: {
            // Nothing was ever read, so the baseline is a genuine 0 and the
            // target is the walk alone — small enough to sit inside the
            // catch-up tolerance. Fed the `.zero` fallback, the overlay would
            // be declared reconciled the instant it is created.
            let store = TodayStore()
            await store.refresh()
            store.walkWillStart()
            var session = WalkSession(startedAt: .now)
            session.steps = 30
            session.distanceMeters = 25
            await store.registerFinishedWalk(session)

            #expect(store.snapshot?.steps == 30)
        }
    }

    @Test("A baseline measured yesterday can't seed a walk taken after midnight")
    @MainActor
    func staleBaselineNeverSeedsTodaysWalk() async throws {
        let calendar = Calendar.current
        guard let nextMidnight = calendar.date(
            byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)
        ),
            let evening = calendar.date(byAdding: .minute, value: -10, to: nextMidnight),
            let morning = calendar.date(byAdding: .minute, value: 10, to: nextMidnight) else {
            Issue.record("could not derive dates around midnight")
            return
        }
        let now = LockedRef(evening)
        let failing = LockedRef(false)
        let hk = LockedRef(HealthMetrics(
            steps: 12_000, distanceKm: 8.0, activeMinutes: 45, activeCalories: 300
        ))
        try await withDependencies {
            $0.date = DateGenerator { now.value }
            $0.healthKit.todayMetrics = {
                if failing.value { throw MetricsDown() }
                return hk.value
            }
        } operation: {
            let store = TodayStore()
            await store.refresh()
            #expect(store.snapshot?.steps == 12_000)

            // The day rolls over and Santé stops answering. Keeping the last
            // known baseline is only ever about *today's* counters — carried
            // into the new day it would post yesterday's evening total as this
            // morning's starting point.
            now.set(morning)
            failing.set(true)
            await store.refresh()
            store.walkWillStart()
            var session = WalkSession(startedAt: now.value)
            session.steps = 1_000
            session.distanceMeters = 800
            await store.registerFinishedWalk(session)
            #expect(store.snapshot?.steps == 1_000)
            #expect(store.snapshot?.distanceKm == 0.8)

            // And the recovered read wins: a 13 000 target sits far out of
            // catch-up reach, so the overlay would outlive the failure — and
            // `isMetricsKnown` would then hand it to the widgets as measured.
            failing.set(false)
            hk.set(HealthMetrics(
                steps: 1_200, distanceKm: 0.9, activeMinutes: 8, activeCalories: 40
            ))
            await store.refresh()
            #expect(store.snapshot?.steps == 1_200)
            let publication = try #require(store.widgetPublication(stored: Self.storedToday()))
            #expect(publication.snapshot.steps == 1_200)
        }
    }

    /// The app group as an earlier wake left it — here only to prove the
    /// published value is the fresh reading and not something carried forward.
    private static func storedToday() -> WidgetSnapshot {
        WidgetSnapshot(
            steps: 4_200, stepsGoal: 6_000, minutes: 21, minutesGoal: 20,
            distanceKm: 3.1, calories: 180, streak: 12, waterML: 750,
            day: Calendar.current.startOfDay(for: .now)
        )
    }
}
