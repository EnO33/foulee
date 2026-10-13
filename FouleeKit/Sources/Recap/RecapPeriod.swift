import Foundation

/// A week or a month the recap looks back on (issues #344, #350, #363, #444).
///
/// The Bilan opens on the **period in progress**, Monday through today or the
/// 1st through today: it is where the outings of the days just gone are read
/// (#350), in the Monday-first week the rest of the app draws (#363). From
/// there it pages back, one whole week or month at a time, as far as
/// `historyMonths` (#444).
nonisolated public struct RecapPeriod: Hashable, Sendable {
    nonisolated public enum Kind: String, CaseIterable, Identifiable, Sendable {
        case week
        case month

        public var id: String { rawValue }

        public var label: String {
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

    public var kind: Kind
    /// First instant of the period.
    public var start: Date
    /// First instant **after** the period.
    public var end: Date

    /// How far back the Bilan pages (issue #444): this month and the eleven
    /// before it — the streak's own year, whose totals close the Bilan (#445).
    public static let historyMonths = StreakCalculator.historyMonths

    /// The period the Bilan opens on for `kind` at `now`: the one in progress,
    /// through today (issues #363, #444).
    public static func current(_ kind: Kind, at now: Date, calendar: Calendar = .iso8601Monday) -> RecapPeriod {
        switch kind {
        case .week: weekSoFar(at: now, calendar: calendar)
        case .month: monthSoFar(at: now, calendar: calendar)
        }
    }

    /// The month in progress, the 1st through today (issue #444). It used to
    /// be the last finished month, which the Bilan could not leave: today was
    /// never in it.
    public static func monthSoFar(at now: Date, calendar: Calendar = .iso8601Monday) -> RecapPeriod {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let first = calendar.dateInterval(of: .month, for: now)?.start ?? today
        return RecapPeriod(kind: .month, start: first, end: tomorrow)
    }

    // MARK: - Paging (issue #444)

    /// Whether `now` falls in this period: the one in progress, which ends
    /// tomorrow and has days to come.
    public func isInProgress(at now: Date) -> Bool {
        contains(now)
    }

    /// The whole week or month before this one — one page back.
    ///
    /// Not `previous`: that is what a period is *compared* with, and for a
    /// period in progress it is cut to the same number of days. Paging back
    /// shows the whole of the period before.
    public func earlier(calendar: Calendar = .iso8601Monday) -> RecapPeriod {
        Self.period(kind, containing: start.addingTimeInterval(-1), calendar: calendar)
    }

    /// The week or month after this one, or `nil` when this one is in
    /// progress: there is nothing to page to past today. The page that holds
    /// today is the period in progress, cut at today.
    public func later(at now: Date, calendar: Calendar = .iso8601Monday) -> RecapPeriod? {
        guard !isInProgress(at: now) else { return nil }
        let next = Self.period(kind, containing: end, calendar: calendar)
        guard next.start <= now else { return nil }
        return next.contains(now) ? Self.current(kind, at: now, calendar: calendar) : next
    }

    /// The oldest page the Bilan reaches for `kind` at `now`: the one holding
    /// the 1st of the month `historyMonths - 1` months ago.
    public static func earliest(_ kind: Kind, at now: Date, calendar: Calendar = .iso8601Monday) -> RecapPeriod {
        let thisMonth = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
        let first = calendar.date(byAdding: .month, value: -(historyMonths - 1), to: thisMonth) ?? thisMonth
        return period(kind, containing: first, calendar: calendar)
    }

    /// Whether there is a page before this one within the history.
    public func hasEarlier(at now: Date, calendar: Calendar = .iso8601Monday) -> Bool {
        start > Self.earliest(kind, at: now, calendar: calendar).start
    }

    /// The last period of `kind` to have ended before `now`.
    ///
    /// The calendar is ISO, Monday first, like every week the app draws: a
    /// recap that cut its weeks on Sunday would disagree with the home's bars.
    public static func lastCompleted(_ kind: Kind, before now: Date, calendar: Calendar = .iso8601Monday) -> RecapPeriod {
        let current = calendar.dateInterval(of: kind.component, for: now)
            ?? DateInterval(start: calendar.startOfDay(for: now), duration: 0)
        return period(kind, containing: current.start.addingTimeInterval(-1), calendar: calendar)
    }

    /// The week in progress, Monday through today — the Bilan's week (issue
    /// #363). Its totals are the days lived; `daysToCome` are the rest.
    public static func weekSoFar(at now: Date, calendar: Calendar = .iso8601Monday) -> RecapPeriod {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let monday = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        return RecapPeriod(kind: .week, start: monday, end: tomorrow)
    }

    /// The days of a period in progress still to come, through Sunday or the
    /// month's last day: drawn, never counted. Empty for a period already over.
    public func daysToCome(calendar: Calendar = .iso8601Monday) -> [Date] {
        guard let whole = calendar.dateInterval(of: kind.component, for: start) else { return [] }
        var days: [Date] = []
        var cursor = calendar.startOfDay(for: end)
        while cursor < whole.end {
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
    /// → Saturday for a week in progress — a fair comparison either way.
    ///
    /// For a month, the calendar month before; for a month in progress, the
    /// same number of days from the 1st of the month before (issue #444), cut
    /// at that month's end. The 12th compares to the 12 first days of the
    /// month before, never to a whole month it could only fall short of.
    public func previous(calendar: Calendar = .iso8601Monday) -> RecapPeriod {
        switch kind {
        case .week:
            let earlier: (Date) -> Date = { calendar.date(byAdding: .day, value: -7, to: $0) ?? $0 }
            return RecapPeriod(kind: kind, start: earlier(start), end: earlier(end))
        case .month:
            let before = earlier(calendar: calendar)
            guard daysToCome(calendar: calendar).isEmpty == false else { return before }
            let length = calendar.dateComponents([.day], from: start, to: end).day ?? 0
            let cut = calendar.date(byAdding: .day, value: length, to: before.start) ?? before.end
            return RecapPeriod(kind: kind, start: before.start, end: min(cut, before.end))
        }
    }

    public func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }

    /// Each day of the period, as day starts, in order.
    public func days(calendar: Calendar = .iso8601Monday) -> [Date] {
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
    public var title: String {
        switch kind {
        case .week: span
        case .month: Self.monthFormatter.string(from: start).capitalized(with: Self.french)
        }
    }

    /// The days themselves, whatever the kind: « Du 1 sept. au 13 sept. », or
    /// « Le 5 oct. » for a single day — what a comparison is made with (issue
    /// #454).
    public var span: String {
        let last = end.addingTimeInterval(-1)
        let first = Self.dayFormatter.string(from: start)
        guard !Calendar.iso8601Monday.isDate(start, inSameDayAs: last) else { return "Le \(first)" }
        return "Du \(first) au \(Self.dayFormatter.string(from: last))"
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

    public init(
        kind: Kind,
        start: Date,
        end: Date
    ) {
        self.kind = kind
        self.start = start
        self.end = end
    }
}
