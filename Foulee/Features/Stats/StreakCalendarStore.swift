import Dependencies
import Foundation
import Observation

/// Loads the day history behind the streak calendar and derives the grid +
/// current/record streaks. Mirrors the other stores' single error boundary.
@MainActor
@Observable
final class StreakCalendarStore {
    static let weeks = 5

    let goalMinutes: Int
    let activeDays: Set<Weekday>

    private(set) var days: [CalendarDay] = []
    private(set) var currentStreak = 0
    private(set) var bestStreak = 0
    private(set) var isLoading = true

    @ObservationIgnored
    @Dependency(\.healthKit) private var healthKit

    init(goalMinutes: Int, activeDays: Set<Weekday>) {
        self.goalMinutes = goalMinutes
        self.activeDays = activeDays
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        // Pull a little extra so a Monday-aligned grid is fully covered.
        let history = (try? await healthKit.dailyMinutes(Self.weeks * 7 + 7)) ?? []
        days = StreakCalendar.build(
            history: history,
            goalMinutes: goalMinutes,
            activeDays: activeDays,
            today: .now,
            weeks: Self.weeks
        )
        currentStreak = StreakCalculator.current(
            history: history,
            goalMinutes: goalMinutes,
            activeWeekdays: activeDays.calendarWeekdays,
            today: .now
        )
        bestStreak = StreakCalculator.best(
            history: history,
            goalMinutes: goalMinutes,
            activeWeekdays: activeDays.calendarWeekdays
        )
    }
}
