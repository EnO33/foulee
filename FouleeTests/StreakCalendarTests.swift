import Foundation
import Testing
@testable import Foulee

@Suite("StreakCalendar")
struct StreakCalendarTests {
    private let calendar = Calendar.iso8601Monday
    private let today = Date(timeIntervalSince1970: 1_716_940_800) // 2024-05-29, Wednesday

    @Test("Returns `count` months, oldest first, current month last")
    func monthCountAndOrder() {
        let months = StreakCalendar.months(
            history: [], goalMinutes: 20, activeDays: Weekday.workWeek,
            today: today, count: 3, calendar: calendar
        )
        #expect(months.count == 3)
        #expect(months[0].monthStart < months[1].monthStart) // oldest first
        let last = calendar.dateComponents([.year, .month, .day], from: months[2].monthStart)
        #expect(last.year == 2024 && last.month == 5 && last.day == 1) // current month last
    }

    @Test("Cells are weekday-aligned with leading blanks and padded to 6 rows")
    func gridAlignment() {
        let may = StreakCalendar.months(
            history: [], goalMinutes: 20, activeDays: Weekday.workWeek,
            today: today, count: 1, calendar: calendar
        )[0]
        #expect(may.cells.count == 42) // 6 rows × 7, stable height
        // 1 May 2024 is a Wednesday → two leading blanks (Mon, Tue).
        #expect(may.cells[0] == nil)
        #expect(may.cells[1] == nil)
        #expect(calendar.component(.day, from: may.cells[2]!.date) == 1)
        #expect(calendar.component(.weekday, from: may.cells[2]!.date) == 4) // Wednesday
        #expect(may.cells[41] == nil) // trailing padding
    }

    @Test("Day status: done when met, missed when active+unmet, rest on weekend, future after today")
    func dayStatus() {
        let firstMay = calendar.date(from: DateComponents(year: 2024, month: 5, day: 1))!
        let history = [DailyMinutes(date: firstMay, minutes: 25)]
        let cells = StreakCalendar.months(
            history: history, goalMinutes: 20, activeDays: Weekday.workWeek,
            today: today, count: 1, calendar: calendar
        )[0].cells.compactMap { $0 }
        func day(_ dayOfMonth: Int) -> CalendarDay {
            cells.first { calendar.component(.day, from: $0.date) == dayOfMonth }!
        }
        #expect(day(1).status == .done)    // Wed 1 May, 25 ≥ 20
        #expect(day(2).status == .missed)  // Thu 2 May, active, no data, past
        #expect(day(4).status == .rest)    // Sat 4 May, weekend
        #expect(day(30).status == .future) // Thu 30 May, after the 29th
    }

    @Test("Month stats: rate, walks and minutes over the month")
    func monthStats() {
        let firstMay = calendar.date(from: DateComponents(year: 2024, month: 5, day: 1))!  // Wed, met
        let secondMay = calendar.date(from: DateComponents(year: 2024, month: 5, day: 2))! // Thu, unmet
        let history = [DailyMinutes(date: firstMay, minutes: 25), DailyMinutes(date: secondMay, minutes: 10)]
        let month = StreakCalendar.months(
            history: history, goalMinutes: 20, activeDays: Weekday.workWeek,
            today: today, count: 1, calendar: calendar
        )[0]
        #expect(month.walks == 1)    // only 1 May met the goal
        #expect(month.minutes == 35) // 25 + 10
        #expect((0...100).contains(month.rate))
    }

    @Test("Weekday stats: per-day rate, Monday-first order, rest flag")
    func weekdayBreakdown() {
        // Every Monday of May 2024 met the goal; nothing else logged.
        let mondays = [6, 13, 20, 27].map { calendar.date(from: DateComponents(year: 2024, month: 5, day: $0))! }
        let history = mondays.map { DailyMinutes(date: $0, minutes: 25) }
        let months = StreakCalendar.months(
            history: history, goalMinutes: 20, activeDays: Weekday.workWeek,
            today: today, count: 1, calendar: calendar
        )
        let stats = StreakCalendar.weekdayStats(months: months, activeDays: Weekday.workWeek, calendar: calendar)
        func stat(_ day: Weekday) -> WeekdayStat { stats.first { $0.weekday == day }! }
        #expect(stats.count == 7)
        #expect(stats[0].weekday == .monday)       // Monday-first
        #expect(stat(.monday).rate == 100)         // 4 met, 0 missed
        #expect(stat(.monday).isActive)
        #expect(stat(.tuesday).rate == 0)          // active, none met
        #expect(stat(.tuesday).isActive)
        #expect(stat(.saturday).isActive == false) // rest day
    }
}
