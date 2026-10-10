import Dependencies
import Foundation
import Testing
@testable import Foulee

/// The Hydratation screen (issue #355): its week, its quick amounts, its store.
@Suite("Hydration detail")
struct HydrationDetailTests {
    /// ISO, Monday first, pinned to GMT.
    private var calendar: Calendar {
        var calendar = Calendar.iso8601Monday
        calendar.timeZone = .gmt
        return calendar
    }

    private var saturday: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 15))!
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: saturday))!
    }

    // MARK: - Week

    @Test("The week so far, Monday first and zero-filled, with Sunday still to come")
    func weekIsZeroFilled() {
        let history = HydrationHistory.make(
            series: [MetricPoint(date: day(0), value: 1_250), MetricPoint(date: day(2), value: 2_000)],
            goalML: 2_000,
            now: saturday,
            calendar: calendar
        )
        // Saturday 10 October: Monday 5 → Saturday 10, and Sunday 11 to come.
        #expect(history.days.map(\.date) == (0..<6).reversed().map { day($0) })
        #expect(history.days.map(\.milliliters) == [0, 0, 0, 2_000, 0, 1_250])
        #expect(history.daysToCome == [calendar.date(byAdding: .day, value: 1, to: day(0))!])
    }

    @Test("The goal held and the mean")
    func goalDaysAndAverage() {
        let history = HydrationHistory(
            days: [2_000, 2_500, 1_000, 0, 1_999, 2_000, 500].enumerated().map {
                HydrationHistory.Day(date: day(6 - $0.offset), milliliters: $0.element)
            },
            goalML: 2_000
        )
        #expect(history.goalDaysMet == 3)
        #expect(history.averageML == 1_428)
    }

    // MARK: - Quick amounts

    @Test("Small, set, large, bottle — around a 250 mL glass")
    func presetsAroundTheGlass() {
        let presets = HydrationServing.presets(glassML: 250)
        #expect(presets.map(\.label) == ["Petit verre", "Verre", "Grand verre", "Bouteille"])
        #expect(presets.map(\.milliliters) == [150, 250, 400, 500])
    }

    @Test("A large glass past the bottle makes the bottle bigger")
    func bottleStaysTheLargest() {
        let amounts = HydrationServing.presets(glassML: 400).map(\.milliliters)
        #expect(amounts == [240, 400, 640, 960])
        #expect(amounts == amounts.sorted())
    }

    // MARK: - Store

    @Test("Today's glasses come newest first")
    @MainActor
    func samplesNewestFirst() async {
        let morning = WaterSample(id: UUID(), date: day(0).addingTimeInterval(8 * 3_600), milliliters: 250, sourceName: "Foulée")
        let noon = WaterSample(id: UUID(), date: day(0).addingTimeInterval(12 * 3_600), milliliters: 500, sourceName: "Apple Watch")
        await withDependencies {
            var client = HealthKitClient.testValue
            client.waterToday = { [morning, noon] }
            $0.healthKit = client
        } operation: {
            let store = HydrationDetailStore()
            await store.load(goalML: 2_000)

            #expect(store.samples == [noon, morning])
        }
    }

    @Test("The screen reads today's glasses and the week in one go")
    @MainActor
    func storeLoads() async {
        let glass = WaterSample(id: UUID(), date: saturday, milliliters: 250, sourceName: "Foulée")
        let asked = LockedRef<[Int]>([])
        let now = saturday
        let today = day(0)
        await withDependencies {
            $0.date = .constant(now)
            var client = HealthKitClient.testValue
            client.waterToday = { [glass] }
            client.waterSeries = { daysBack in
                asked.set(asked.value + [daysBack])
                return [MetricPoint(date: today, value: 250)]
            }
            $0.healthKit = client
        } operation: {
            let store = HydrationDetailStore()
            await store.load(goalML: 2_000)

            #expect(store.samples == [glass])
            #expect(asked.value == [7])
            // The whole week is drawn: the days lived and those still to come.
            let lived = store.history?.days.count ?? 0
            let toCome = store.history?.daysToCome.count ?? 0
            #expect(lived + toCome == 7)
            #expect(store.lastError == nil)
        }
    }

    @Test("A refused read is said, not shown as an empty week")
    @MainActor
    func storeFailure() async {
        struct Refused: Error {}
        await withDependencies {
            var client = HealthKitClient.testValue
            client.waterToday = { throw Refused() }
            $0.healthKit = client
        } operation: {
            let store = HydrationDetailStore()
            await store.load(goalML: 2_000)

            #expect(store.history == nil)
            #expect(store.lastError != nil)
        }
    }
}
