import Foundation

/// Outings saved on the Garmin watch that Santé doesn't have yet (ADR 0009,
/// D2). Garmin Connect writes them there in its own time; until it does, the
/// summary the watch sent stands in for the workout. Pure Foundation, like
/// `GarminSnapshotOverlay`, so the whole rule is testable without a watch.
///
/// Three rules, the overlay's own:
///
/// 1. **Nothing here is written to HealthKit.** Garmin Connect writes the same
///    outing later, and a sample of ours would sit next to it for good.
/// 2. **Never added, always unioned.** A pending outing is one more workout
///    interval in the minute count (`ActiveMinutes`), which unions overlapping
///    sessions: the day Garmin Connect's copy lands, the two cover the same
///    clock and count once. It is how the outing counts for the streak without
///    any chance of counting twice.
/// 3. **It goes as soon as Santé covers it** — any workout overlapping it, the
///    test `WorkoutDeduplication` merges rows by — or once older than the
///    streak can reach.
nonisolated enum GarminPendingOutings {
    /// Beyond the streak's own history window a pending outing can change
    /// nothing any more, and Garmin Connect has had more than enough time.
    static let horizon: TimeInterval = TimeInterval(StreakCalculator.historyWindowDays) * 24 * 60 * 60

    /// `pending` with `summary` in it once, oldest first: the watch retries
    /// until it hears the phone got it, so the same outing can arrive twice.
    static func adding(
        _ summary: GarminSessionSummary,
        to pending: [GarminSessionSummary]
    ) -> [GarminSessionSummary] {
        (pending.filter { $0.startedAt != summary.startedAt } + [summary])
            .sorted { $0.startedAt < $1.startedAt }
    }

    /// The outings Santé doesn't cover yet, and that are still within reach of
    /// the streak at `now`.
    static func remaining(
        _ pending: [GarminSessionSummary],
        healthKitWorkouts: [ActiveMinutes.WorkoutInterval],
        now: Date
    ) -> [GarminSessionSummary] {
        let covered = healthKitWorkouts.compactMap(ActiveMinutes.span(of:))
        return pending.filter { outing in
            guard now.timeIntervalSince(outing.startedAt) < horizon else { return false }
            guard let span = ActiveMinutes.span(of: outing.interval) else { return false }
            return !covered.contains { ActiveMinutes.overlap($0, span) }
        }
    }
}
