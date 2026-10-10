import Dependencies
import Foundation
import Testing
@testable import Foulee

/// Loading the recaps (issue #344): one read of Santé for both periods.
@Suite("Recap store")
@MainActor
struct RecapStoreTests {
    private let calendar = Calendar.iso8601Monday
    private struct Denied: Error {}

    private var saturday: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 12))!
    }

    /// The month before last starts on 1 August: 71 days back, today included.
    @Test("The read reaches back to the start of the earliest period compared")
    func daysBack() {
        let periods = RecapPeriod.Kind.allCases.map { RecapPeriod.lastCompleted($0, before: saturday, calendar: calendar) }
        #expect(RecapStore.daysBack(covering: periods, from: saturday, calendar: calendar) == 71)
    }

    @Test("Both recaps come from the same read")
    func loadsBoth() async {
        let asked = LockedRef<[Int]>([])
        let october1 = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        await withDependencies {
            $0.date = .constant(saturday)
            $0.healthKit = HealthKitClient(
                requestAuthorization: { true },
                todayMetrics: { .zero },
                saveWorkout: { _ in },
                dailyMinutes: { daysBack in
                    asked.set(asked.value + [daysBack])
                    return [DailyMinutes(date: october1, minutes: 30)]
                },
                recentWorkouts: { _ in [] },
                workoutDetail: { WorkoutDetail(summary: $0, heartRateSamples: [], stepsCount: 0) },
                metricSeries: { _, _ in [] }
            )
        } operation: {
            let store = RecapStore()
            await store.load(goalMinutes: 20, activeDays: Set(Weekday.allCases))

            #expect(asked.value == [71])
            #expect(store.recaps[.week]?.totals.minutes == 30)
            #expect(store.recaps[.month]?.totals.minutes == 0)
            #expect(store.lastError == nil)
            #expect(!store.isLoading)
        }
    }

    @Test("A refused read is said, not shown as an empty recap")
    func refusedRead() async {
        await withDependencies {
            $0.date = .constant(saturday)
            $0.healthKit = HealthKitClient(
                requestAuthorization: { true },
                todayMetrics: { .zero },
                saveWorkout: { _ in },
                dailyMinutes: { _ in throw Denied() },
                recentWorkouts: { _ in [] },
                workoutDetail: { WorkoutDetail(summary: $0, heartRateSamples: [], stepsCount: 0) }
            )
        } operation: {
            let store = RecapStore()
            await store.load(goalMinutes: 20, activeDays: [])
            #expect(store.recaps.isEmpty)
            #expect(store.lastError != nil)
        }
    }
}

/// The « 7 derniers jours » view (issue #348).
@Suite("Recent activity store")
@MainActor
struct RecentActivityStoreTests {
    private let calendar = Calendar.iso8601Monday

    @Test("The last seven days come with the seven before, and their outings day by day")
    func loadsTheLastSevenDays() async {
        let saturday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 18))!
        let thursday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 12))!
        let asked = LockedRef<[Int]>([])
        let walk = WorkoutSummary(
            id: UUID(),
            startedAt: thursday,
            endedAt: thursday.addingTimeInterval(1_800),
            durationSeconds: 1_800,
            distanceKm: 2.4,
            activeCalories: 120,
            sourceName: "Foulée",
            activity: .walking
        )
        await withDependencies {
            $0.date = .constant(saturday)
            $0.healthKit = HealthKitClient(
                requestAuthorization: { true },
                todayMetrics: { .zero },
                saveWorkout: { _ in },
                dailyMinutes: { daysBack in
                    asked.set(asked.value + [daysBack])
                    return [DailyMinutes(date: Calendar.iso8601Monday.startOfDay(for: thursday), minutes: 30)]
                },
                recentWorkouts: { _ in [walk] },
                workoutDetail: { WorkoutDetail(summary: $0, heartRateSamples: [], stepsCount: 0) },
                metricSeries: { _, _ in [] }
            )
        } operation: {
            let store = RecentActivityStore()
            await store.load(goalMinutes: 20, activeDays: Set(Weekday.allCases))

            #expect(asked.value == [14])
            #expect(store.recap?.days.count == 7)
            #expect(store.recap?.days.last?.date == calendar.startOfDay(for: saturday))
            #expect(store.recap?.totals.minutes == 30)
            #expect(store.recap?.goalDaysMet == 1)
            #expect(store.days.count == 7)
            #expect(store.days.first?.day == Calendar.current.startOfDay(for: saturday))
            #expect(store.days[2].workouts == [walk])
            #expect(store.lastError == nil)
        }
    }
}
