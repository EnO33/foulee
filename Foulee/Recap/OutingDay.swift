import Foundation

/// One day of a recap and the outings filed under it — what the Bilan shows
/// when a day is picked (issues #218, #317, #348, #350).
struct OutingDay: Identifiable, Equatable, Sendable {
    let day: Date
    let workouts: [WorkoutSummary]

    var id: Date { day }

    /// Every day of `period`, in order, each holding the deduplicated outings
    /// that began on it, newest first (issue #361).
    ///
    /// Taking its calendar as a parameter, so a test can reach it (#218). The
    /// order below is what the tests on `WorkoutDeduplication` and
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
    static func days(in period: RecapPeriod, from workouts: [WorkoutSummary], calendar: Calendar = .iso8601Monday) -> [OutingDay] {
        let outings = WorkoutDeduplication.collapsingOverlaps(OutingGrouping.groupingLegs(workouts))
        let byDay = Dictionary(grouping: outings) { calendar.startOfDay(for: $0.startedAt) }
        return period.days(calendar: calendar).map { day in
            OutingDay(day: day, workouts: (byDay[day] ?? []).sorted { $0.startedAt > $1.startedAt })
        }
    }
}
