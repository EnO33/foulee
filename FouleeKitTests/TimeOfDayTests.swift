import Foundation
import Testing
@testable import FouleeKit

@Suite("TimeOfDay")
struct TimeOfDayTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    @Test("Raw minutes round-trip, and past midnight wrap into the day")
    func rawMinutes() {
        #expect(TimeOfDay(rawMinutes: 9 * 60 + 5) == TimeOfDay(hour: 9, minute: 5))
        #expect(TimeOfDay(hour: 9, minute: 5).rawMinutes == 545)
        #expect(TimeOfDay(rawMinutes: 25 * 60) == TimeOfDay(hour: 1, minute: 0))
    }

    @Test("« 09:05 », zero-padded")
    func clockText() {
        #expect(TimeOfDay(hour: 9, minute: 5).clockText == "09:05")
        #expect(TimeOfDay(hour: 23, minute: 59).clockText == "23:59")
    }

    @Test("An end far enough after the start is kept")
    func validEndKeepsAValidEnd() {
        let start = TimeOfDay(hour: 9, minute: 0)
        let end = TimeOfDay(hour: 9, minute: TimeOfDay.minimumWindowMinutes)
        #expect(TimeOfDay.validEnd(end, after: start) == end)
    }

    @Test("An end too close to the start moves to an hour after it")
    func validEndMovesAnEndTooClose() {
        let start = TimeOfDay(hour: 9, minute: 0)
        #expect(TimeOfDay.validEnd(TimeOfDay(hour: 9, minute: 2), after: start) == TimeOfDay(hour: 10, minute: 0))
        #expect(TimeOfDay.validEnd(TimeOfDay(hour: 8, minute: 0), after: start) == TimeOfDay(hour: 10, minute: 0))
    }

    @Test("The moved end never passes 23:59")
    func validEndStaysWithinTheDay() {
        let start = TimeOfDay(hour: 23, minute: 30)
        #expect(TimeOfDay.validEnd(TimeOfDay(hour: 23, minute: 31), after: start) == TimeOfDay(hour: 23, minute: 59))
    }

    @Test("Read from a date, and placed back on a given day")
    func dates() throws {
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 8, minute: 15)))
        let noon = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 12, minute: 30)))
        #expect(TimeOfDay(date: noon, calendar: calendar) == TimeOfDay(hour: 12, minute: 30))
        #expect(TimeOfDay(hour: 12, minute: 30).dateToday(calendar: calendar, now: now) == noon)
    }
}
