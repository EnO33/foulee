import Foundation
import Testing
@testable import Foulee

@Suite("WalkFormatting")
struct WalkFormattingTests {
    @Test("Under an hour reads as mm:ss")
    func clockUnderHour() {
        #expect(TimeInterval(0).walkClockText == "00:00")
        #expect(TimeInterval(65).walkClockText == "01:05")
        #expect(TimeInterval(20 * 60 + 9).walkClockText == "20:09")
    }

    @Test("Past the hour promotes to h:mm:ss")
    func clockOverHour() {
        #expect(TimeInterval(3_600).walkClockText == "1:00:00")
        #expect(TimeInterval(3_661).walkClockText == "1:01:01")
        #expect(TimeInterval(75 * 60 + 30).walkClockText == "1:15:30")
    }

    @Test("km value uses a French decimal comma and no unit")
    func kmValue() {
        #expect(1.234.kmValue() == "1,23")
        #expect(0.0.kmValue() == "0,00")
        #expect(1.27.kmValue(fractionDigits: 1) == "1,3")
        #expect(1.24.kmValue(fractionDigits: 1) == "1,2")
    }

    @Test("km text appends the unit")
    func kmText() {
        #expect(1.234.kmText() == "1,23 km")
        #expect(3.0.kmText(fractionDigits: 1) == "3,0 km")
    }
}

@Suite("ISOWeek")
struct ISOWeekTests {
    private let calendar = Calendar.iso8601Monday

    @Test("Returns seven consecutive days starting on Monday")
    func sevenDaysFromMonday() {
        // 2024-05-29 is a Wednesday.
        let wednesday = Date(timeIntervalSince1970: 1_716_940_800)
        let days = ISOWeek.days(containing: wednesday, calendar: calendar)
        #expect(days.count == 7)
        #expect(calendar.component(.weekday, from: days[0]) == 2) // Monday
        #expect(calendar.component(.weekday, from: days[6]) == 1) // Sunday
        for index in 1..<days.count {
            let gap = calendar.dateComponents([.day], from: days[index - 1], to: days[index]).day
            #expect(gap == 1)
        }
    }

    @Test("A Monday reference is itself the first day of the week")
    func mondayIsFirst() {
        // 2024-05-27 is a Monday.
        let monday = Date(timeIntervalSince1970: 1_716_768_000)
        let days = ISOWeek.days(containing: monday, calendar: calendar)
        #expect(calendar.isDate(days[0], inSameDayAs: monday))
    }

    @Test("A Sunday reference still maps to the Monday that opened its week")
    func sundayMapsToMonday() {
        // 2024-06-02 is a Sunday.
        let sunday = Date(timeIntervalSince1970: 1_717_286_400)
        let days = ISOWeek.days(containing: sunday, calendar: calendar)
        #expect(calendar.isDate(days[6], inSameDayAs: sunday))
        #expect(calendar.component(.weekday, from: days[0]) == 2)
    }
}
