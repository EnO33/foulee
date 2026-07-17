import Dependencies
import Foundation
import Testing
@testable import Foulee

/// Minimal HealthKit stub where only `todayMetrics` matters.
private func healthKitStub(
    todayMetrics: @escaping @Sendable () async throws -> HealthMetrics
) -> HealthKitClient {
    HealthKitClient(
        requestAuthorization: { true },
        todayMetrics: todayMetrics,
        saveWalkingWorkout: { _ in },
        dailyMinutes: { _ in [] },
        recentWorkouts: { _ in [] },
        workoutDetail: { summary in
            WorkoutDetail(summary: summary, heartRateSamples: [], stepsCount: 0)
        }
    )
}

@Suite("TodayStore error freshness")
struct TodayStoreErrorFreshnessTests {
    @Test("A transient failure clears once the next refresh succeeds")
    @MainActor
    func transientErrorClearsOnNextSuccess() async {
        struct Boom: Error, LocalizedError {
            var errorDescription: String? { "Santé indisponible" }
        }
        let failing = LockedRef(true)
        await withDependencies {
            $0.healthKit = healthKitStub {
                if failing.value { throw Boom() }
                return HealthMetrics(steps: 2_000, distanceKm: 1.2, activeMinutes: 15, activeCalories: 80)
            }
        } operation: {
            let store = TodayStore()
            await store.refresh()
            #expect(store.lastError == "Santé indisponible")

            // The device unlocks / HealthKit recovers: the banner must not
            // stay pinned for the rest of the process lifetime.
            failing.set(false)
            await store.refresh()
            #expect(store.lastError == nil)
            #expect(store.snapshot?.steps == 2_000)
        }
    }

    @Test("A stale refresh doesn't clobber a newer pass's outcome")
    @MainActor
    func staleRefreshDoesNotClobberNewerPass() async {
        struct Boom: Error, LocalizedError {
            var errorDescription: String? { "Santé indisponible" }
        }
        // The first todayMetrics call (the stale pass) parks on the gate;
        // later calls (the newer pass) answer immediately.
        let (gate, release) = AsyncStream<Void>.makeStream()
        let parked = LockedRef(false)
        await withDependencies {
            $0.healthKit = healthKitStub {
                if !parked.value {
                    parked.set(true)
                    for await _ in gate { break }
                    throw Boom()
                }
                return HealthMetrics(steps: 2_000, distanceKm: 1.2, activeMinutes: 15, activeCalories: 80)
            }
        } operation: {
            let store = TodayStore()
            let stalePass = Task { await store.refresh() }
            var spins = 0
            while !parked.value, spins < 10_000 {
                await Task.yield()
                spins += 1
            }
            #expect(parked.value)

            // A newer pass starts and finishes while the stale one is parked.
            await store.refresh()
            #expect(store.lastError == nil)
            #expect(store.snapshot?.steps == 2_000)

            // The stale pass now fails: its zeroed metrics and its error must
            // not overwrite the newer pass's snapshot or verdict.
            release.finish()
            await stalePass.value
            #expect(store.lastError == nil)
            #expect(store.snapshot?.steps == 2_000)
        }
    }
}

@Suite("TodayStore walk overlay staleness")
struct TodayStoreWalkOverlayStalenessTests {
    @Test("The post-walk overlay is dropped when the day changes")
    @MainActor
    func overlayDroppedOnDayChange() async {
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: .now)
        guard let nextMidnight = calendar.date(byAdding: .day, value: 1, to: midnight),
              let evening = calendar.date(byAdding: .minute, value: -10, to: nextMidnight),
              let morning = calendar.date(byAdding: .minute, value: 10, to: nextMidnight) else {
            Issue.record("could not derive dates around midnight")
            return
        }
        let now = LockedRef(evening)
        let hkSteps = LockedRef(6_000)
        await withDependencies {
            $0.date = DateGenerator { now.value }
            $0.healthKit = healthKitStub {
                HealthMetrics(steps: hkSteps.value, distanceKm: 4, activeMinutes: 40, activeCalories: 200)
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

            // Next morning (20 minutes later — well before the expiry kicks
            // in): HealthKit restarts near zero and yesterday's post-walk
            // totals must not be shown as today's.
            now.set(morning)
            hkSteps.set(0)
            await store.refresh()
            #expect(store.snapshot?.steps == 0)
            #expect(store.snapshot?.distanceKm == 4.0)
        }
    }

