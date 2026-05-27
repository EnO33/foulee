import Foundation

/// Pure functions that turn a history of `DailyMinutes` into streak counts.
/// No HealthKit imports, no state — easy to test on any platform.
enum StreakCalculator {
    /// Count back from `today` while consecutive previous days reach
    /// `goalMinutes`. Today itself counts if it already meets the goal,
    /// otherwise the streak is read from yesterday backwards.
    static func current(
        history: [DailyMinutes],
        goalMinutes: Int,
        today: Date,
        calendar: Calendar = .current
    ) -> Int {
        let dayMap = Dictionary(
            uniqueKeysWithValues: history.map { (calendar.startOfDay(for: $0.date), $0.minutes) }
        )
        let startOfToday = calendar.startOfDay(for: today)

        var cursor = (dayMap[startOfToday] ?? 0) >= goalMinutes
            ? startOfToday
            : calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday

        var streak = 0
        while (dayMap[cursor] ?? 0) >= goalMinutes {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    /// Longest consecutive run of days where `minutes >= goalMinutes` in
    /// the entire history. Empty history → 0.
    static func best(
        history: [DailyMinutes],
        goalMinutes: Int,
        calendar: Calendar = .current
    ) -> Int {
        let sorted = history
            .map { DailyMinutes(date: calendar.startOfDay(for: $0.date), minutes: $0.minutes) }
            .sorted { $0.date < $1.date }

        var best = 0
        var current = 0
        var previousDay: Date?

        for entry in sorted {
            guard entry.minutes >= goalMinutes else {
                current = 0
                previousDay = entry.date
                continue
            }
            if let previous = previousDay,
               let expected = calendar.date(byAdding: .day, value: 1, to: previous),
               expected == entry.date {
                current += 1
            } else {
                current = 1
            }
            previousDay = entry.date
            best = max(best, current)
        }
        return best
    }
}
