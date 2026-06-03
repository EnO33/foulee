import Foundation

/// How a single day reads on the streak calendar.
enum DayStatus: Equatable, Sendable {
    case done    // active day, goal met
    case missed  // active day, goal not met
    case rest    // not one of the user's active weekdays
    case future  // hasn't happened yet (fills the current week)
}

/// One cell of the streak calendar.
struct CalendarDay: Identifiable, Equatable, Sendable {
    let date: Date
    let status: DayStatus
    /// Exercise minutes that day (drives the ring fill + the day detail).
    let minutes: Int
    var id: Date { date }
}

/// Pure builder for the heatmap grid — Monday-aligned days, oldest → newest,
/// exactly `weeks * 7` long so a 7-column grid lays out one week per row.
enum StreakCalendar {
    static func build(
        history: [DailyMinutes],
        goalMinutes: Int,
        activeDays: Set<Weekday>,
        today: Date,
        weeks: Int,
        calendar: Calendar = .iso8601Monday
    ) -> [CalendarDay] {
        let startOfToday = calendar.startOfDay(for: today)
        let mondayThisWeek = ISOWeek.days(containing: startOfToday, calendar: calendar).first ?? startOfToday
        guard weeks > 0,
              let start = calendar.date(byAdding: .day, value: -(weeks - 1) * 7, to: mondayThisWeek)
        else { return [] }

        let byDay = Dictionary(
            uniqueKeysWithValues: history.map { (calendar.startOfDay(for: $0.date), $0.minutes) }
        )
        let activeWeekdays = Set(activeDays.map(\.calendarWeekday))

        func status(of date: Date) -> DayStatus {
            if date > startOfToday { return .future }
            guard activeWeekdays.contains(calendar.component(.weekday, from: date)) else { return .rest }
            return (byDay[date] ?? 0) >= goalMinutes ? .done : .missed
        }

        return (0..<(weeks * 7)).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return CalendarDay(date: date, status: status(of: date), minutes: byDay[date] ?? 0)
        }
    }
}
