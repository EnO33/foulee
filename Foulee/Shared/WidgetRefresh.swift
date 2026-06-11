import Foundation

/// Picks the next timeline-refresh date so the daily WidgetKit budget
/// (~40-70 reloads/day, system-imposed) is spent where it matters: tight during
/// waking hours, asleep overnight.
///
/// During the active window the next refresh lands on a rounded N-minute
/// boundary (08:00, 08:10, …) rather than `now + N`, so the iPhone widgets and
/// the Watch complications — which refresh at different instants — converge on
/// the *same* wall-clock slots and appear to move together. Outside the window
/// a single wake is requested at the next window start, so none of the budget
/// is burnt overnight when nobody is looking.
enum WidgetRefresh {
    /// Daytime cadence in minutes. The realistic floor is ~10-15: asking for
    /// less just gets throttled once the daily budget runs out. Tunable in one
    /// place if end-of-day gaps show up.
    static let daytimeStepMinutes = 10
    static let windowStartHour = 8
    static let windowEndHour = 20

    static func nextRefresh(after now: Date, calendar: Calendar = .current) -> Date {
        let hour = calendar.component(.hour, from: now)
        if hour >= windowStartHour, hour < windowEndHour {
            return nextDaytimeSlot(after: now, calendar: calendar)
        }
        return nextWindowStart(after: now, hour: hour, calendar: calendar)
    }

    /// The next rounded multiple of `daytimeStepMinutes` strictly after `now`.
    private static func nextDaytimeSlot(after now: Date, calendar: Calendar) -> Date {
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let target = (minute / daytimeStepMinutes + 1) * daytimeStepMinutes
        let topOfHour = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now) ?? now
        // `target` can be 60 (e.g. at :55) — adding minutes rolls into the next
        // hour, which is exactly what we want.
        return calendar.date(byAdding: .minute, value: target, to: topOfHour)
            ?? now.addingTimeInterval(TimeInterval(daytimeStepMinutes * 60))
    }

    /// `windowStartHour` today if we're before it, otherwise tomorrow.
    private static func nextWindowStart(after now: Date, hour: Int, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: now)
        let todayStart = calendar.date(byAdding: .hour, value: windowStartHour, to: startOfDay) ?? now
        if hour < windowStartHour { return todayStart }
        return calendar.date(byAdding: .day, value: 1, to: todayStart)
            ?? now.addingTimeInterval(8 * 60 * 60)
    }
}
