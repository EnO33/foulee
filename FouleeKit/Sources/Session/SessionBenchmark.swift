import Foundation

/// Where one outing stands against the six months before it (issue #526).
///
/// The figures the session notification (#525) picks its one line from:
/// pace against the usual, the trend of the last four weeks, the records, the
/// volume of the week and the month. Nothing is chosen here — only measured —
/// so the choice can be tested apart (#527).
///
/// Pure: built from the workouts Santé already gives the résumé, grouped and
/// deduplicated as the résumé does, so an outing here is one row there.
nonisolated struct SessionBenchmark: Equatable, Sendable {
    /// The outing's pace against the earlier outings of the same sport.
    nonisolated struct Pace: Equatable, Sendable {
        /// The outing's own, in seconds per kilometre.
        var current: TimeInterval
        /// Earlier outings of the same sport that have a pace, in the window.
        var sessions: Int
        /// Their average, weighted by distance: one long walk weighs more
        /// than a short one, as it does in the legs.
        var average: TimeInterval?
        /// Their fastest.
        var best: TimeInterval?
        /// The last four weeks, the outing included.
        var recent: TimeInterval?
        var recentSessions: Int
        /// The rest of the window, before those four weeks.
        var earlier: TimeInterval?
        var earlierSessions: Int
    }

    /// The best earlier outings of the same sport, in the window.
    nonisolated struct Records: Equatable, Sendable {
        /// Earlier outings of the same sport.
        var sessions: Int
        var longestKm: Double?
        var highestElevationMeters: Double?
    }

    /// Every sport together: the week and the month the outing falls in, up
    /// to it, against the whole week and month before.
    nonisolated struct Volume: Equatable, Sendable {
        /// Outings this week, this one included.
        var outingsThisWeek: Int
        var minutesThisWeek: Int
        var minutesLastWeek: Int
        var kmThisMonth: Double
        var kmLastMonth: Double
        /// The first day of last month, to name it.
        var lastMonth: Date
    }

    var outing: WorkoutSummary
    /// The sport compared on, `nil` for an outing that changed sport: a walk
    /// and run together has no « usual » to stand against.
    var activity: RecordedActivity?
    /// `nil` when pace says nothing: a hike, a mixed outing, a short one.
    var pace: Pace?
    /// `nil` for a mixed outing.
    var records: Records?
    var volume: Volume

    /// How far back « the usual » reaches.
    static let windowMonths = 6
    /// What « lately » covers, for the trend.
    static let recentDays = 28
    /// Below this, a GPS-less distance makes the pace a guess.
    static let minimumPaceKm = 1.0
    /// Paces outside this range, in s/km, are a measurement gone wrong or a
    /// pause someone forgot to end — not a pace.
    static let plausiblePace: ClosedRange<TimeInterval> = 120...2_400

    /// `outing` against `workouts`: Santé's, as read for the résumé — legs and
    /// copies are grouped here, and the outing's own rows set aside.
    static func make(
        for outing: WorkoutSummary,
        among workouts: [WorkoutSummary],
        calendar: Calendar = .iso8601Monday
    ) -> SessionBenchmark {
        let others = WorkoutDeduplication.collapsingOverlaps(OutingGrouping.groupingLegs(workouts))
            .filter { !covers($0, outing) }
        let windowStart = calendar.date(byAdding: .month, value: -windowMonths, to: outing.startedAt)
            ?? outing.startedAt
        let earlier = others.filter { (windowStart..<outing.startedAt).contains($0.startedAt) }
        let activity = outing.activities.count == 1 ? outing.activity : nil
        let sameSport = activity.map { sport in earlier.filter { $0.activities == [sport] } } ?? []

        return SessionBenchmark(
            outing: outing,
            activity: activity,
            pace: activity.flatMap { pace(of: outing, as: $0, against: sameSport, calendar: calendar) },
            records: activity.map { _ in
                Records(
                    sessions: sameSport.count,
                    longestKm: sameSport.map(\.distanceKm).max(),
                    highestElevationMeters: sameSport.map(\.elevationMeters).max()
                )
            },
            volume: volume(of: outing, among: others, calendar: calendar)
        )
    }

    /// Seconds per kilometre, or `nil` when the outing has no pace worth
    /// stating.
    static func pace(of outing: WorkoutSummary) -> TimeInterval? {
        guard outing.distanceKm >= minimumPaceKm else { return nil }
        let pace = outing.durationSeconds / outing.distanceKm
        return plausiblePace.contains(pace) ? pace : nil
    }

    private static func pace(
        of outing: WorkoutSummary,
        as activity: RecordedActivity,
        against earlier: [WorkoutSummary],
        calendar: Calendar
    ) -> Pace? {
        // A hike is told by its distance and its climb: its pace depends on
        // the slope more than on the walker.
        guard activity != .hiking, let current = pace(of: outing) else { return nil }
        let paced = earlier.filter { pace(of: $0) != nil }
        let recentStart = calendar.date(byAdding: .day, value: -recentDays, to: outing.startedAt) ?? outing.startedAt
        let recent = paced.filter { $0.startedAt >= recentStart } + [outing]
        let before = paced.filter { $0.startedAt < recentStart }
        return Pace(
            current: current,
            sessions: paced.count,
            average: averagePace(of: paced),
            best: paced.compactMap(pace(of:)).min(),
            recent: averagePace(of: recent),
            recentSessions: recent.count,
            earlier: averagePace(of: before),
            earlierSessions: before.count
        )
    }

    /// Total time over total distance: the pace of all of them run end to end.
    private static func averagePace(of outings: [WorkoutSummary]) -> TimeInterval? {
        let km = outings.map(\.distanceKm).reduce(0, +)
        guard km > 0 else { return nil }
        return outings.map(\.durationSeconds).reduce(0, +) / km
    }

    private static func volume(
        of outing: WorkoutSummary,
        among others: [WorkoutSummary],
        calendar: Calendar
    ) -> Volume {
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: outing.startedAt)
        let thisMonth = calendar.dateInterval(of: .month, for: outing.startedAt)
        let lastWeek = thisWeek.flatMap { calendar.dateInterval(of: .weekOfYear, for: $0.start.addingTimeInterval(-1)) }
        let lastMonth = thisMonth.flatMap { calendar.dateInterval(of: .month, for: $0.start.addingTimeInterval(-1)) }
        // Up to the outing: a notification read late must not count what came
        // after it.
        let upToOuting = others.filter { $0.startedAt < outing.startedAt } + [outing]

        func outings(in interval: DateInterval?, from rows: [WorkoutSummary]) -> [WorkoutSummary] {
            guard let interval else { return [] }
            return rows.filter { interval.start <= $0.startedAt && $0.startedAt < interval.end }
        }
        func minutes(_ rows: [WorkoutSummary]) -> Int {
            Int((rows.map(\.durationSeconds).reduce(0, +) / 60).rounded())
        }
        let week = outings(in: thisWeek, from: upToOuting)
        return Volume(
            outingsThisWeek: week.count,
            minutesThisWeek: minutes(week),
            minutesLastWeek: minutes(outings(in: lastWeek, from: others)),
            kmThisMonth: outings(in: thisMonth, from: upToOuting).map(\.distanceKm).reduce(0, +),
            kmLastMonth: outings(in: lastMonth, from: others).map(\.distanceKm).reduce(0, +),
            lastMonth: lastMonth?.start ?? outing.startedAt
        )
    }

    /// Whether `row` is the outing itself, or a copy of it from another
    /// writer: any overlap of their clocks, the résumé's own test.
    private static func covers(_ row: WorkoutSummary, _ outing: WorkoutSummary) -> Bool {
        row.id == outing.id || (row.startedAt < outing.endedAt && outing.startedAt < row.endedAt)
    }
}
