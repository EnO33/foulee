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

    @Test("Refresh fills weather when location is granted and WeatherKit responds")
    @MainActor
    func refreshPopulatesWeather() async {
        await withDependencies {
            $0.healthKit = HealthKitClient(
                isAvailable: { true },
                requestAuthorization: { true },
                todayMetrics: {
                    HealthMetrics(steps: 100, distanceKm: 0.05, activeMinutes: 1, activeCalories: 4)
                },
                saveWalkingWorkout: { _ in }
            )
            $0.location = .previewValue
            $0.weather = WeatherClient(
                middayForecast: { _ in
                    WeatherSnapshot(
                        temperatureCelsius: 18,
                        condition: "Partiellement nuageux",
                        advice: "idéal"
                    )
                }
            )
        } operation: {
            let store = TodayStore()
            await store.refresh()

            #expect(store.snapshot?.weather.temperatureCelsius == 18)
            #expect(store.snapshot?.weather.condition == "Partiellement nuageux")
            #expect(store.snapshot?.weather.advice == "idéal")
        }
    }

    @Test("Refresh still completes when location is denied — weather stays on fallback")
    @MainActor
    func refreshSkipsWeatherWithoutLocation() async {
        await withDependencies {
            $0.healthKit = HealthKitClient(
                isAvailable: { true },
                requestAuthorization: { true },
                todayMetrics: {
                    HealthMetrics(steps: 100, distanceKm: 0.05, activeMinutes: 1, activeCalories: 4)
                },
                saveWalkingWorkout: { _ in }
            )
            $0.location = .testValue
            $0.weather = WeatherClient(
                middayForecast: { _ in
                    Issue.record("middayForecast should not run without location")
                    return WeatherSnapshot(temperatureCelsius: 0, condition: "", advice: "")
                }
            )
        } operation: {
            let store = TodayStore()
            await store.refresh()

            #expect(store.snapshot != nil)
            #expect(store.snapshot?.weather.condition == "—")
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
