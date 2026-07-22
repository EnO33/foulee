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

@Suite("TodayStore streak history window")
struct TodayStoreStreakWindowTests {
    @Test("Refresh fetches the shared streak history window, not 30 days")
    @MainActor
    func refreshFetchesFullHistoryWindow() async {
        let captured = LockedRef(0)
        await withDependencies {
            $0.healthKit.dailyMinutes = { daysBack in
                captured.set(daysBack)
                return []
            }
        } operation: {
            let store = TodayStore()
            await store.refresh()

            #expect(captured.value == StreakCalculator.historyWindowDays)
        }
    }

    @Test("A record older than 30 days shows on the home card (device report: 23 vs 12)")
    @MainActor
    func recordOlderThanThirtyDaysShowsOnHomeCard() async throws {
        // 23-day run ending ~40 days ago, then a fresh 12-day run up to today.
        var minutesByOffset: [Int: Int] = [:]
        for offset in 40...62 { minutesByOffset[offset] = 25 }
        for offset in 0...11 { minutesByOffset[offset] = 25 }
        let crafted = history(minutesByOffset: minutesByOffset)
        try await withDependencies {
            $0.healthKit.dailyMinutes = Self.windowed(crafted)
        } operation: {
            let store = try makeEveryDayStore()
            await store.refresh()

            #expect(store.snapshot?.bestStreak == 23)
            #expect(store.snapshot?.streak == 12)
        }
    }

    @Test("A current streak longer than 30 days isn't capped")
    @MainActor
    func longCurrentStreakNotCapped() async throws {
        let crafted = history(
            minutesByOffset: Dictionary(uniqueKeysWithValues: (0...34).map { ($0, 25) })
        )
        try await withDependencies {
            $0.healthKit.dailyMinutes = Self.windowed(crafted)
        } operation: {
            let store = try makeEveryDayStore()
            await store.refresh()

            #expect(store.snapshot?.streak == 35)
            #expect(store.snapshot?.bestStreak == 35)
        }
    }

    @Test("A year of history doesn't disturb the current week's bars")
    @MainActor
    func weekBarsUnaffectedByDeepHistory() async {
        let calendar = Calendar.iso8601Monday
        let today = calendar.startOfDay(for: .now)
        let week = ISOWeek.days(containing: .now, calendar: calendar)
        // A year of 25-minute days, with distinct values on this week's
        // elapsed days so a misaligned lookup would be caught.
        var byDay: [Date: Int] = [:]
        for offset in 0..<StreakCalculator.historyWindowDays {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            byDay[day] = 25
        }
        for (index, day) in week.enumerated() where day <= today {
            byDay[day] = (index + 1) * 10
        }
        let crafted = byDay.map { DailyMinutes(date: $0.key, minutes: $0.value) }
        let expected = week.enumerated().map { index, day in day <= today ? (index + 1) * 10 : 0 }
        await withDependencies {
            $0.healthKit.dailyMinutes = { _ in crafted }
        } operation: {
            let store = TodayStore()
            await store.refresh()

            #expect(store.snapshot?.weekMinutes == expected)
        }
    }

    /// Store with every weekday active, so streak counts don't depend on
    /// which day of the week the test happens to run.
    @MainActor
    private func makeEveryDayStore() throws -> TodayStore {
        let store = TodayStore()
        let suiteName = "TodayStoreStreakWindowTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = UserPreferences(defaults: defaults)
        preferences.activeDays = Set(Weekday.allCases)
        store.apply(preferences: preferences)
        return store
    }

    /// Stub that honors `daysBack` like the real query would — so a
    /// regression to a shallow fetch makes the scenario tests fail exactly
    /// the way the device did (bestStreak 12 instead of 23), instead of the
    /// stub feeding the full crafted history regardless of the window.
    private static func windowed(_ crafted: [DailyMinutes]) -> @Sendable (Int) async throws -> [DailyMinutes] {
        { daysBack in
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)
            guard let cutoff = calendar.date(byAdding: .day, value: -(daysBack - 1), to: today) else {
                return crafted
            }
            return crafted.filter { $0.date >= cutoff }
        }
    }

    /// `[daysAgo: minutes]` → history entries anchored on today. Absent
    /// offsets read as 0 minutes downstream, i.e. a missed day.
    private func history(minutesByOffset: [Int: Int]) -> [DailyMinutes] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return minutesByOffset.compactMap { offset, minutes in
            calendar.date(byAdding: .day, value: -offset, to: today)
                .map { DailyMinutes(date: $0, minutes: minutes) }
        }
    }
}

@Suite("TodayStore optimistic walk overlay")
struct TodayStoreWalkOverlayTests {
    @Test("A finished walk overlays its steps + distance, then reconciles to HealthKit")
    @MainActor
    func optimisticWalkOverlayReconciles() async {
        // HealthKit lags behind the walk: it keeps reporting the pre-walk totals
        // until iOS flushes the walk, then jumps past them.
        let hkSteps = LockedRef(3_000)
        await withDependencies {
            $0.date = .constant(.now)
            $0.healthKit = HealthKitClient(
                requestAuthorization: { true },
                todayMetrics: {
                    HealthMetrics(
                        steps: hkSteps.value,
                        distanceKm: 2.0,
                        activeMinutes: 5,
                        activeCalories: 30
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
            #expect(store.snapshot?.steps == 3_000)

            // Walk 1 200 steps / 1 km while HealthKit still reports 3 000.
            store.walkWillStart()
            var session = WalkSession(startedAt: .now)
            session.steps = 1_200
            session.distanceMeters = 1_000
            await store.registerFinishedWalk(session)

            // Shown immediately, on top of the captured baseline.
            #expect(store.snapshot?.steps == 4_200)
            #expect(store.snapshot?.distanceKm == 3.0)

            // iOS flushes the walk (plus a few extra steps): the overlay
            // dissolves and we show real data — never double-counted.
            hkSteps.set(4_500)
            await store.refresh()
            #expect(store.snapshot?.steps == 4_500)
            #expect(store.snapshot?.distanceKm == 2.0)
        }
    }
}

@Suite("TodayStore weather isolation")
struct TodayStoreWeatherTests {
    @Test("A WeatherKit failure doesn't raise the Health-data error banner")
    @MainActor
    func weatherFailureDoesNotSetLastError() async {
        struct WeatherDown: Error {}
        await withDependencies {
            $0.healthKit = HealthKitClient(
                requestAuthorization: { true },
                todayMetrics: {
                    HealthMetrics(steps: 5_000, distanceKm: 3, activeMinutes: 25, activeCalories: 120)
                },
                saveWalkingWorkout: { _ in },
                dailyMinutes: { _ in [] },
                recentWorkouts: { _ in [] },
                workoutDetail: { summary in
                    WorkoutDetail(summary: summary, heartRateSamples: [], stepsCount: 0)
                }
            )
            $0.location = .previewValue
            $0.weather = WeatherClient(middayForecast: { _ in throw WeatherDown() })
        } operation: {
            let store = TodayStore()
            await store.refresh()

            // Metrics loaded fine and only weather failed — the user must NOT be
            // told to check their Santé permissions.
            #expect(store.snapshot != nil)
            #expect(store.lastError == nil)
        }
    }
}
