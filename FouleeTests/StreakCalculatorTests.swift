import Foundation
import Testing
@testable import Foulee

@Suite("StreakCalculator")
struct StreakCalculatorTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let today = Date(timeIntervalSince1970: 1_716_768_000) // 2024-05-27, stable anchor

    @Test("Empty history yields 0")
    func emptyHistory() {
        #expect(StreakCalculator.current(history: [], goalMinutes: 20, today: today) == 0)
        #expect(StreakCalculator.best(history: [], goalMinutes: 20) == 0)
    }

    @Test("Five consecutive days at or above goal → streak of 5")
    func fiveInARow() {
        let history = days(values: [22, 24, 21, 25, 30], endingAt: today)
        #expect(StreakCalculator.current(history: history, goalMinutes: 20, today: today) == 5)
    }

    @Test("Today below goal — streak picks up from yesterday")
    func todayBelowGoal() {
        let history = days(values: [22, 24, 21, 25, 5], endingAt: today)
        #expect(StreakCalculator.current(history: history, goalMinutes: 20, today: today) == 4)
    }

    @Test("Gap in history breaks the current streak")
    func gapBreaksStreak() {
        var history = days(values: [22, 24, 21], endingAt: today)
        // Drop the day 2 days ago so there's a gap.
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: today))!
        history.removeAll { calendar.isDate($0.date, inSameDayAs: twoDaysAgo) }
        // Streak should still count today + yesterday, then break.
        #expect(StreakCalculator.current(history: history, goalMinutes: 20, today: today) == 2)
    }

    @Test("best returns longest run, current run shorter")
    func bestExceedsCurrent() {
        // 7 in a row, gap, then 3 in a row up to today.
        let pattern = [25, 22, 24, 21, 23, 25, 22, 0, 22, 24, 21]
        let history = days(values: pattern, endingAt: today)
        #expect(StreakCalculator.best(history: history, goalMinutes: 20) == 7)
        #expect(StreakCalculator.current(history: history, goalMinutes: 20, today: today) == 3)
    }

    @Test("All days below goal — both metrics are 0")
    func nothingMeetsGoal() {
        let history = days(values: [5, 8, 12, 10], endingAt: today)
        #expect(StreakCalculator.current(history: history, goalMinutes: 20, today: today) == 0)
        #expect(StreakCalculator.best(history: history, goalMinutes: 20) == 0)
    }

    private func days(values: [Int], endingAt today: Date) -> [DailyMinutes] {
        let startOfToday = calendar.startOfDay(for: today)
        return values.enumerated().map { offset, minutes in
            let date = calendar.date(
                byAdding: .day, value: -(values.count - 1 - offset), to: startOfToday
            )!
            return DailyMinutes(date: date, minutes: minutes)
        }
    }
}
