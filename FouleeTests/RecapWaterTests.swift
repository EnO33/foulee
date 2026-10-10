import Dependencies
import Foundation
import Testing
@testable import Foulee

/// The water side of the Bilan (issue #356).
@Suite("Recap water")
@MainActor
struct RecapWaterTests {
    private let calendar = Calendar.iso8601Monday
    private struct Refused: Error {}

    private func day(_ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    /// Saturday 10 October: the week is 4 → 10 October, the one before 27
    /// September → 3 October.
    private var saturday: Date { day(10, 10, hour: 18) }

    private var week: RecapPeriod { RecapPeriod.lastDays(endingOn: saturday, calendar: calendar) }

    @Test("A day's mean over the whole period, the days held, and the period before")
    func makesTheWater() {
        let series = [
            MetricPoint(date: day(10, 4), value: 2_000),
            MetricPoint(date: day(10, 6), value: 2_500),
            MetricPoint(date: day(10, 10), value: 1_000),
            MetricPoint(date: day(9, 30), value: 1_400)
        ]
        let water = RecapWater.make(period: week, series: series, goalML: 2_000, calendar: calendar)
        #expect(water.averageML == 786) // 5 500 / 7
        #expect(water.previousAverageML == 200) // 1 400 / 7
        #expect(water.goalDaysMet == 2)
        #expect(water.dayCount == 7)
        #expect(water.goalML == 2_000)
    }

    @Test("No water is a zero mean, not a missing one")
    func emptySeries() {
        let water = RecapWater.make(period: week, series: [], goalML: 2_000, calendar: calendar)
        #expect(water == RecapWater(averageML: 0, previousAverageML: 0, goalDaysMet: 0, dayCount: 7, goalML: 2_000))
    }

    private func client(water: @escaping @Sendable (Int) async throws -> [MetricPoint]) -> HealthKitClient {
        var client = HealthKitClient.testValue
        client.dailyMinutes = { _ in [] }
        client.metricSeries = { _, _ in [] }
        client.recentWorkouts = { _ in [] }
        client.waterSeries = water
        return client
    }

    @Test("With hydration on, both periods come with their water")
    func storeLoadsWater() async {
        let october6 = day(10, 6)
        await withDependencies {
            $0.date = .constant(saturday)
            $0.healthKit = client { _ in [MetricPoint(date: october6, value: 2_100)] }
        } operation: {
            let store = RecapStore()
            await store.load(goalMinutes: 20, activeDays: [], waterGoalML: 2_000)

            #expect(store.water[.week]?.goalDaysMet == 1)
            #expect(store.water[.week]?.averageML == 300)
            #expect(store.water[.month]?.averageML == 0)
        }
    }

    @Test("With hydration off, Santé is not asked for water")
    func storeSkipsWaterWhenOff() async {
        let asked = LockedRef(false)
        await withDependencies {
            $0.date = .constant(saturday)
            $0.healthKit = client { _ in
                asked.set(true)
                return []
            }
        } operation: {
            let store = RecapStore()
            await store.load(goalMinutes: 20, activeDays: [])

            #expect(!asked.value)
            #expect(store.water.isEmpty)
            #expect(store.recaps[.week] != nil)
        }
    }

    @Test("A refused water read leaves the recap standing, without its water")
    func storeSurvivesARefusedWaterRead() async {
        await withDependencies {
            $0.date = .constant(saturday)
            $0.healthKit = client { _ in throw Refused() }
        } operation: {
            let store = RecapStore()
            await store.load(goalMinutes: 20, activeDays: [], waterGoalML: 2_000)

            #expect(store.water.isEmpty)
            #expect(store.recaps[.week] != nil)
            #expect(store.lastError == nil)
        }
    }
}
