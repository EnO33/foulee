import Foundation

/// Pure functions that turn a history of `DailyMinutes` into streak counts.
/// No HealthKit imports, no state — easy to test on any platform.
///
/// `activeWeekdays` uses `Calendar` weekday numbering (1 = Sunday … 7 =
/// Saturday). A **rest day** (a weekday not in the set) neither extends nor
/// breaks the streak — only a *missed active day* breaks it. The default of
/// every weekday keeps the "every single day" behaviour (used by the widgets,
/// which don't know the user's chosen days).
enum StreakCalculator {
    private static let everyDay: Set<Int> = [1, 2, 3, 4, 5, 6, 7]

    /// Count back from `today` over active days, skipping rest days, while each
    /// active day reaches `goalMinutes`. Today counts if it already meets the
    /// goal; an unfinished today doesn't break a streak that held yesterday.
    static func current(
        history: [DailyMinutes],
        goalMinutes: Int,
        activeWeekdays: Set<Int> = everyDay,
        today: Date,
        calendar: Calendar = .current
    ) -> Int {
        let active = activeWeekdays.isEmpty ? everyDay : activeWeekdays
        let dayMap = Dictionary(
            uniqueKeysWithValues: history.map { (calendar.startOfDay(for: $0.date), $0.minutes) }
        )
        let startOfToday = calendar.startOfDay(for: today)

        func isActive(_ date: Date) -> Bool { active.contains(calendar.component(.weekday, from: date)) }
        func met(_ date: Date) -> Bool { (dayMap[date] ?? 0) >= goalMinutes }

        var cursor = startOfToday
        // An active "today" that isn't done yet must not break the streak —
        // read it from yesterday backwards instead.
        if isActive(startOfToday), !met(startOfToday) {
            cursor = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        }

        // Never count past the history we actually have.
        let earliest = dayMap.keys.min() ?? startOfToday

        var streak = 0
        while cursor >= earliest {
            if isActive(cursor) {
                guard met(cursor) else { break } // a planned day was missed
                streak += 1
            }
            // rest day → skip without touching the streak
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    /// Longest run of consecutive active days meeting `goalMinutes` across the
    /// history, with rest days skipped. Empty history → 0.
    static func best(
        history: [DailyMinutes],
        goalMinutes: Int,
        activeWeekdays: Set<Int> = everyDay,
        calendar: Calendar = .current
    ) -> Int {
        let active = activeWeekdays.isEmpty ? everyDay : activeWeekdays
        let dayMap = Dictionary(
            uniqueKeysWithValues: history.map { (calendar.startOfDay(for: $0.date), $0.minutes) }
        )
        guard let earliest = dayMap.keys.min(), let latest = dayMap.keys.max() else { return 0 }

        var best = 0
        var current = 0
        var cursor = earliest
        while cursor <= latest {
            if active.contains(calendar.component(.weekday, from: cursor)) {
                if (dayMap[cursor] ?? 0) >= goalMinutes {
                    current += 1
                    best = max(best, current)
                } else {
                    current = 0
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return best
    }
}
