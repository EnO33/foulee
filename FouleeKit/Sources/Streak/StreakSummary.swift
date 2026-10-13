import Foundation

/// Success rate for one weekday across the history (Fitness-style "which days
/// are you most regular" breakdown).
nonisolated public struct WeekdayStat: Identifiable, Equatable, Sendable {
    public let weekday: Weekday
    /// 0…100 — share of that weekday's active days whose goal was met.
    public let rate: Int
    /// One of the user's active weekdays (false ones are muted in the UI).
    public let isActive: Bool
    public var id: Int { weekday.rawValue }
}

/// The streak and the twelve months behind it, as the Bilan opens and closes
/// on them (issue #445): the streak and its record above the periods, the
/// year's totals and the most regular weekdays below.
///
/// The year is the Bilan's own history — from the 1st of the month
/// `RecapPeriod.historyMonths - 1` months ago through today — so its totals
/// cover exactly the months the screen pages through.
nonisolated public struct StreakSummary: Equatable, Sendable {
    /// Active days in a row whose goal was met, through today.
    public let current: Int
    /// The longest such run in the history.
    public let best: Int
    /// Active days whose goal was met over the year.
    public let walks: Int
    /// Exercise minutes over the year, rest days included.
    public let minutes: Int
    /// Share of the year's active days whose goal was met, 0…100.
    public let rate: Int
    /// Monday → Sunday.
    public let weekdays: [WeekdayStat]

    /// Days still to walk to equal the record, `nil` once it is reached or
    /// while there is none.
    public var daysToRecord: Int? {
        best > current ? best - current : nil
    }

    /// How far the streak has come toward the record, 0…1. Full as soon as a
    /// streak starts with no record before it.
    public var recordProgress: Double {
        guard best > 0 else { return current > 0 ? 1 : 0 }
        return min(Double(current) / Double(best), 1)
    }

    /// `history` must cover `StreakCalculator.historyWindowDays`, as every
    /// streak surface does: a shallower one turns the record into the best of
    /// what was read (issue #176).
    public static func make(
        history: [DailyMinutes],
        goalMinutes: Int,
        activeDays: Set<Weekday>,
        today: Date,
        calendar: Calendar = .iso8601Monday
    ) -> StreakSummary {
        let start = RecapPeriod.earliest(.month, at: today, calendar: calendar).start
        let end = calendar.startOfDay(for: today)
        let byDay = Dictionary(
            history.map { (calendar.startOfDay(for: $0.date), $0.minutes) },
            uniquingKeysWith: max
        )
        let activeWeekdays = activeDays.calendarWeekdays
        let days = sequence(first: start) { calendar.date(byAdding: .day, value: 1, to: $0) }
            .prefix { $0 <= end }
            .map { (weekday: calendar.component(.weekday, from: $0), minutes: byDay[$0] ?? 0) }
        let active = days.filter { activeWeekdays.contains($0.weekday) }
        let walks = active.filter { $0.minutes >= goalMinutes }.count

        return StreakSummary(
            current: StreakCalculator.current(history: history, goalMinutes: goalMinutes, activeDays: activeDays, today: today),
            best: StreakCalculator.best(history: history, goalMinutes: goalMinutes, activeWeekdays: activeWeekdays),
            walks: walks,
            minutes: days.reduce(0) { $0 + $1.minutes },
            rate: percent(met: walks, of: active.count),
            weekdays: Weekday.allCases.map { weekday in
                let those = active.filter { $0.weekday == weekday.calendarWeekday }
                return WeekdayStat(
                    weekday: weekday,
                    rate: percent(met: those.filter { $0.minutes >= goalMinutes }.count, of: those.count),
                    isActive: activeDays.contains(weekday)
                )
            }
        )
    }

    private static func percent(met: Int, of total: Int) -> Int {
        total == 0 ? 0 : Int((Double(met) / Double(total) * 100).rounded())
    }
}
