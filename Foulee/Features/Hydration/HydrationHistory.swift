import Foundation

/// The last seven days of water (issue #355), read like the Bilan reads
/// minutes: one day each, zero-filled, and how many of them held the goal.
struct HydrationHistory: Equatable, Sendable {
    struct Day: Identifiable, Equatable, Sendable {
        var date: Date
        var milliliters: Int

        var id: Date { date }
    }

    /// How many days the screen shows, today included.
    static let window = 7

    /// Oldest first, today last.
    var days: [Day]
    var goalML: Int

    /// Days whose total reached the goal.
    var goalDaysMet: Int {
        days.filter { HydrationMath.reachedGoal(intakeML: $0.milliliters, goalML: goalML) }.count
    }

    /// Mean of the days, today included, in millilitres.
    var averageML: Int {
        guard !days.isEmpty else { return 0 }
        return days.map(\.milliliters).reduce(0, +) / days.count
    }

    /// `window` days ending on `now`'s, filled from the daily series: a day the
    /// series does not hold, or holds as zero, is a day without water.
    static func make(series: [MetricPoint], goalML: Int, now: Date, calendar: Calendar = .current) -> HydrationHistory {
        let today = calendar.startOfDay(for: now)
        let byDay = Dictionary(series.map { (calendar.startOfDay(for: $0.date), $0.value) }, uniquingKeysWith: +)
        let days = (0..<window).reversed().compactMap { offset -> Day? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return Day(date: date, milliliters: Int((byDay[date] ?? 0).rounded()))
        }
        return HydrationHistory(days: days, goalML: goalML)
    }
}
