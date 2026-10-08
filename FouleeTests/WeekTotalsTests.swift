import Foundation
import Testing
@testable import Foulee

/// The « Semaine » tab's arithmetic (issue #327): which days count, and that
/// a series reaching back past Monday is not counted twice.
@Suite("Week totals")
struct WeekTotalsTests {
    private var calendar: Calendar {
        var calendar = Calendar.iso8601Monday
        calendar.timeZone = .gmt
        return calendar
    }

    /// 2024-05-27 was a Monday.
    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: Date(timeIntervalSince1970: 1_716_768_000)) ?? .now
    }

    @Test("Monday is day one of the week, Sunday day seven", arguments: [(0, 1), (3, 4), (6, 7)])
    func daysSoFar(offset: Int, expected: Int) {
        #expect(WeekTotals.daysSoFar(at: day(offset).addingTimeInterval(15 * 3_600), calendar: calendar) == expected)
    }

    @Test("Only points from Monday on are summed")
    func sumsFromMonday() {
        let points = [-1, 0, 1, 2].map { MetricPoint(date: day($0), value: 1_000) }
        #expect(WeekTotals.sum(points, weekOf: day(2), calendar: calendar) == 3_000)
    }

    @Test("Nothing yet is zero")
    func emptyIsZero() {
        #expect(WeekTotals.sum([], weekOf: day(0), calendar: calendar) == 0)
    }
}
