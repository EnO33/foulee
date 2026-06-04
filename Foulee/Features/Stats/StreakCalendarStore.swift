import Dependencies
import Foundation
import Observation

/// Loads the day history behind the streak rings and derives the browsable
/// months + current/record streaks. Mirrors the other stores' single error
/// boundary.
@MainActor
@Observable
final class StreakCalendarStore {
    /// How many calendar months the rings browser can page back through.
    static let monthsBack = 12

    let goalMinutes: Int
    let activeDays: Set<Weekday>

    private(set) var months: [StreakMonth] = []
    private(set) var currentStreak = 0
    private(set) var bestStreak = 0
    private(set) var isLoading = true

    /// Goals met across all loaded months.
    var totalWalks: Int { months.reduce(0) { $0 + $1.walks } }

    /// Exercise minutes across all loaded months.
    var totalMinutes: Int { months.reduce(0) { $0 + $1.minutes } }

    /// Overall success rate across every active day in the loaded history.
    var overallRate: Int {
        let active = months
            .flatMap { $0.cells.compactMap { $0 } }
            .filter { $0.status == .done || $0.status == .missed }
        guard !active.isEmpty else { return 0 }
        let done = active.filter { $0.status == .done }.count
        return Int((Double(done) / Double(active.count) * 100).rounded())
    }

    /// Per-weekday regularity over the loaded history.
    var weekdayStats: [WeekdayStat] {
        StreakCalendar.weekdayStats(months: months, activeDays: activeDays)
    }

    @ObservationIgnored
    @Dependency(\.healthKit) private var healthKit

    init(goalMinutes: Int, activeDays: Set<Weekday>) {
        self.goalMinutes = goalMinutes
        self.activeDays = activeDays
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        // Pull enough to cover the 1st of the oldest month, plus a little slack.
        let history = (try? await healthKit.dailyMinutes(Self.monthsBack * 31 + 7)) ?? []
        months = StreakCalendar.months(
            history: history,
            goalMinutes: goalMinutes,
            activeDays: activeDays,
            today: .now,
            count: Self.monthsBack
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
