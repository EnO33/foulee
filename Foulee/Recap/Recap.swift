import Foundation

/// A week or a month in review (issue #344).
///
/// Pure: built from what the home already reads from Santé — the merged daily
/// minutes, the daily series, the workouts — so every figure here is one the
/// rest of the app would give for the same days.
struct Recap: Equatable, Sendable {
    struct Totals: Equatable, Sendable {
        var minutes = 0
        var steps = 0
        var distanceKm: Double = 0
        var calories = 0
        /// Outings, counted like the résumé counts them: the legs of one
        /// outing are one, and a Strava copy of a watch session is the same.
        var outings = 0
    }

    var period: RecapPeriod
    var totals: Totals
    /// The period before, for the comparison.
    var previous: Totals
    /// Every day of the period, zero-filled, in order.
    var days: [DailyMinutes]
    var goalMinutes: Int
    /// Active days of the period on which the minutes goal was reached.
    var goalDaysMet: Int
    /// Active days in the period — the ones the user planned to move on.
    var goalDaysPlanned: Int

    /// The day with the most minutes; `nil` for a period without any.
    var bestDay: DailyMinutes? {
        days.filter { $0.minutes > 0 }.max { $0.minutes < $1.minutes }
    }

    var isEmpty: Bool {
        totals.minutes == 0 && totals.steps == 0 && totals.outings == 0
    }

    /// What the recap is made of: Santé, read once for both periods.
    struct Inputs: Sendable {
        var minutes: [DailyMinutes] = []
        var steps: [MetricPoint] = []
        var distance: [MetricPoint] = []
        var calories: [MetricPoint] = []
        var workouts: [WorkoutSummary] = []
    }

    static func make(
        period: RecapPeriod,
        from inputs: Inputs,
        goalMinutes: Int,
        activeDays: Set<Weekday>,
        calendar: Calendar = .iso8601Monday
    ) -> Recap {
        let minutes = inputs.minutes
        let byDay = Dictionary(minutes.map { (calendar.startOfDay(for: $0.date), $0.minutes) }) { first, _ in first }
        let days = period.days(calendar: calendar).map { DailyMinutes(date: $0, minutes: byDay[$0] ?? 0) }
        // No active day chosen means every day, as for the streak.
        let weekdays = activeDays.isEmpty ? Set(1...7) : activeDays.calendarWeekdays
        let planned = days.filter { weekdays.contains(calendar.component(.weekday, from: $0.date)) }
        // Grouped before deduplicated, the résumé's order (`OutingGrouping`).
        let outings = WorkoutDeduplication.collapsingOverlaps(OutingGrouping.groupingLegs(inputs.workouts))

        func totals(in range: RecapPeriod) -> Totals {
            func sum(_ points: [MetricPoint]) -> Double {
                points.filter { range.contains($0.date) }.map(\.value).reduce(0, +)
            }
            return Totals(
                minutes: minutes.filter { range.contains($0.date) }.map(\.minutes).reduce(0, +),
                steps: Int(sum(inputs.steps).rounded()),
                distanceKm: sum(inputs.distance),
                calories: Int(sum(inputs.calories).rounded()),
                outings: outings.filter { range.contains($0.startedAt) }.count
            )
        }

        return Recap(
            period: period,
            totals: totals(in: period),
            previous: totals(in: period.previous(calendar: calendar)),
            days: days,
            goalMinutes: goalMinutes,
            goalDaysMet: planned.filter { $0.minutes >= goalMinutes }.count,
            goalDaysPlanned: planned.count
        )
    }

    /// The change from `old` to `new`, as a fraction: 0.12 for +12 %. `nil`
    /// when there was nothing before — « +∞ % » says nothing.
    static func change(from old: Double, to new: Double) -> Double? {
        guard old > 0 else { return nil }
        return (new - old) / old
    }
}
