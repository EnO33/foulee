import Foundation

/// Hour+minute pair, calendar-agnostic. Encoded as `hour * 60 + minute` in
/// UserDefaults so a single `Int` round-trips cleanly.
nonisolated public struct TimeOfDay: Equatable, Hashable, Sendable, Codable {
    public var hour: Int
    public var minute: Int

    public static let middayWindowStart = TimeOfDay(hour: 11, minute: 30)
    public static let middayWindowEnd = TimeOfDay(hour: 13, minute: 30)

    public var rawMinutes: Int {
        hour * 60 + minute
    }

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public init(rawMinutes: Int) {
        self.hour = (rawMinutes / 60) % 24
        self.minute = rawMinutes % 60
    }

    public init(date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }

    /// Bind to today's date for a `DatePicker` or scheduling call.
    public func dateToday(calendar: Calendar = .current, now: Date = .now) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? now
    }
}

nonisolated public extension TimeOfDay {
    /// « 11:30 » — the same wall clock as `Date.clockText`, in the hours the
    /// device reads (issue #586).
    var clockText: String { DateComponents(hour: hour, minute: minute).clockText }
}

nonisolated public extension TimeOfDay {
    /// The shortest window — outing or hydration — the app accepts (#395).
    static let minimumWindowMinutes = 5

    /// `end`, pushed past `start` when a stored window is inverted or too
    /// short, so nothing downstream ever reads a window that ends before it
    /// begins. Capped at 23:59: windows never cross midnight.
    static func validEnd(_ end: TimeOfDay, after start: TimeOfDay) -> TimeOfDay {
        let earliest = start.rawMinutes + minimumWindowMinutes
        guard end.rawMinutes < earliest else { return end }
        return TimeOfDay(rawMinutes: min(start.rawMinutes + 60, 23 * 60 + 59))
    }
}
