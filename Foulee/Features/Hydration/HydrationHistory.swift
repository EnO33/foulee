import Foundation

/// The week's water so far (issues #355, #363), read like the Bilan reads
/// minutes: Monday through today, one day each, zero-filled, how many of them
/// held the goal — and the days still to come, drawn but never counted.
struct HydrationHistory: Equatable, Sendable {
    struct Day: Identifiable, Equatable, Sendable {
        var date: Date
        var milliliters: Int

        var id: Date { date }
    }

    /// Days of history read: enough for any week so far, today included.
    static let window = 7

    /// Monday first, today last.
    var days: [Day]
    /// The rest of the week, through Sunday.
    var daysToCome: [Date] = []
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

    /// The week of `now` so far, filled from the daily series: a day the
    /// series does not hold, or holds as zero, is a day without water.
    static func make(series: [MetricPoint], goalML: Int, now: Date, calendar: Calendar = .iso8601Monday) -> HydrationHistory {
        let week = RecapPeriod.weekSoFar(at: now, calendar: calendar)
        let byDay = Dictionary(series.map { (calendar.startOfDay(for: $0.date), $0.value) }, uniquingKeysWith: +)
        return HydrationHistory(
            days: week.days(calendar: calendar).map { Day(date: $0, milliliters: Int((byDay[$0] ?? 0).rounded())) },
            daysToCome: week.daysToCome(calendar: calendar),
            goalML: goalML
        )
    }
}
