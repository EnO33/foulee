import Foundation
import Testing
@testable import FouleeKit

@Suite("StreakSummary")
struct StreakSummaryTests {
    private let calendar = Calendar.iso8601Monday
    private let today = Date(timeIntervalSince1970: 1_716_940_800) // 2024-05-29, Wednesday

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func make(_ history: [DailyMinutes], activeDays: Set<Weekday> = Weekday.workWeek) -> StreakSummary {
        StreakSummary.make(history: history, goalMinutes: 20, activeDays: activeDays, today: today, calendar: calendar)
    }

    @Test("The year is the Bilan's twelve months: from 1 June 2023 through today")
    func yearBounds() {
        let summary = make([
            DailyMinutes(date: day(2023, 5, 31), minutes: 40), // Wed, the month before
            DailyMinutes(date: day(2023, 6, 1), minutes: 25),  // Thu, the first day counted
            DailyMinutes(date: day(2024, 5, 29), minutes: 30), // Wed, today
        ])
        #expect(summary.walks == 2)
        #expect(summary.minutes == 55)
    }

    @Test("Walks and rate count active days only; minutes count every day")
    func activeDaysOnly() {
        let summary = make([
            DailyMinutes(date: day(2024, 5, 27), minutes: 25), // Mon, met
            DailyMinutes(date: day(2024, 5, 28), minutes: 10), // Tue, unmet
            DailyMinutes(date: day(2024, 5, 25), minutes: 60), // Sat, rest
        ], activeDays: [.monday, .tuesday])
        #expect(summary.walks == 1)
        #expect(summary.minutes == 95)
        // 1 met out of the 104 Mondays and Tuesdays of the year: 1 %.
        #expect(summary.rate == 1)
    }

    @Test("Weekdays: per-day rate, Monday first, rest days flagged")
    func weekdayBreakdown() {
        // Every Monday of the year met the goal; nothing else logged.
        var mondays: [DailyMinutes] = []
        var date = day(2023, 6, 5)
        while date <= today {
            mondays.append(DailyMinutes(date: date, minutes: 25))
            date = calendar.date(byAdding: .day, value: 7, to: date)!
        }
        let stats = make(mondays).weekdays
        func stat(_ day: Weekday) -> WeekdayStat { stats.first { $0.weekday == day }! }
        #expect(stats.map(\.weekday) == Weekday.allCases)
        #expect(stat(.monday).rate == 100)
        #expect(stat(.tuesday).rate == 0)
        #expect(stat(.tuesday).isActive)
        #expect(stat(.saturday).isActive == false)
    }

    @Test("The streak and the record are StreakCalculator's")
    func streakAndRecord() {
        // Mon 27, Tue 28 and today: a running streak of three, the record.
        let summary = make([27, 28, 29].map { DailyMinutes(date: day(2024, 5, $0), minutes: 25) })
        #expect(summary.current == 3)
        #expect(summary.best == 3)
    }

    @Test("Toward the record: days left and progress")
    func recordProgress() {
        let behind = StreakSummary(current: 3, best: 12, walks: 0, minutes: 0, rate: 0, weekdays: [])
        #expect(behind.daysToRecord == 9)
        #expect(behind.recordProgress == 0.25)

        let level = StreakSummary(current: 12, best: 12, walks: 0, minutes: 0, rate: 0, weekdays: [])
        #expect(level.daysToRecord == nil)
        #expect(level.recordProgress == 1)

        let first = StreakSummary(current: 0, best: 0, walks: 0, minutes: 0, rate: 0, weekdays: [])
        #expect(first.daysToRecord == nil)
        #expect(first.recordProgress == 0)
    }
}
