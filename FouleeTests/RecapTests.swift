import Foundation
import Testing
@testable import Foulee

/// The week and the month in review (issue #344).
@Suite("Recap")
struct RecapTests {
    private let calendar = Calendar.iso8601Monday

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // MARK: - Periods

    @Test("Mid-week, the week recapped is the last whole one, Monday to Monday")
    func lastWeek() {
        // Saturday 10 October 2026.
        let period = RecapPeriod.lastCompleted(.week, before: day(2026, 10, 10, hour: 12), calendar: calendar)
        #expect(period.start == day(2026, 9, 28))
        #expect(period.end == day(2026, 10, 5))
        #expect(period.days(calendar: calendar).count == 7)
    }

    /// The notification lands on Monday morning: that week is not done.
    @Test("On a Monday, the week recapped ended last night")
    func onMonday() {
        let period = RecapPeriod.lastCompleted(.week, before: day(2026, 10, 5, hour: 9), calendar: calendar)
        #expect(period.start == day(2026, 9, 28))
        #expect(period.end == day(2026, 10, 5))
    }

    @Test("On the 1st, the month recapped is the one that just ended")
    func lastMonth() {
        let period = RecapPeriod.lastCompleted(.month, before: day(2026, 10, 1, hour: 9), calendar: calendar)
        #expect(period.start == day(2026, 9, 1))
        #expect(period.end == day(2026, 10, 1))
        #expect(period.days(calendar: calendar).count == 30)
        #expect(period.title == "Septembre 2026")
        #expect(period.previous(calendar: calendar).start == day(2026, 8, 1))
    }

    // MARK: - Totals

    private var september: RecapPeriod {
        RecapPeriod.lastCompleted(.month, before: day(2026, 10, 10), calendar: calendar)
    }

    private func workout(on date: Date, outing: OutingLeg? = nil) -> WorkoutSummary {
        WorkoutSummary(
            id: UUID(),
            startedAt: date,
            endedAt: date.addingTimeInterval(1_200),
            durationSeconds: 1_200,
            distanceKm: 2,
            activeCalories: 90,
            sourceName: "Foulée",
            activity: .walking,
            outing: outing
        )
    }

    private func recap(activeDays: Set<Weekday> = Set(Weekday.allCases)) -> Recap {
        let sharedOuting = UUID()
        let inputs = Recap.Inputs(
            minutes: [
                DailyMinutes(date: day(2026, 8, 20), minutes: 30),   // August: the period before
                DailyMinutes(date: day(2026, 9, 1), minutes: 25),
                DailyMinutes(date: day(2026, 9, 2), minutes: 10),
                DailyMinutes(date: day(2026, 9, 15), minutes: 45),
                DailyMinutes(date: day(2026, 10, 2), minutes: 60)    // October: outside
            ],
            steps: [MetricPoint(date: day(2026, 9, 1), value: 4_000), MetricPoint(date: day(2026, 8, 3), value: 2_000)],
            distance: [MetricPoint(date: day(2026, 9, 1), value: 3.25)],
            calories: [MetricPoint(date: day(2026, 9, 1), value: 210.4)],
            workouts: [
                // Two legs of one outing, then a walk on its own.
                workout(on: day(2026, 9, 1, hour: 12), outing: OutingLeg(outingID: sharedOuting, index: 0)),
                workout(on: day(2026, 9, 1, hour: 12).addingTimeInterval(1_200), outing: OutingLeg(outingID: sharedOuting, index: 1)),
                workout(on: day(2026, 9, 15, hour: 18)),
                workout(on: day(2026, 10, 2, hour: 12))
            ]
        )
        return Recap.make(period: september, from: inputs, goalMinutes: 20, activeDays: activeDays, calendar: calendar)
    }

    @Test("Only the period's own days count")
    func totals() {
        let totals = recap().totals
        #expect(totals.minutes == 80)
        #expect(totals.steps == 4_000)
        #expect(totals.distanceKm == 3.25)
        #expect(totals.calories == 210)
    }

    /// The legs of one outing are one outing, as in the résumé.
    @Test("Outings are counted like the résumé counts them")
    func outings() {
        #expect(recap().totals.outings == 2)
    }

    @Test("The period before is totalled for the comparison")
    func previous() {
        let previous = recap().previous
        #expect(previous.minutes == 30)
        #expect(previous.steps == 2_000)
    }

    @Test("Every day of the period is there, zero-filled")
    func days() {
        let days = recap().days
        #expect(days.count == 30)
        #expect(days.first?.minutes == 25)
        #expect(days[1].minutes == 10)
        #expect(days[2].minutes == 0)
    }

    @Test("The goal is counted on active days only")
    func goalDays() {
        // September 2026: the 1st and 15th are Tuesdays, the 2nd a Wednesday.
        let everyDay = recap()
        #expect(everyDay.goalDaysPlanned == 30)
        #expect(everyDay.goalDaysMet == 2)

        let tuesdays = recap(activeDays: [.tuesday])
        #expect(tuesdays.goalDaysPlanned == 5)
        #expect(tuesdays.goalDaysMet == 2)
    }

    @Test("The best day is the one with the most minutes")
    func bestDay() {
        #expect(recap().bestDay == DailyMinutes(date: day(2026, 9, 15), minutes: 45))
    }

    @Test("A period without anything is empty")
    func empty() {
        let recap = Recap.make(period: september, from: Recap.Inputs(), goalMinutes: 20, activeDays: [], calendar: calendar)
        #expect(recap.isEmpty)
        #expect(recap.bestDay == nil)
    }

    // MARK: - Change

    @Test("A change is a fraction of what came before, and nothing without a before")
    func change() {
        #expect(Recap.change(from: 100, to: 112) == 0.12)
        #expect(Recap.change(from: 100, to: 50) == -0.5)
        #expect(Recap.change(from: 0, to: 50) == nil)
    }
}