    @Test("The post-walk overlay expires after an hour even if the target is never reached")
    @MainActor
    func overlayExpiresAfterAnHour() async {
        // 10:00 today, so a +61 min jump stays inside the same calendar day.
        let start = Calendar.current.startOfDay(for: .now).addingTimeInterval(10 * 3_600)
        let now = LockedRef(start)
        let hkSteps = LockedRef(3_000)
        await withDependencies {
            $0.date = DateGenerator { now.value }
            $0.healthKit = healthKitStub {
                HealthMetrics(steps: hkSteps.value, distanceKm: 2, activeMinutes: 20, activeCalories: 100)
            }
        } operation: {
            let store = TodayStore()
            await store.refresh()
            store.walkWillStart()
            var session = WalkSession(startedAt: now.value)
            session.steps = 2_000
            session.distanceMeters = 1_500
            await store.registerFinishedWalk(session)
            #expect(store.snapshot?.steps == 5_000)

            // HealthKit never reconciles (target out of tolerance) — after an
            // hour the overlay is a lie, not a patch: trust HealthKit.
            now.set(start.addingTimeInterval(61 * 60))
            await store.refresh()
            #expect(store.snapshot?.steps == 3_000)
            #expect(store.snapshot?.distanceKm == 2.0)
        }
    }

    @Test("The overlay dissolves when HealthKit lands just under the target")
    @MainActor
    func overlayClearsWithinTolerance() async {
        // CMPedometer (which measured the walk) typically counts a bit more
        // than the coprocessor total HealthKit reports, so the exact target
        // may never be reached: a 2% / 50-step tolerance absorbs the gap.
        let hkSteps = LockedRef(3_000)
        await withDependencies {
            $0.date = .constant(.now)
            $0.healthKit = healthKitStub {
                HealthMetrics(steps: hkSteps.value, distanceKm: 2, activeMinutes: 20, activeCalories: 100)
            }
        } operation: {
            let store = TodayStore()
            await store.refresh()
            store.walkWillStart()
            var session = WalkSession(startedAt: .now)
            session.steps = 1_000
            session.distanceMeters = 800
            await store.registerFinishedWalk(session)
            // Target 4 000, tolerance max(50, 2%) = 80.

            hkSteps.set(3_900) // below 3 920 → overlay still covers the gap
            await store.refresh()
            #expect(store.snapshot?.steps == 4_000)

            hkSteps.set(3_925) // within tolerance → real data takes over
            await store.refresh()
            #expect(store.snapshot?.steps == 3_925)
        }
    }

    @Test("Two consecutive walks don't compound their overlays")
    @MainActor
    func consecutiveWalksDoNotCompound() async {
        // HealthKit never flushes either walk during the test window.
        let hkSteps = LockedRef(1_000)
        await withDependencies {
            $0.date = .constant(.now)
            $0.healthKit = healthKitStub {
                HealthMetrics(steps: hkSteps.value, distanceKm: 0.5, activeMinutes: 10, activeCalories: 40)
            }
        } operation: {
            let store = TodayStore()
            await store.refresh()

            store.walkWillStart()
            var first = WalkSession(startedAt: .now)
            first.steps = 500
            first.distanceMeters = 250
            await store.registerFinishedWalk(first)
            #expect(store.snapshot?.steps == 1_500)

            // Second walk: the baseline must be the raw HealthKit total
            // (1 000), not the overlay-inflated snapshot (1 500) — otherwise
            // each walk would stack on the previous one's optimism.
            store.walkWillStart()
            var second = WalkSession(startedAt: .now)
            second.steps = 500
            second.distanceMeters = 250
            await store.registerFinishedWalk(second)
            #expect(store.snapshot?.steps == 1_500)
            #expect(store.snapshot?.distanceKm == 0.75)
        }
    }
}
