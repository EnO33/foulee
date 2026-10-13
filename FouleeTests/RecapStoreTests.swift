import Dependencies
import FouleeKit
import Foundation
import Testing
@testable import Foulee

/// Loading the Bilan (issues #344, #350): one read of Santé for both periods
/// and their outings.
@Suite("Recap store")
struct RecapStoreTests {
    private let calendar = Calendar.iso8601Monday
    nonisolated private struct Denied: Error {}

    private var saturday: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 12))!
    }

    /// The month so far is compared with the first days of September (#444):
    /// 40 days back, today included.
    @Test("The read reaches back to the start of the earliest period compared")
    func daysBack() {
        let periods = RecapPeriod.Kind.allCases.map { RecapPeriod.current($0, at: saturday, calendar: calendar) }
        #expect(RecapStore.daysBack(covering: periods, from: saturday, calendar: calendar) == 40)
    }

    /// The earliest month is November 2025, compared with October 2025: the
    /// read starts on 1 October 2025, 375 days back (#444).
    @Test("With the history, the read reaches back twelve months and the month before")
    func daysBackWithHistory() {
        let periods = RecapPeriod.Kind.allCases.flatMap {
            [RecapPeriod.current($0, at: saturday, calendar: calendar), RecapPeriod.earliest($0, at: saturday, calendar: calendar)]
        }
        #expect(RecapStore.daysBack(covering: periods, from: saturday, calendar: calendar) == 375)
    }

    @Test("Both recaps and their outings come from the same read")
    func loadsBoth() async {
        let asked = LockedRef<[Int]>([])
        let thursday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 12))!
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
                    return [DailyMinutes(date: calendar.startOfDay(for: thursday), minutes: 30)]
                },
                recentWorkouts: { _ in [walk] },
                workoutDetail: { WorkoutDetail(summary: $0, heartRateSamples: [], stepsCount: 0) },
                metricSeries: { _, _ in [] }
            )
        } operation: {
            let store = RecapStore()
            await store.load(goalMinutes: 20, activeDays: Set(Weekday.allCases))

            #expect(asked.value == [40])
            // The week so far: Monday 5 → Saturday 10 October (#363).
            let week = store.recaps[.week]
            #expect(week?.days.count == 6)
            #expect(week?.days.first?.date == calendar.date(from: DateComponents(year: 2026, month: 10, day: 5)))
            #expect(week?.days.last?.date == calendar.startOfDay(for: saturday))
            #expect(week?.totals.minutes == 30)
            #expect(week?.goalDaysMet == 1)
            // The month so far, 1 → 10 October (#444), holds Thursday's walk.
            #expect(store.recaps[.month]?.totals.minutes == 30)

            // Outings line up with the recap's days, oldest first.
            let days = store.outings[.week] ?? []
            #expect(days.map(\.day) == week?.days.map(\.date))
            #expect(days[3].workouts == [walk])
            #expect(store.outings[.month]?.count == 10)
            #expect(store.outings[.month]?.flatMap(\.workouts) == [walk])

            // A past period comes from the same read, worked out on demand.
            let september = RecapPeriod.monthSoFar(at: saturday, calendar: calendar).earlier(calendar: calendar)
            #expect(store.content(for: september)?.recap.days.count == 30)
            #expect(store.content(for: september)?.outings.allSatisfy(\.workouts.isEmpty) == true)
            // The card on the home reads no streak.
            #expect(store.streak == nil)
            #expect(store.lastError == nil)
            #expect(!store.isLoading)
        }
    }

    /// The record is the home's only if both read the same history (#176):
    /// the screen reads `StreakCalculator.historyWindowDays`, deeper than the
    /// 375 days its periods need (#445).
    @Test("With the history, the streak comes from the home's window")
    func streakWithHistory() async {
        let asked = LockedRef<[Int]>([])
        let today = calendar.startOfDay(for: saturday)
        let walked = (0..<3).map { DailyMinutes(date: calendar.date(byAdding: .day, value: -$0, to: today)!, minutes: 30) }
        await withDependencies {
            $0.date = .constant(saturday)
            $0.healthKit = HealthKitClient(
                requestAuthorization: { true },
                todayMetrics: { .zero },
                saveWorkout: { _ in },
                dailyMinutes: { daysBack in
                    asked.set(asked.value + [daysBack])
                    return walked
                },
                recentWorkouts: { _ in [] },
                workoutDetail: { WorkoutDetail(summary: $0, heartRateSamples: [], stepsCount: 0) },
                metricSeries: { _, _ in [] }
            )
        } operation: {
            let store = RecapStore()
            await store.load(goalMinutes: 20, activeDays: Set(Weekday.allCases), withHistory: true)

            #expect(asked.value == [StreakCalculator.historyWindowDays])
            #expect(store.streak?.current == 3)
            #expect(store.streak?.best == 3)
            #expect(store.streak?.walks == 3)
            #expect(store.streak?.minutes == 90)
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
