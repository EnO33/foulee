import Foundation

/// A week or a month in review (issue #344).
///
/// Pure: built from what the home already reads from Santé — the merged daily
/// minutes, the daily series, the workouts — so every figure here is one the
/// rest of the app would give for the same days.
nonisolated public struct Recap: Equatable, Sendable {
    nonisolated public struct Totals: Equatable, Sendable {
        public var minutes = 0
        public var steps = 0
        public var distanceKm: Double = 0
        public var calories = 0
        /// Outings, counted like the résumé counts them: the legs of one
        /// outing are one, and a Strava copy of a watch session is the same.
        public var outings = 0
        /// The outings' climb, in metres (issue #537): summed from the
        /// outings rather than a daily series, Santé having none for it. An
        /// outing whose source wrote no climb adds nothing.
        public var climbMeters: Double = 0

        public init(
            minutes: Int = 0,
            steps: Int = 0,
            distanceKm: Double = 0,
            calories: Int = 0,
            outings: Int = 0,
            climbMeters: Double = 0
        ) {
            self.minutes = minutes
            self.steps = steps
            self.distanceKm = distanceKm
            self.calories = calories
            self.outings = outings
            self.climbMeters = climbMeters
        }
    }

    /// One day of the period.
    nonisolated public struct Day: Equatable, Sendable, Identifiable {
        public var date: Date
        public var minutes: Int
        /// An active day — one the user planned to move on. The others are
        /// rest days: drawn as such, and never counted as missed.
        public var isPlanned: Bool

        public var id: Date { date }

        public init(
            date: Date,
            minutes: Int,
            isPlanned: Bool
        ) {
            self.date = date
            self.minutes = minutes
            self.isPlanned = isPlanned
        }
    }

    /// What the period says, in one sentence — the first thing read.
    nonisolated public enum Verdict: Equatable, Sendable {
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

    public var period: RecapPeriod
    public var totals: Totals
    /// The period before, for the comparison.
    public var previous: Totals
    /// Every day of the period, zero-filled, in order.
    public var days: [Day]
    public var goalMinutes: Int
    /// Active days of the period on which the minutes goal was reached.
    public var goalDaysMet: Int
    /// Active days in the period — the ones the user planned to move on.
    public var goalDaysPlanned: Int

    /// The day with the most minutes; `nil` for a period without any.
    public var bestDay: Day? {
        days.filter { $0.minutes > 0 }.max { $0.minutes < $1.minutes }
    }

    /// Share of the planned days on which the goal held, `0...1`.
    public var goalRate: Double {
        goalDaysPlanned > 0 ? Double(goalDaysMet) / Double(goalDaysPlanned) : 0
    }

    /// Most telling first: a perfect period says so even if it did fewer
    /// minutes than the one before; regularity outranks volume, because the
    /// streak is what the app is about.
    public var verdict: Verdict {
        if isEmpty { return .quiet }
        if goalDaysPlanned > 0, goalDaysMet == goalDaysPlanned { return .perfect }
        if goalRate >= Self.steadyRate { return .steady }
        if let change = Self.change(from: Double(previous.minutes), to: Double(totals.minutes)), change > 0 {
            return .improving
        }
        return .started
    }

    /// From this share of planned days held, a period reads as regular.
    public static let steadyRate = 0.7

    public var isEmpty: Bool {
        totals.minutes == 0 && totals.steps == 0 && totals.outings == 0
    }

    /// What the recap is made of: Santé, read once for both periods.
    nonisolated public struct Inputs: Sendable {
        public var minutes: [DailyMinutes] = []
        public var steps: [MetricPoint] = []
        public var distance: [MetricPoint] = []
        public var calories: [MetricPoint] = []
        public var workouts: [WorkoutSummary] = []

        public init(
            minutes: [DailyMinutes] = [],
            steps: [MetricPoint] = [],
            distance: [MetricPoint] = [],
            calories: [MetricPoint] = [],
            workouts: [WorkoutSummary] = []
        ) {
            self.minutes = minutes
            self.steps = steps
            self.distance = distance
            self.calories = calories
            self.workouts = workouts
        }
    }

    public static func make(
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
            let periodOutings = outings.filter { range.contains($0.startedAt) }
            return Totals(
                minutes: minutes.filter { range.contains($0.date) }.map(\.minutes).reduce(0, +),
                steps: Int(sum(inputs.steps).rounded()),
                distanceKm: sum(inputs.distance),
                calories: Int(sum(inputs.calories).rounded()),
                outings: periodOutings.count,
                climbMeters: periodOutings.map(\.elevationMeters).reduce(0, +)
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
    public static func change(from old: Double, to new: Double) -> Double? {
        guard old > 0 else { return nil }
        return (new - old) / old
    }

    /// What is left for `new` to match `old`, or `nil` once it has: how a
    /// period still in progress reads against the one before, rather than as
    /// a drop it may yet make up (issue #454).
    public static func remaining(from new: Double, toMatch old: Double) -> Double? {
        old > new ? old - new : nil
    }

    public init(
        period: RecapPeriod,
        totals: Totals,
        previous: Totals,
        days: [Day],
        goalMinutes: Int,
        goalDaysMet: Int,
        goalDaysPlanned: Int
    ) {
        self.period = period
        self.totals = totals
        self.previous = previous
        self.days = days
        self.goalMinutes = goalMinutes
        self.goalDaysMet = goalDaysMet
        self.goalDaysPlanned = goalDaysPlanned
    }
}
