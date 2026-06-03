import Foundation

/// How a single day reads on the streak calendar.
enum DayStatus: Equatable, Sendable {
    case done    // active day, goal met
    case missed  // active day, goal not met
    case rest    // not one of the user's active weekdays
    case future  // hasn't happened yet (fills the current month)
}

/// One cell of the streak calendar.
struct CalendarDay: Identifiable, Equatable, Sendable {
    let date: Date
    let status: DayStatus
    /// Exercise minutes that day (drives the ring fill + the day detail).
    let minutes: Int
    var id: Date { date }
}

/// One calendar month laid out for the rings browser: weekday-aligned cells
/// (leading `nil`s pad the first week, trailing `nil`s pad to a fixed 6 rows so
/// pages don't change height), the month's title, and a few derived stats.
struct StreakMonth: Identifiable, Equatable, Sendable {
    let monthStart: Date
    let title: String
    let cells: [CalendarDay?]
    var id: Date { monthStart }

    private var realDays: [CalendarDay] { cells.compactMap { $0 } }

    /// Days whose goal was met.
    var walks: Int { realDays.filter { $0.status == .done }.count }

    /// Total exercise minutes logged across the month.
    var minutes: Int { realDays.reduce(0) { $0 + $1.minutes } }

    /// Share of active (past, non-rest) days whose goal was met, as a percent.
    var rate: Int {
        let active = realDays.filter { $0.status == .done || $0.status == .missed }
        guard !active.isEmpty else { return 0 }
        let done = active.filter { $0.status == .done }.count
        return Int((Double(done) / Double(active.count) * 100).rounded())
    }
}

/// Pure builder for the streak rings — the last `count` calendar months, each
/// weekday-aligned (Monday first) for a 7-column grid.
enum StreakCalendar {
    /// The last `count` calendar months, oldest → newest (current month last).
    /// Each month's `cells` start with leading `nil`s so the 1st lands under its
    /// weekday column, and are padded with trailing `nil`s to exactly 6 rows
    /// (42 cells) so swiping between months keeps a stable height.
    static func months(
        history: [DailyMinutes],
        goalMinutes: Int,
        activeDays: Set<Weekday>,
        today: Date,
        count: Int,
        calendar: Calendar = .iso8601Monday
    ) -> [StreakMonth] {
        let startOfToday = calendar.startOfDay(for: today)
        guard count > 0,
              let currentMonthStart = calendar.date(
                  from: calendar.dateComponents([.year, .month], from: startOfToday))
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

        return (0..<count).reversed().compactMap { back in
            guard let monthStart = calendar.date(byAdding: .month, value: -back, to: currentMonthStart),
                  let dayRange = calendar.range(of: .day, in: .month, for: monthStart)
            else { return nil }
            // Monday-based offset of the 1st (Mon = 0 … Sun = 6).
            let leading = (calendar.component(.weekday, from: monthStart) + 5) % 7
            var cells: [CalendarDay?] = Array(repeating: nil, count: leading)
            for day in dayRange {
                guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else { continue }
                cells.append(CalendarDay(date: date, status: status(of: date), minutes: byDay[date] ?? 0))
            }
            while cells.count < 42 { cells.append(nil) } // pad to 6 rows
            return StreakMonth(monthStart: monthStart, title: monthTitle(monthStart), cells: cells)
        }
    }

    private static let monthTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return formatter
    }()

    private static func monthTitle(_ date: Date) -> String {
        monthTitleFormatter.string(from: date).capitalized
    }
}
