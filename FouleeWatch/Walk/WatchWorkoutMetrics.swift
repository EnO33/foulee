import Foundation

/// Live snapshot from `HKLiveWorkoutBuilder` — the view binds against
/// this. Heart rate is `nil` until the first sensor reading lands.
struct WatchWorkoutMetrics: Equatable, Sendable {
    var elapsed: TimeInterval
    var steps: Int
    var distanceMeters: Double
    var activeCalories: Int
    var heartRate: Int?
    /// What the watch says the wearer is doing right now (issue #250).
    ///
    /// Comes from the detection, not from HealthKit's segment list: the two
    /// agree in normal running, and when they do not it is because a
    /// `beginNewActivity` did not take — in which case naming the sport from
    /// the decision and the numbers from the recording makes the disagreement
    /// visible on screen (« Course » next to zeros) instead of hiding it.
    var activity: SessionActivity = .walking
    /// Everything measured while doing `activity`, since the session started —
    /// not since the last switch. See `WatchActivityTotals`.
    var activityTotals: WatchActivityTotals = .zero

    static let zero = WatchWorkoutMetrics(
        elapsed: 0,
        steps: 0,
        distanceMeters: 0,
        activeCalories: 0,
        heartRate: nil
    )

    /// The empty state of a session of `activity`. Distinct from `zero`, which
    /// has to name *some* activity and names the commoner one: a run opened at
    /// `zero` would read « Marche » for the second before the first metrics
    /// land.
    static func empty(for activity: SessionActivity) -> WatchWorkoutMetrics {
        var metrics = zero
        metrics.activity = activity
        return metrics
    }

    var distanceKm: Double { distanceMeters / 1_000 }

    /// « Course · 12:04 » — the sport being done and how long it has added up
    /// to across the session.
    var activityHeadlineText: String {
        "\(activity.label) · \(activityTotals.elapsed.walkClockText)"
    }

    /// One sentence naming the current activity and its running totals, for
    /// VoiceOver (issue #250).
    ///
    /// Six values read out one by one say nothing about which activity they
    /// belong to, and « quel sport la montre a-t-elle compris ? » is exactly
    /// the question this block exists to answer — the answer must not be
    /// available only to people who can see the figure.
    ///
    /// Here rather than in the view so it is a pure function of the metrics,
    /// and so the wording is asserted rather than eyeballed.
    var activitySummaryText: String {
        "\(activity.label) : \(activityTotals.elapsed.walkClockText), "
            + "\(activityTotals.steps) pas, \(activityTotals.distanceKm.kmText(fractionDigits: 1)), "
            + "\(activityTotals.activeCalories) kcal"
    }
}
