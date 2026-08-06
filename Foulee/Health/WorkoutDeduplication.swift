import Foundation

/// Collapses one outing written by several sources into one row of the 7-day
/// résumé (issue #218).
///
/// A runner routinely has three writers into Santé at once — the Apple Watch,
/// Garmin Connect, Strava — each saving its own `HKWorkout` for the same
/// outing. Grouping by day alone listed that outing twice or three times, once
/// per writer. #217 widened the résumé from walks to runs and hikes, which
/// turned the multi-writer case from an exception into the common one.
///
/// The rule is the one the minute count has followed since #183: sessions
/// covering the same clock are one session, never a sum. The overlap predicate
/// is `ActiveMinutes.overlap` itself rather than a copy — a second, subtly
/// different definition of "the same session" living here is exactly the defect
/// this fixes, one level up.
///
/// Pure and total: same input, same output, always.
enum WorkoutDeduplication {
    /// One row per stretch of clock actually exercised, newest first.
    ///
    /// **Which source shows its label and its numbers** when rows merge: the
    /// longest session, the earliest on a tie, the lowest sample id if two tie
    /// on both. Longest first because the writer that captured more of the
    /// outing describes it best (a phone that joined late, a watch whose
    /// auto-pause cut the tail). The two further tie-breaks exist so the order
    /// is *total*: two renders of the same data can never disagree.
    ///
    /// **A merged row covers the group's whole span**, not the winner's alone:
    /// `startedAt`, `endedAt` and `durationSeconds` become the union
    /// `min(start) ..< max(end)` — literally the range `unionedSpans` counted
    /// for the ring. Keeping the winner's own three fields looked harmless
    /// because a true duplicate contains its twin, but two writers whose clocks
    /// differ by a minute produce a *staggered* pair: a 08:00→08:45 run and a
    /// 08:44→09:20 cool-down merge, and showing only the 45-minute row hid 35
    /// minutes the streak had already been credited with. The row and the ring
    /// now agree by construction, on both the total and the day (the union
    /// starts when the earliest writer did, so `startOfDay` lands where
    /// `workoutMinutesByDay` filed it — even when the longest copy begins after
    /// midnight).
    ///
    /// **Nothing is summed.** The union is clock covered, never an addition:
    /// the staggered pair above renders 80 minutes, not 45 + 36. Distance,
    /// calories, steps and the sample id stay the winner's own, so the row
    /// never claims kilometres the user didn't run and the detail sheet can
    /// still read the sample back by id.
    ///
    /// **Distinct sessions stay distinct.** Only genuinely overlapping spans
    /// merge; two runs the same day, or a pair where one ends exactly when the
    /// next starts, remain two rows (see `ActiveMinutes.overlap`).
    static func collapsingOverlaps(_ workouts: [WorkoutSummary]) -> [WorkoutSummary] {
        var rows: [WorkoutSummary] = []
        var group: [WorkoutSummary] = []
        var groupSpan: Range<Date>?

        for workout in workouts.sorted(by: startsFirst) {
            guard let span = span(of: workout) else {
                // A zero-length session covers no clock, so it overlaps
                // nothing — it keeps its own row rather than vanishing.
                rows.append(workout)
                continue
            }
            if let current = groupSpan, ActiveMinutes.overlap(current, span) {
                group.append(workout)
                // Extend, don't replace: a chain A∩B, B∩C collapses to one row
                // even when A and C don't touch, exactly as `unionedSpans`
                // merges it into one span for the minutes.
                groupSpan = current.lowerBound..<max(current.upperBound, span.upperBound)
                continue
            }
            rows.append(contentsOf: representative(of: group, covering: groupSpan))
            group = [workout]
            groupSpan = span
        }
        rows.append(contentsOf: representative(of: group, covering: groupSpan))

        // Sorted here rather than trusted from the query: the sweep above walks
        // the sessions in start order, and the sheet lists them newest first.
        return rows.sorted { startsFirst($1, $0) }
    }

    /// The stretch of clock a session covers — built through
    /// `ActiveMinutes.span(of:)` so it is literally the span the ring counted.
    private static func span(of workout: WorkoutSummary) -> Range<Date>? {
        ActiveMinutes.span(of: ActiveMinutes.WorkoutInterval(
            start: workout.startedAt,
            duration: workout.durationSeconds
        ))
    }

    /// A total order over sessions by start time. The tie-breaks (longest
    /// first, then sample id) never change *which* rows survive — they only
    /// make the sweep, and the list it produces, reproducible.
    private static func startsFirst(_ lhs: WorkoutSummary, _ rhs: WorkoutSummary) -> Bool {
        (lhs.startedAt, -lhs.durationSeconds, lhs.id.uuidString)
            < (rhs.startedAt, -rhs.durationSeconds, rhs.id.uuidString)
    }

    /// The one row a merged group shows, stretched over `span`, or nothing for
    /// an empty group.
    ///
    /// A group of one is returned untouched: its `endedAt` is the sample's real
    /// end date, which for a paused workout sits *after* `start + duration`,
    /// and the résumé's time range should keep showing the wall clock the user
    /// remembers. Only a group that actually merged is rewritten, and then to
    /// the span the ring counted — see `collapsingOverlaps`.
    private static func representative(
        of group: [WorkoutSummary],
        covering span: Range<Date>?
    ) -> [WorkoutSummary] {
        guard var row = group.min(by: isPreferred) else { return [] }
        guard group.count > 1, let span else { return [row] }
        row.startedAt = span.lowerBound
        row.endedAt = span.upperBound
        row.durationSeconds = span.upperBound.timeIntervalSince(span.lowerBound)
        return [row]
    }

    /// Longest wins; earliest breaks a tie on duration; the sample id breaks a
    /// tie on both. Negating the duration turns "longest" into "smallest" so
    /// the whole rule reads as one tuple comparison.
    private static func isPreferred(_ lhs: WorkoutSummary, over rhs: WorkoutSummary) -> Bool {
        (-lhs.durationSeconds, lhs.startedAt, lhs.id.uuidString)
            < (-rhs.durationSeconds, rhs.startedAt, rhs.id.uuidString)
    }
}
