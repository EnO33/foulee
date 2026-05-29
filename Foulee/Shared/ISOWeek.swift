import Foundation

extension Calendar {
    /// An ISO-8601 calendar pinned to Monday as the first weekday — matches
    /// the `L M M J V S D` labels the Today and Stats week views render.
    static var iso8601Monday: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2 // Monday (defensive: matches ISO 8601)
        return calendar
    }
}

enum ISOWeek {
    /// The seven day-start `Date`s, Monday → Sunday, of the ISO week
    /// containing `reference`. Returns an empty array only if calendar math
    /// fails (it doesn't in practice).
    static func days(containing reference: Date, calendar: Calendar = .iso8601Monday) -> [Date] {
        let today = calendar.startOfDay(for: reference)
        let weekday = calendar.component(.weekday, from: today)
        // ISO weekday: 1 = Sunday → 6 days back, 2 = Monday → 0, etc.
        let mondayOffset = -((weekday + 5) % 7)
        guard let monday = calendar.date(byAdding: .day, value: mondayOffset, to: today) else {
            return []
        }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }
}
