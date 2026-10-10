import Foundation

/// A week or a month the recap looks back on (issues #344, #350, #363).
///
/// The week is the **week in progress**, Monday through today: the Bilan is
/// where the outings of the days just gone are read (#350), in the Monday-first
/// week the rest of the app draws (#363). The month stays the last **finished**
/// one: on the 1st, the month that just ended.
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

    /// The period the Bilan shows for `kind` at `now`: the week so far, and
    /// the last finished month (issues #350, #363).
    static func current(_ kind: Kind, at now: Date, calendar: Calendar = .iso8601Monday) -> RecapPeriod {
        switch kind {
        case .week: weekSoFar(at: now, calendar: calendar)
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

    /// The week in progress, Monday through today — the Bilan's week (issue
    /// #363). Its totals are the days lived; `daysToCome` are the rest.
    static func weekSoFar(at now: Date, calendar: Calendar = .iso8601Monday) -> RecapPeriod {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let monday = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        return RecapPeriod(kind: .week, start: monday, end: tomorrow)
    }

    /// The days of a week in progress still to come, through Sunday: drawn,
    /// never counted. Empty for a month, or a week already over.
    func daysToCome(calendar: Calendar = .iso8601Monday) -> [Date] {
        guard kind == .week, let week = calendar.dateInterval(of: .weekOfYear, for: start) else { return [] }
        var days: [Date] = []
        var cursor = calendar.startOfDay(for: end)
        while cursor < week.end {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    /// The period just before this one — what the recap compares against.
    ///
    /// For a week, the same days a week earlier (issues #348, #363): the
    /// previous ISO week for a whole week, and Monday → Saturday against Monday
    /// → Saturday for a week in progress — a fair comparison either way. For a
    /// month, the calendar month before.
    func previous(calendar: Calendar = .iso8601Monday) -> RecapPeriod {
        switch kind {
        case .week:
            let earlier: (Date) -> Date = { calendar.date(byAdding: .day, value: -7, to: $0) ?? $0 }
            return RecapPeriod(kind: kind, start: earlier(start), end: earlier(end))
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
