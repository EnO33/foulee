import Dependencies
import Foundation
import Testing
@testable import Foulee

/// Loading the Bilan (issues #344, #350): one read of Santé for both periods
/// and their outings.
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
        let periods = RecapPeriod.Kind.allCases.map { RecapPeriod.current($0, at: saturday, calendar: calendar) }
        #expect(RecapStore.daysBack(covering: periods, from: saturday, calendar: calendar) == 71)
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

            #expect(asked.value == [71])
            // The week so far: Monday 5 → Saturday 10 October (#363).
            let week = store.recaps[.week]
            #expect(week?.days.count == 6)
            #expect(week?.days.first?.date == calendar.date(from: DateComponents(year: 2026, month: 10, day: 5)))
            #expect(week?.days.last?.date == calendar.startOfDay(for: saturday))
            #expect(week?.totals.minutes == 30)
            #expect(week?.goalDaysMet == 1)
            #expect(store.recaps[.month]?.totals.minutes == 0)

            // Outings line up with the recap's days, oldest first.
            let days = store.outings[.week] ?? []
            #expect(days.map(\.day) == week?.days.map(\.date))
            #expect(days[3].workouts == [walk])
            #expect(store.outings[.month]?.count == 30)
            #expect(store.outings[.month]?.allSatisfy(\.workouts.isEmpty) == true)
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
