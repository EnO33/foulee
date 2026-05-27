import Foundation

/// Hour+minute pair, calendar-agnostic. Encoded as `hour * 60 + minute` in
/// UserDefaults so a single `Int` round-trips cleanly.
struct TimeOfDay: Equatable, Hashable, Sendable, Codable {
    var hour: Int
    var minute: Int

    static let middayWindowStart = TimeOfDay(hour: 11, minute: 30)
    static let middayWindowEnd = TimeOfDay(hour: 13, minute: 30)

    var rawMinutes: Int {
        hour * 60 + minute
    }

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    init(rawMinutes: Int) {
        self.hour = (rawMinutes / 60) % 24
        self.minute = rawMinutes % 60
    }

    /// Bind to today's date for a `DatePicker` or scheduling call.
    func dateToday(calendar: Calendar = .current, now: Date = .now) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? now
    }
}
