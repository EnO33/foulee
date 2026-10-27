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
///
/// Until then it is also a row of the résumé (#479), under `sourceName`: the
/// outing was done, and the résumé is the record of what was done.
nonisolated public enum GarminPendingOutings {
    /// Where the résumé says the row comes from. The watch, not Santé: the
    /// detail has nothing more to read than the summary itself.
    static var sourceName: String { kitText("Montre Garmin") }

    /// Beyond the streak's own history window a pending outing can change
    /// nothing any more, and Garmin Connect has had more than enough time.
    public static let horizon: TimeInterval = TimeInterval(StreakCalculator.historyWindowDays) * 24 * 60 * 60

    /// `pending` with `summary` in it once, oldest first: the watch retries
    /// until it hears the phone got it, so the same outing can arrive twice.
    public static func adding(
        _ summary: GarminSessionSummary,
        to pending: [GarminSessionSummary]
    ) -> [GarminSessionSummary] {
        (pending.filter { $0.startedAt != summary.startedAt } + [summary])
            .sorted { $0.startedAt < $1.startedAt }
    }

    /// The outings Santé doesn't cover yet, and that are still within reach of
    /// the streak at `now`.
    public static func remaining(
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

    /// The clock the outings cover, for the minute count of `window`: an
    /// outing belongs to the window it starts in, as `ActiveMinutes` files a
    /// workout under the day it starts.
    public static func intervals(
        _ pending: [GarminSessionSummary],
        startingIn window: Range<Date>
    ) -> [ActiveMinutes.WorkoutInterval] {
        pending.filter { window.contains($0.startedAt) }.map(\.interval)
    }

    /// The outings of `window`, as the résumé lists a Santé workout.
    public static func workouts(
        _ pending: [GarminSessionSummary],
        startingIn window: Range<Date>
    ) -> [WorkoutSummary] {
        pending.filter { window.contains($0.startedAt) }.map(workout(of:))
    }

    /// The route of the pending outing `workout` stands for, as the detail's
    /// map draws it: none for a Santé workout, or an outing without a route.
    public static func route(of workout: WorkoutSummary, in pending: [GarminSessionSummary]) -> [RouteSegment] {
        guard isPending(workout),
              let outing = pending.first(where: { $0.startedAt == workout.startedAt }),
              outing.route.count > 1 else { return [] }
        return [RouteSegment(id: workout.id, activity: workout.activity, coordinates: outing.route)]
    }

    /// Whether `workout` is a pending outing rather than a Santé workout.
    public static func isPending(_ workout: WorkoutSummary) -> Bool {
        workout.sourceName == sourceName
    }

    private static func workout(of outing: GarminSessionSummary) -> WorkoutSummary {
        WorkoutSummary(
            id: id(of: outing),
            startedAt: outing.startedAt,
            endedAt: outing.endedAt,
            durationSeconds: outing.durationSeconds,
            distanceKm: Double(outing.distanceMeters) / 1_000,
            activeCalories: 0,
            steps: outing.steps,
            elevationMeters: Double(outing.ascentMeters),
            descentMeters: Double(outing.descentMeters),
            sourceName: sourceName,
            activity: RecordedActivity(rawValue: outing.activity.rawValue) ?? .other
        )
    }

    /// Stable from one read to the next, so SwiftUI keeps the row: made of the
    /// start, which already identifies the outing.
    private static func id(of outing: GarminSessionSummary) -> UUID {
        let start = withUnsafeBytes(of: outing.startedAt.timeIntervalSince1970.bitPattern.bigEndian, Array.init)
        return UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, start[0], start[1], start[2], start[3], start[4], start[5], start[6], start[7]))
    }
}
