import Dependencies
import Foundation
import Testing
@testable import Foulee

@Suite("MetricStatsStore")
struct MetricStatsStoreTests {
    private func points(_ values: [Double]) -> [MetricPoint] {
        values.enumerated().map { index, value in
            MetricPoint(
                date: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 86_400),
                value: value
            )
        }
    }

    @Test("Week range loads the daily series and derives total / average / best")
    @MainActor
    func weekSummary() async {
        let series = points([10, 0, 20, 30])
        await withDependencies {
            $0.healthKit.metricSeries = { _, _ in series }
        } operation: {
            let store = MetricStatsStore(metric: .minutes)
            store.range = .week
            await store.load()

            #expect(store.total == 60)
            #expect(store.best == 30)
            #expect(store.average == 20) // 60 over 3 non-empty buckets
            #expect(store.isEmpty == false)
        }
    }

    @Test("Empty series → isEmpty with a zeroed summary")
    @MainActor
    func emptySummary() async {
        await withDependencies {
            $0.healthKit.metricSeries = { _, _ in [] }
        } operation: {
            let store = MetricStatsStore(metric: .steps)
            store.range = .month
            await store.load()

            #expect(store.isEmpty)
            #expect(store.total == 0)
            #expect(store.average == 0)
            #expect(store.best == 0)
        }
    }

    @Test("Today range pulls the hourly series, not the daily one")
    @MainActor
    func todayUsesHourly() async {
        await withDependencies {
            $0.healthKit.hourlyToday = { _ in self.points([2, 3]) }
            $0.healthKit.metricSeries = { _, _ in self.points([999]) }
        } operation: {
            let store = MetricStatsStore(metric: .steps)
            store.range = .today
            await store.load()

            #expect(store.total == 5)
        }
    }
}
