import Foundation
import Testing
@testable import Foulee

@Suite("TodaySnapshot")
struct TodaySnapshotTests {
    @Test("hasNoActivity is true when everything is zero")
    func emptyIsEmpty() {
        #expect(makeSnapshot().hasNoActivity)
    }

    @Test("Any steps make it non-empty")
    func stepsCount() {
        #expect(!makeSnapshot(steps: 120).hasNoActivity)
    }

    @Test("A past streak keeps it non-empty even with no steps today")
    func streakCounts() {
        #expect(!makeSnapshot(streak: 3).hasNoActivity)
    }

    @Test("History earlier in the week keeps it non-empty")
    func weekHistoryCounts() {
        #expect(!makeSnapshot(weekMinutes: [0, 22, 0, 0, 0, 0, 0]).hasNoActivity)
    }

    private func makeSnapshot(
        steps: Int = 0,
        streak: Int = 0,
        weekMinutes: [Int] = Array(repeating: 0, count: 7)
    ) -> TodaySnapshot {
        TodaySnapshot(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            steps: steps,
            stepsGoal: 6_000,
            minutes: 0,
            minutesGoal: 20,
            distanceKm: 0,
            calories: 0,
            streak: streak,
            bestStreak: 0,
            weather: WeatherSnapshot(temperatureCelsius: 0, condition: "—", advice: ""),
            weekMinutes: weekMinutes,
            weekGoal: 20,
            walkWindowStart: DateComponents(hour: 12, minute: 0),
            hasWalkedToday: false
        )
    }
}
