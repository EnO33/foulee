import Foundation
import Testing
@testable import Foulee

@Suite("StreakCalendar")
struct StreakCalendarTests {
    private let calendar = Calendar.iso8601Monday
    private let today = Date(timeIntervalSince1970: 1_716_940_800) // 2024-05-29, Wednesday

    @Test("Grid is weeks×7 days, Monday-aligned, oldest first")
    func gridShape() {
        let days = StreakCalendar.build(
            history: [], goalMinutes: 20, activeDays: Weekday.workWeek,
            today: today, weeks: 4, calendar: calendar
        )
        #expect(days.count == 28)
        #expect(calendar.component(.weekday, from: days[0].date) == 2) // Monday
    }

    @Test("Past active days with no data are missed; tomorrow is future")
    func missedAndFuture() {
        let days = StreakCalendar.build(
            history: [], goalMinutes: 20, activeDays: Weekday.workWeek,
            today: today, weeks: 1, calendar: calendar
        )
        // Week Mon 27 May → Sun 2 Jun; today is Wed 29.
        #expect(days[0].status == .missed) // Mon, past active, no data
        #expect(days[2].status == .missed) // Wed = today, active, no data
        #expect(days[3].status == .future) // Thu, hasn't happened
    }

    @Test("A met active day is done; a past weekend is rest")
    func doneAndRest() {
        let monday = Date(timeIntervalSince1970: 1_716_768_000) // 2024-05-27, Monday
        let history = [DailyMinutes(date: monday, minutes: 25)]
        let days = StreakCalendar.build(
            history: history, goalMinutes: 20, activeDays: Weekday.workWeek,
            today: today, weeks: 2, calendar: calendar
        )
        // days[0…6] = previous week (20–26 May), days[7…13] = this week (27 May–2 Jun)
        #expect(days[7].status == .done) // Mon 27 May, 25 ≥ 20
        #expect(days[5].status == .rest) // Sat 25 May, past weekend
    }
}
