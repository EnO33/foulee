import Foundation

/// The week so far, Monday to today, for the home's « Semaine » tab (issue
/// #327).
///
/// Pas, distance and calories: daily HealthKit series summed from Monday.
/// Minutes are not here on purpose — the tab sums `weekMinutes`, the merged
/// per-day figures the week bars and the streak already use, so the total and
/// the bars under it can never disagree.
struct WeekTotals: Equatable, Sendable {
    var steps: Int
    var distanceKm: Double
    var calories: Int

    /// Days from Monday to `today`, both included: 1 on a Monday, 7 on a
    /// Sunday — how far back the daily series must reach.
    static func daysSoFar(at today: Date, calendar: Calendar = .iso8601Monday) -> Int {
        let start = calendar.startOfDay(for: today)
        let index = ISOWeek.days(containing: today, calendar: calendar).firstIndex(of: start) ?? 6
        return index + 1
    }

    /// Sum `points` from this week's Monday on. Points from before it — a
    /// series asked for a day too many — are left out rather than counted.
    static func sum(_ points: [MetricPoint], weekOf today: Date, calendar: Calendar = .iso8601Monday) -> Double {
        guard let monday = ISOWeek.days(containing: today, calendar: calendar).first else { return 0 }
        return points.filter { $0.date >= monday }.map(\.value).reduce(0, +)
    }
}
