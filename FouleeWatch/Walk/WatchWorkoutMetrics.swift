import Foundation

/// Live snapshot from `HKLiveWorkoutBuilder` — the view binds against
/// this. Heart rate is `nil` until the first sensor reading lands.
struct WatchWorkoutMetrics: Equatable, Sendable {
    var elapsed: TimeInterval
    var steps: Int
    var distanceMeters: Double
    var activeCalories: Int
    var heartRate: Int?
    /// Virtual start of the session: the instant `elapsed` would have been zero
    /// (issue #266).
    ///
    /// `nil` when there is no clock to run — the zero state, and the seeded
    /// capture session, whose board must stay byte-identical between runs.
    ///
    /// Same construction as the Live Activity's `timerBasis`, and for the same
    /// reason: a *duration* pushed from the store is frozen between two
    /// deliveries from HealthKit, while a *date* lets any clock derive the
    /// current value on its own. Recomputed on every ingest, so HealthKit's own
    /// `elapsedTime` — which knows about paused stretches — keeps correcting
    /// any drift.
    var timerBasis: Date?
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

    /// How long the session has been running, read at `date`.
    ///
    /// This is what the live screen must draw. `elapsed` alone is a snapshot
    /// written when HealthKit delivered a batch: the screen wrapped it in a
    /// `TimelineView` that rebuilt every second and redrew **the same frozen
    /// number** — the clock advanced in jerks, at HealthKit's pace, and the
    /// file's own comment claimed the opposite (issue #266).
    ///
    /// Falls back to the pushed snapshot when there is no basis, which is the
    /// finished session and the seeded capture — both of which want a value
    /// that does not move.
    func elapsed(at date: Date) -> TimeInterval {
        guard let timerBasis else { return elapsed }
        return max(0, date.timeIntervalSince(timerBasis))
    }

    /// « Course · 12:04 » — the sport being done and how long it has added up
    /// to across the session. Just « Course » when nothing has been measured
    /// for it yet.
    ///
    /// The clock is dropped rather than shown at zero, and the counters below
    /// it disappear for the same reason: since issue #256 nothing segments the
    /// session, so there is genuinely nothing to total. « Course · 00:00 » next
    /// to three zeros reads as a broken counter; « Course » alone reads as what
    /// it is — the sport, named, with no figures claimed.
    var activityHeadlineText: String {
        guard hasMeasuredActivityTotals else { return activity.label }
        return "\(activity.label) · \(activityTotals.elapsed.walkClockText)"
    }

    /// Whether HealthKit has measured anything for the current sport.
    var hasMeasuredActivityTotals: Bool { activityTotals != .zero }

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
        guard hasMeasuredActivityTotals else { return activity.label }
        return "\(activity.label) : \(activityTotals.elapsed.walkClockText), "
            + "\(activityTotals.steps) pas, \(activityTotals.distanceKm.kmText(fractionDigits: 1)), "
            + "\(activityTotals.activeCalories) kcal"
    }
}
