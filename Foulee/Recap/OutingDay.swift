import Foundation

/// One day of the last seven and the outings filed under it — the
/// « 7 derniers jours » view (issues #218, #317, #348).
struct OutingDay: Identifiable, Equatable, Sendable {
    let day: Date
    let workouts: [WorkoutSummary]

    var id: Date { day }

    /// How many days the view lists, today included.
    static let window = 7

    /// The view's days: `window` day-starts ending on `now`'s, newest first,
    /// each holding the deduplicated outings that began on it.
    ///
    /// Taking its calendar and clock as parameters, so a test can reach it
    /// (#218). The order below is what the tests on `WorkoutDeduplication` and
    /// `OutingGrouping` cannot see on their own:
    ///
    /// - **Legs are rejoined first** (#317): an outing must meet a copy of
    ///   itself from another writer as one session, or the copy would swallow
    ///   its first leg and leave the others as rows of their own.
    /// - **Then deduplicated, then grouped by day** (#218): the copies of one
    ///   outing come from different writers and can start seconds apart, so a
    ///   session begun just before midnight can have its twin recorded just
    ///   after. Grouping first would file them under two days, where neither
    ///   bucket would ever see the overlap.
    static func lastDays(from workouts: [WorkoutSummary], calendar: Calendar = .current, now: Date) -> [OutingDay] {
        let today = calendar.startOfDay(for: now)
        let dayStarts = (0..<window).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let outings = WorkoutDeduplication.collapsingOverlaps(OutingGrouping.groupingLegs(workouts))
        let byDay = Dictionary(grouping: outings) { calendar.startOfDay(for: $0.startedAt) }
        return dayStarts.map { OutingDay(day: $0, workouts: byDay[$0] ?? []) }
    }
}
