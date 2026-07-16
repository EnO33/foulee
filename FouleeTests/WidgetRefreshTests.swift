import Foundation
import Testing
@testable import Foulee

@Suite struct WidgetRefreshTests {
    /// Fixed UTC calendar so the hour math is deterministic on any machine.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: hour, minute: minute))!
    }

    @Test func daytimeRoundsUpToNextTenMinuteSlot() {
        #expect(WidgetRefresh.nextRefresh(after: date(8, 3), calendar: calendar) == date(8, 10))
        #expect(WidgetRefresh.nextRefresh(after: date(8, 17), calendar: calendar) == date(8, 20))
        #expect(WidgetRefresh.nextRefresh(after: date(14, 0), calendar: calendar) == date(14, 10))
    }

    @Test func slotAtFiftyFiveRollsIntoNextHour() {
        #expect(WidgetRefresh.nextRefresh(after: date(9, 55), calendar: calendar) == date(10, 0))
    }

    @Test func beforeWindowWakesAtEight() {
        #expect(WidgetRefresh.nextRefresh(after: date(6, 30), calendar: calendar) == date(8, 0))
        #expect(WidgetRefresh.nextRefresh(after: date(0, 5), calendar: calendar) == date(8, 0))
    }

    @Test func afterWindowWakesAtNextEight() {
        // 20:00 is the edge — already outside the active window.
        #expect(WidgetRefresh.nextRefresh(after: date(20, 0), calendar: calendar) == date(8, 0).addingTimeInterval(24 * 3_600))
        #expect(WidgetRefresh.nextRefresh(after: date(23, 30), calendar: calendar) == date(8, 0).addingTimeInterval(24 * 3_600))
    }

    @Test func lastDaytimeSlotIsStillRequested() {
        // 19:52 -> 20:00; the next call (at 20:00) defers to tomorrow 08:00.
        #expect(WidgetRefresh.nextRefresh(after: date(19, 52), calendar: calendar) == date(20, 0))
    }

    @Test func midnightEntryLandsAtNextLocalMidnight() {
        // A timeline built at 23:50 dates its zeroed reset entry at 00:00.
        #expect(WidgetRefresh.nextMidnight(after: date(23, 50), calendar: calendar)
            == date(0, 0).addingTimeInterval(24 * 3_600))
        #expect(WidgetRefresh.nextMidnight(after: date(0, 5), calendar: calendar)
            == date(0, 0).addingTimeInterval(24 * 3_600))
    }

    @Test func midnightEntryIsStrictlyAfterAnExactMidnightBuild() {
        // Built exactly at 00:00, the reset must target the FOLLOWING
        // midnight — a same-instant entry would zero the fresh day itself.
        #expect(WidgetRefresh.nextMidnight(after: date(0, 0), calendar: calendar)
            == date(0, 0).addingTimeInterval(24 * 3_600))
    }
}
