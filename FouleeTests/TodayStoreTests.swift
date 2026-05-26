import Dependencies
import Foundation
import Testing
@testable import Foulee

@Suite("TodayStore")
struct TodayStoreTests {
    @Test("Refresh maps HealthMetrics into the snapshot")
    @MainActor
    func refreshPopulatesSnapshot() async {
        await withDependencies {
            $0.healthKit = HealthKitClient(
                isAvailable: { true },
                requestAuthorization: { true },
                todayMetrics: {
                    HealthMetrics(
                        steps: 1_234,
                        distanceKm: 0.5,
                        activeMinutes: 10,
                        activeCalories: 50
                    )
                },
                saveWalkingWorkout: { _ in }
            )
        } operation: {
            let store = TodayStore()
            await store.refresh()

            #expect(store.snapshot?.steps == 1_234)
            #expect(store.snapshot?.minutes == 10)
            #expect(store.snapshot?.distanceKm == 0.5)
            #expect(store.snapshot?.calories == 50)
            #expect(store.snapshot?.hasWalkedToday == false)
            #expect(store.lastError == nil)
        }
    }

    @Test("hasWalkedToday flips once activeMinutes reaches the goal")
    @MainActor
    func hasWalkedTodayFlips() async {
        await withDependencies {
            $0.healthKit = HealthKitClient(
                isAvailable: { true },
                requestAuthorization: { true },
                todayMetrics: {
                    HealthMetrics(
                        steps: 4_000,
                        distanceKm: 1.5,
                        activeMinutes: 25,
                        activeCalories: 120
                    )
                },
                saveWalkingWorkout: { _ in }
            )
        } operation: {
            let store = TodayStore()
            await store.refresh()

            #expect(store.snapshot?.hasWalkedToday == true)
        }
    }

    @Test("A throwing HealthKit surfaces lastError and leaves snapshot nil")
    @MainActor
    func failureSurfacesAsLastError() async {
        struct Boom: Error, LocalizedError {
            var errorDescription: String? { "Santé en feu" }
        }
        await withDependencies {
            $0.healthKit = HealthKitClient(
                isAvailable: { true },
                requestAuthorization: { true },
                todayMetrics: { throw Boom() },
                saveWalkingWorkout: { _ in }
            )
        } operation: {
            let store = TodayStore()
            await store.refresh()

            #expect(store.snapshot == nil)
            #expect(store.lastError == "Santé en feu")
        }
    }

    @Test("Bootstrap short-circuits when authorization is denied")
    @MainActor
    func bootstrapStopsWhenDenied() async {
        await withDependencies {
            $0.healthKit = HealthKitClient(
                isAvailable: { true },
                requestAuthorization: { false },
                todayMetrics: {
                    Issue.record("todayMetrics should not run when auth is denied")
                    return .zero
                },
                saveWalkingWorkout: { _ in }
            )
        } operation: {
            let store = TodayStore()
            await store.bootstrap()

            #expect(store.snapshot == nil)
        }
    }
}
