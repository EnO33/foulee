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

    /// One day of the period.
    struct Day: Equatable, Sendable, Identifiable {
        var date: Date
        var minutes: Int
        /// An active day — one the user planned to move on. The others are
        /// rest days: drawn as such, and never counted as missed.
        var isPlanned: Bool

        var id: Date { date }
    }

    /// What the period says, in one sentence — the first thing read.
    enum Verdict: Equatable, Sendable {
        /// Nothing recorded.
        case quiet
        /// The goal held on every planned day.
        case perfect
        /// The goal held on most planned days.
        case steady
        /// More minutes than the period before.
        case improving
        /// Something was done; next time, a day more.
        case started
    }

    var period: RecapPeriod
    var totals: Totals
    /// The period before, for the comparison.
    var previous: Totals
    /// Every day of the period, zero-filled, in order.
    var days: [Day]
    var goalMinutes: Int
    /// Active days of the period on which the minutes goal was reached.
    var goalDaysMet: Int
    /// Active days in the period — the ones the user planned to move on.
    var goalDaysPlanned: Int

    /// The day with the most minutes; `nil` for a period without any.
    var bestDay: Day? {
        days.filter { $0.minutes > 0 }.max { $0.minutes < $1.minutes }
    }

    /// Share of the planned days on which the goal held, `0...1`.
    var goalRate: Double {
        goalDaysPlanned > 0 ? Double(goalDaysMet) / Double(goalDaysPlanned) : 0
    }

    /// Most telling first: a perfect period says so even if it did fewer
    /// minutes than the one before; regularity outranks volume, because the
    /// streak is what the app is about.
    var verdict: Verdict {
        if isEmpty { return .quiet }
        if goalDaysPlanned > 0, goalDaysMet == goalDaysPlanned { return .perfect }
        if goalRate >= Self.steadyRate { return .steady }
        if let change = Self.change(from: Double(previous.minutes), to: Double(totals.minutes)), change > 0 {
            return .improving
        }
        return .started
    }

    /// From this share of planned days held, a period reads as regular.
    static let steadyRate = 0.7

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
        // No active day chosen means every day, as for the streak.
        let weekdays = activeDays.isEmpty ? Set(1...7) : activeDays.calendarWeekdays
        let days = period.days(calendar: calendar).map {
            Day(date: $0, minutes: byDay[$0] ?? 0, isPlanned: weekdays.contains(calendar.component(.weekday, from: $0)))
        }
        let planned = days.filter(\.isPlanned)
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
