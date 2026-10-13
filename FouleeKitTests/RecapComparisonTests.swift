import Foundation
import Testing
@testable import FouleeKit

/// A period against the one before (issues #346, #454): the change, what is
/// left to match it, and the days it is compared with.
@Suite("Recap comparison")
struct RecapComparisonTests {
    private let calendar = Calendar.iso8601Monday

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test("A change is a fraction of what came before, and nothing without a before")
    func change() {
        #expect(Recap.change(from: 100, to: 112) == 0.12)
        #expect(Recap.change(from: 100, to: 50) == -0.5)
        #expect(Recap.change(from: 0, to: 50) == nil)
    }

    @Test("A period in progress behind the one before has something left to match")
    func remaining() {
        #expect(Recap.remaining(from: 10, toMatch: 42) == 32)
        #expect(Recap.remaining(from: 42, toMatch: 42) == nil)
        #expect(Recap.remaining(from: 50, toMatch: 42) == nil)
    }

    @Test("A comparison names its days: a range, or a single day")
    func span() {
        // Tuesday 6 October 2026: the week so far, then the same days before.
        let week = RecapPeriod.current(.week, at: day(2026, 10, 6, hour: 12), calendar: calendar)
        #expect(week.previous(calendar: calendar).span == "Du 28 sept. au 29 sept.")
        // On a Monday, the week so far is one day.
        let monday = RecapPeriod.current(.week, at: day(2026, 10, 5, hour: 12), calendar: calendar)
        #expect(monday.previous(calendar: calendar).span == "Le 28 sept.")
        #expect(monday.title == "Le 5 oct.")
    }
}
