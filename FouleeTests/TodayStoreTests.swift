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
                saveWalkingWorkout: { _ in },
                dailyMinutes: { _ in [] },
                recentWorkouts: { _ in [] },
                workoutDetail: { summary in
                    WorkoutDetail(summary: summary, heartRateSamples: [], stepsCount: 0)
                }
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
                saveWalkingWorkout: { _ in },
                dailyMinutes: { _ in [] },
                recentWorkouts: { _ in [] },
                workoutDetail: { summary in
                    WorkoutDetail(summary: summary, heartRateSamples: [], stepsCount: 0)
                }
            )
        } operation: {
            let store = TodayStore()
            await store.refresh()

            #expect(store.snapshot?.hasWalkedToday == true)
        }
    }

    @Test("A throwing HealthKit surfaces lastError and falls back to zero metrics")
    @MainActor
    func failureFallsBackAndSurfacesError() async {
        struct Boom: Error, LocalizedError {
            var errorDescription: String? { "Santé en feu" }
        }
        await withDependencies {
            $0.healthKit = HealthKitClient(
                isAvailable: { true },
                requestAuthorization: { true },
                todayMetrics: { throw Boom() },
                saveWalkingWorkout: { _ in },
                dailyMinutes: { _ in [] },
                recentWorkouts: { _ in [] },
                workoutDetail: { summary in
                    WorkoutDetail(summary: summary, heartRateSamples: [], stepsCount: 0)
                }
            )
        } operation: {
            let store = TodayStore()
            await store.refresh()

            // Snapshot is always set so the UI never hangs on the placeholder;
            // failure surfaces via lastError for an in-screen banner.
            #expect(store.snapshot?.steps == 0)
            #expect(store.snapshot?.minutes == 0)
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
                saveWalkingWorkout: { _ in },
                dailyMinutes: { _ in [] },
                recentWorkouts: { _ in [] },
                workoutDetail: { summary in
                    WorkoutDetail(summary: summary, heartRateSamples: [], stepsCount: 0)
                }
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
                saveWalkingWorkout: { _ in },
                dailyMinutes: { _ in [] },
                recentWorkouts: { _ in [] },
                workoutDetail: { summary in
                    WorkoutDetail(summary: summary, heartRateSamples: [], stepsCount: 0)
                }
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

    @Test("Refresh aligns weekMinutes on the current ISO week (Mon → Sun)")
    @MainActor
    func weekMinutesAlignedToCurrentWeek() async {
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2
        let today = calendar.startOfDay(for: .now)
        let weekday = calendar.component(.weekday, from: today)
        let mondayOffset = -((weekday + 5) % 7)
        guard let monday = calendar.date(byAdding: .day, value: mondayOffset, to: today) else {
            Issue.record("could not derive Monday from current week")
            return
        }
        // Synthesise: 10 minutes on Monday, 20 on Tuesday, 30 on Wednesday.
        let crafted: [DailyMinutes] = [
            DailyMinutes(date: monday, minutes: 10),
            DailyMinutes(
                date: calendar.date(byAdding: .day, value: 1, to: monday) ?? monday,
                minutes: 20
            ),
            DailyMinutes(
                date: calendar.date(byAdding: .day, value: 2, to: monday) ?? monday,
                minutes: 30
            )
        ]
        await withDependencies {
            $0.healthKit = HealthKitClient(
                isAvailable: { true },
                requestAuthorization: { true },
                todayMetrics: { .zero },
                saveWalkingWorkout: { _ in },
                dailyMinutes: { _ in crafted },
                recentWorkouts: { _ in [] },
                workoutDetail: { summary in
                    WorkoutDetail(summary: summary, heartRateSamples: [], stepsCount: 0)
                }
            )
        } operation: {
            let store = TodayStore()
            await store.refresh()

            // First three slots match Mon/Tue/Wed; remaining are zero.
            #expect(store.snapshot?.weekMinutes[0] == 10) // Mon
            #expect(store.snapshot?.weekMinutes[1] == 20) // Tue
            #expect(store.snapshot?.weekMinutes[2] == 30) // Wed
            #expect(store.snapshot?.weekMinutes[3] == 0)
            #expect(store.snapshot?.weekMinutes[6] == 0)  // Sun
        }
    }

    @Test("Bootstrap still populates the snapshot when authorization is denied")
    @MainActor
    func bootstrapPopulatesEvenWhenDenied() async {
        await withDependencies {
            $0.healthKit = HealthKitClient(
                isAvailable: { true },
                requestAuthorization: { false },
                todayMetrics: { .zero },
                saveWalkingWorkout: { _ in },
                dailyMinutes: { _ in [] },
                recentWorkouts: { _ in [] },
                workoutDetail: { summary in
                    WorkoutDetail(summary: summary, heartRateSamples: [], stepsCount: 0)
                }
            )
        } operation: {
            let store = TodayStore()
            await store.bootstrap()

            // Auth denied is not a deadlock — UI must render with zeros so
            // the user can navigate to Settings and re-enable HealthKit.
            #expect(store.snapshot?.steps == 0)
            #expect(store.snapshot?.minutes == 0)
        }
    }
}
