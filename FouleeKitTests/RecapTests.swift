import Foundation
import Testing
@testable import FouleeKit

/// The week and the month in review (issues #344, #350).
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

    /// The week in progress is never a finished one.
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

    @Test("The whole week and month a date falls in")
    func containing() {
        let week = RecapPeriod.containing(day(2026, 10, 10, hour: 12), .week, calendar: calendar)
        #expect(week.start == day(2026, 10, 5))
        #expect(week.end == day(2026, 10, 12))
        let month = RecapPeriod.containing(day(2026, 10, 10, hour: 12), .month, calendar: calendar)
        #expect(month.start == day(2026, 10, 1))
        #expect(month.end == day(2026, 11, 1))
    }

    @Test("A calendar week's previous is the week before")
    func previousWeek() {
        let period = RecapPeriod.lastCompleted(.week, before: day(2026, 10, 10, hour: 12), calendar: calendar)
        let previous = period.previous(calendar: calendar)
        #expect(previous.start == day(2026, 9, 21))
        #expect(previous.end == day(2026, 9, 28))
    }

    /// The Bilan's week (issue #363): Monday through today, compared with the
    /// same days a week earlier.
    @Test("The week so far starts on Monday, and compares with the same days last week")
    func weekSoFar() {
        let period = RecapPeriod.weekSoFar(at: day(2026, 10, 10, hour: 18), calendar: calendar)
        #expect(period.start == day(2026, 10, 5))
        #expect(period.end == day(2026, 10, 11))
        #expect(period.days(calendar: calendar).count == 6)
        let previous = period.previous(calendar: calendar)
        #expect(previous.start == day(2026, 9, 28))
        #expect(previous.end == day(2026, 10, 4))
    }

    @Test("Sunday is the only day still to come on a Saturday")
    func daysToCome() {
        let saturday = RecapPeriod.weekSoFar(at: day(2026, 10, 10, hour: 18), calendar: calendar)
        #expect(saturday.daysToCome(calendar: calendar) == [day(2026, 10, 11)])
        let monday = RecapPeriod.weekSoFar(at: day(2026, 10, 5, hour: 8), calendar: calendar)
        #expect(monday.days(calendar: calendar) == [day(2026, 10, 5)])
        #expect(monday.daysToCome(calendar: calendar).count == 6)
        let sunday = RecapPeriod.weekSoFar(at: day(2026, 10, 11, hour: 20), calendar: calendar)
        #expect(sunday.daysToCome(calendar: calendar).isEmpty)
        #expect(sunday.days(calendar: calendar).count == 7)
    }

    @Test("A whole week or month has no days to come")
    func wholePeriods() {
        let week = RecapPeriod.lastCompleted(.week, before: day(2026, 10, 10, hour: 12), calendar: calendar)
        #expect(week.daysToCome(calendar: calendar).isEmpty)
        #expect(september.daysToCome(calendar: calendar).isEmpty)
    }

    /// What the Bilan opens on (issues #350, #363, #444).
    @Test("The Bilan opens on the week so far and the month so far")
    func currentPeriods() {
        let saturday = day(2026, 10, 10, hour: 18)
        let week = RecapPeriod.current(.week, at: saturday, calendar: calendar)
        #expect(week == RecapPeriod.weekSoFar(at: saturday, calendar: calendar))
        let month = RecapPeriod.current(.month, at: saturday, calendar: calendar)
        #expect(month.start == day(2026, 10, 1))
        #expect(month.end == day(2026, 10, 11))
        #expect(month.isInProgress(at: saturday))
    }

    /// Twenty-one pale days after the 10th, through the 31st.
    @Test("A month in progress has the rest of the month to come")
    func monthDaysToCome() {
        let month = RecapPeriod.monthSoFar(at: day(2026, 10, 10, hour: 18), calendar: calendar)
        let toCome = month.daysToCome(calendar: calendar)
        #expect(toCome.count == 21)
        #expect(toCome.first == day(2026, 10, 11))
        #expect(toCome.last == day(2026, 10, 31))
    }

    /// The 10th against the 10 first days of September, never against a
    /// whole month it could only fall short of.
    @Test("A month in progress compares with the same days of the month before")
    func monthSoFarComparesTheSameDays() {
        let previous = RecapPeriod.monthSoFar(at: day(2026, 10, 10, hour: 18), calendar: calendar).previous(calendar: calendar)
        #expect(previous.start == day(2026, 9, 1))
        #expect(previous.end == day(2026, 9, 11))
    }

    /// 30 March in progress: the month before has 28 days, and the
    /// comparison stops at its end rather than spilling into March.
    @Test("The comparison of a long month stops at the end of a short one")
    func monthSoFarComparisonIsCut() {
        let previous = RecapPeriod.monthSoFar(at: day(2027, 3, 30, hour: 18), calendar: calendar).previous(calendar: calendar)
        #expect(previous.start == day(2027, 2, 1))
        #expect(previous.end == day(2027, 3, 1))
    }

    @Test("A whole month still compares with the whole month before")
    func wholeMonthComparesTheWholeMonthBefore() {
        let previous = september.previous(calendar: calendar)
        #expect(previous.start == day(2026, 8, 1))
        #expect(previous.end == day(2026, 9, 1))
    }

    // MARK: - Paging (issue #444)

    @Test("Paging back from the week so far shows the whole week before")
    func earlierWeek() {
        let week = RecapPeriod.weekSoFar(at: day(2026, 10, 10, hour: 18), calendar: calendar)
        let before = week.earlier(calendar: calendar)
        #expect(before.start == day(2026, 9, 28))
        #expect(before.end == day(2026, 10, 5))
        #expect(!before.isInProgress(at: day(2026, 10, 10, hour: 18)))
    }

    @Test("Paging back from the month so far shows the whole month before")
    func earlierMonth() {
        let month = RecapPeriod.monthSoFar(at: day(2026, 10, 10, hour: 18), calendar: calendar)
        #expect(month.earlier(calendar: calendar) == september)
    }

    @Test("Paging forward lands on the period in progress, cut at today, and stops there")
    func laterStopsAtToday() throws {
        let now = day(2026, 10, 10, hour: 18)
        let forward = try #require(september.later(at: now, calendar: calendar))
        #expect(forward == RecapPeriod.monthSoFar(at: now, calendar: calendar))
        #expect(forward.later(at: now, calendar: calendar) == nil)

        let august = september.earlier(calendar: calendar)
        #expect(august.later(at: now, calendar: calendar) == september)
    }

    /// November 2025 through October 2026: twelve months, this one included.
    @Test("The history reaches back twelve months, this one included")
    func history() {
        let now = day(2026, 10, 10, hour: 18)
        let earliestMonth = RecapPeriod.earliest(.month, at: now, calendar: calendar)
        #expect(earliestMonth.start == day(2025, 11, 1))
        #expect(!earliestMonth.hasEarlier(at: now, calendar: calendar))
        #expect(earliestMonth.later(at: now, calendar: calendar)?.hasEarlier(at: now, calendar: calendar) == true)

        // The week that holds 1 November 2025, a Saturday.
        let earliestWeek = RecapPeriod.earliest(.week, at: now, calendar: calendar)
        #expect(earliestWeek.start == day(2025, 10, 27))
        #expect(!earliestWeek.hasEarlier(at: now, calendar: calendar))
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
        #expect(recap().bestDay == Recap.Day(date: day(2026, 9, 15), minutes: 45, isPlanned: true))
    }

    @Test("A period without anything is empty")
    func empty() {
        let recap = Recap.make(period: september, from: Recap.Inputs(), goalMinutes: 20, activeDays: [], calendar: calendar)
        #expect(recap.isEmpty)
        #expect(recap.bestDay == nil)
    }

    @Test("Rest days are marked as such")
    func restDays() {
        let tuesdays = recap(activeDays: [.tuesday])
        #expect(tuesdays.days[0].isPlanned)      // Tuesday 1st
        #expect(!tuesdays.days[1].isPlanned)     // Wednesday 2nd
    }

    // MARK: - Verdict

    private func recap(met: Int, planned: Int, minutes: Int, before: Int) -> Recap {
        Recap(
            period: september,
            totals: Recap.Totals(minutes: minutes),
            previous: Recap.Totals(minutes: before),
            days: [],
            goalMinutes: 20,
            goalDaysMet: met,
            goalDaysPlanned: planned
        )
    }

    @Test("The verdict says what the period means, most telling first")
    func verdicts() {
        #expect(recap(met: 0, planned: 5, minutes: 0, before: 50).verdict == .quiet)
        #expect(recap(met: 5, planned: 5, minutes: 100, before: 300).verdict == .perfect)
        #expect(recap(met: 4, planned: 5, minutes: 100, before: 300).verdict == .steady)
        #expect(recap(met: 1, planned: 5, minutes: 100, before: 50).verdict == .improving)
        #expect(recap(met: 1, planned: 5, minutes: 40, before: 50).verdict == .started)
        #expect(recap(met: 1, planned: 5, minutes: 40, before: 0).verdict == .started)
    }
}
