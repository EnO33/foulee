import Foundation

/// A week or a month the recap looks back on (issues #344, #350).
///
/// The week is the **last seven days**, today included: the Bilan is where the
/// outings of the days just gone are read (#350). The month stays the last
/// **finished** one: on the 1st, the month that just ended.
struct RecapPeriod: Hashable, Sendable {
    enum Kind: String, CaseIterable, Identifiable, Sendable {
        case week
        case month

        var id: String { rawValue }

        var label: String {
            switch self {
            case .week: "Semaine"
            case .month: "Mois"
            }
        }

        fileprivate var component: Calendar.Component {
            switch self {
            case .week: .weekOfYear
            case .month: .month
            }
        }
    }

    var kind: Kind
    /// First instant of the period.
    var start: Date
    /// First instant **after** the period.
    var end: Date

    /// The period the Bilan shows for `kind` at `now`: the last seven days for
    /// the week, the last finished month for the month (issue #350).
    static func current(_ kind: Kind, at now: Date, calendar: Calendar = .iso8601Monday) -> RecapPeriod {
        switch kind {
        case .week: lastDays(endingOn: now, calendar: calendar)
        case .month: lastCompleted(.month, before: now, calendar: calendar)
        }
    }

    /// The last period of `kind` to have ended before `now`.
    ///
    /// The calendar is ISO, Monday first, like every week the app draws: a
    /// recap that cut its weeks on Sunday would disagree with the home's bars.
    static func lastCompleted(_ kind: Kind, before now: Date, calendar: Calendar = .iso8601Monday) -> RecapPeriod {
        let current = calendar.dateInterval(of: kind.component, for: now)
            ?? DateInterval(start: calendar.startOfDay(for: now), duration: 0)
        return period(kind, containing: current.start.addingTimeInterval(-1), calendar: calendar)
    }

    /// The last `count` days, today included — the Bilan's week (issues #348,
    /// #350). Rolling rather than calendar-aligned, so it is a `.week` that
    /// need not start on a Monday.
    static func lastDays(_ count: Int = 7, endingOn now: Date, calendar: Calendar = .iso8601Monday) -> RecapPeriod {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let start = calendar.date(byAdding: .day, value: -count, to: tomorrow) ?? now
        return RecapPeriod(kind: .week, start: start, end: tomorrow)
    }

    /// The period just before this one — what the recap compares against.
    ///
    /// For a week, the seven days before (issue #348): the same as the
    /// previous ISO week for a calendar week, and the right answer for a
    /// rolling one. For a month, the calendar month before.
    func previous(calendar: Calendar = .iso8601Monday) -> RecapPeriod {
        switch kind {
        case .week:
            let length = calendar.dateComponents([.day], from: start, to: end).day ?? 7
            let earlier = calendar.date(byAdding: .day, value: -length, to: start) ?? start
            return RecapPeriod(kind: kind, start: earlier, end: start)
        case .month:
            return Self.period(kind, containing: start.addingTimeInterval(-1), calendar: calendar)
        }
    }

    func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }

    /// Each day of the period, as day starts, in order.
    func days(calendar: Calendar = .iso8601Monday) -> [Date] {
        var days: [Date] = []
        var cursor = calendar.startOfDay(for: start)
        while cursor < end {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    /// « Du 29 sept. au 5 oct. » for a week, « Septembre 2026 » for a month.
    var title: String {
        switch kind {
        case .week:
            let last = end.addingTimeInterval(-1)
            return "Du \(Self.dayFormatter.string(from: start)) au \(Self.dayFormatter.string(from: last))"
        case .month:
            return Self.monthFormatter.string(from: start).capitalized(with: Self.french)
        }
    }

    private static func period(_ kind: Kind, containing date: Date, calendar: Calendar) -> RecapPeriod {
        let interval = calendar.dateInterval(of: kind.component, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 86_400)
        return RecapPeriod(kind: kind, start: interval.start, end: interval.end)
    }

    private static let french = Locale(identifier: "fr_FR")

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = french
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = french
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()
}
