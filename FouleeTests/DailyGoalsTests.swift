import Foundation
import Testing
@testable import Foulee

/// The moment a ring closes on the home (issue #368).
@Suite("Daily goals")
struct DailyGoalsTests {
    private func snapshot(steps: Int = 0, minutes: Int = 0, walked: Bool = false) -> TodaySnapshot {
        TodaySnapshot(
            date: Date(timeIntervalSince1970: 0),
            steps: steps,
            stepsGoal: 8_000,
            minutes: minutes,
            minutesGoal: 30,
            distanceKm: 0,
            calories: 0,
            streak: 0,
            bestStreak: 0,
            weather: WeatherSnapshot(temperatureCelsius: 0, condition: "", advice: ""),
            weekMinutes: [],
            walkWindowStart: DateComponents(),
            hasWalkedToday: walked
        )
    }

    @Test("Each goal is met at its threshold")
    func thresholds() {
        #expect(DailyGoals(snapshot(steps: 7_999, minutes: 29)) == DailyGoals(steps: false, minutes: false))
        #expect(DailyGoals(snapshot(steps: 8_000, minutes: 30)) == DailyGoals(steps: true, minutes: true))
    }

    @Test("A finished outing closes the minutes ring")
    func finishedOuting() {
        #expect(DailyGoals(snapshot(minutes: 12, walked: true)).minutes)
    }

    @Test("Closing either ring is celebrated")
    func crossing() {
        let none = DailyGoals(steps: false, minutes: false)
        #expect(DailyGoals(steps: true, minutes: false).closesARing(since: none))
        #expect(DailyGoals(steps: false, minutes: true).closesARing(since: none))
        #expect(DailyGoals(steps: true, minutes: true).closesARing(since: DailyGoals(steps: true, minutes: false)))
    }

    @Test("A ring already closed, or one that opens again, is not")
    func noCrossing() {
        let both = DailyGoals(steps: true, minutes: true)
        #expect(!both.closesARing(since: both))
        #expect(!DailyGoals(steps: false, minutes: true).closesARing(since: both))
    }
}
