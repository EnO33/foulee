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
    /// « 5'25"/km », or `nil` when there is nothing honest to say (issue #300).
    ///
    /// Carried on the snapshot rather than pulled from the store by the view,
    /// so the screen stays a function of one value — and so the withholding
    /// rules can be asserted without a session.
    var recentPace: String?
    /// Every leg of the outing, oldest first (issue #265).
    ///
    /// A change of sport ends one `HKWorkout` and opens another, so an outing
    /// is a list rather than a single record. The summary reads it to give each
    /// sport its own figures beside the totals.
    var legs: [WatchWorkoutSegment] = []

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

    /// Each sport of the outing with its own figures, oldest first — empty when
    /// there is nothing to break down (issue #265).
    ///
    /// Empty for a single-sport outing **on purpose**: the totals above already
    /// say everything, and a lone « Marche 18:24 » under an 18:24 clock is a
    /// line that repeats itself. It appears exactly when the outing changed
    /// sport, which is when it has something to add.
    var perSport: [WatchSportSummary] {
        let sports = Set(legs.map(\.activity))
        guard sports.count > 1 else { return [] }
        return SessionActivity.allCases.compactMap { activity in
            guard sports.contains(activity) else { return nil }
            // Every leg is closed by the time a summary is shown, so the clock
            // passed here changes nothing.
            return WatchSportSummary(
                activity: activity,
                totals: WatchActivityTotals.of(activity, in: legs, at: .distantPast)
            )
        }
    }

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

    /// « Course · 7'37"/km » — the sport being done and how fast, right now.
    /// Just « Course » when there is no pace to state (issue #300).
    ///
    /// **The pace took the place of this sport's elapsed time**, and only one
    /// of them fits: three parts on this line wrap on a 40 mm, and the capture
    /// sentinel said so rather than letting it ship. The elapsed lost, because
    /// « depuis combien de temps je cours ? » is answered one swipe away on the
    /// legs page — with a pace per leg besides — while « à quelle allure je
    /// vais ? » is answered nowhere else at all.
    ///
    /// The clock is dropped rather than shown at zero, and the counters below
    /// it disappear for the same reason: since issue #256 nothing segments the
    /// session, so there is genuinely nothing to total. « Course · 00:00 » next
    /// to three zeros reads as a broken counter; « Course » alone reads as what
    /// it is — the sport, named, with no figures claimed.
    var activityHeadlineText: String {
        guard let recentPace else { return activity.label }
        return "\(activity.label) · \(recentPace)"
    }

    /// Whether the current sport's own totals say anything the clock and the
    /// tiles do not (issue #299).
    ///
    /// **Not merely « has HealthKit measured something ».** On a sortie that
    /// has not changed sport there is one leg, so this sport's totals *are* the
    /// outing's totals — « Course · 18:24 » under an 18:24 clock, and three
    /// counters repeating the four tiles above them. The same figures twice.
    ///
    /// Same rule as `perSport`, and for the same reason: the block appears when
    /// it has something to add, which is once the outing has been split.
    ///
    /// It also buys back the height that let the page overflow a 40 mm. That is
    /// a consequence, not the reason — but it is how the defect was found, once
    /// the capture seed stopped photographing a page shorter than the app.
    var showsActivityBreakdown: Bool { legs.count > 1 && activityTotals != .zero }

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
        guard showsActivityBreakdown else { return activity.label }
        return "\(activity.label) : \(activityTotals.elapsed.walkClockText), "
            + "\(activityTotals.steps) pas, \(activityTotals.distanceKm.kmText(fractionDigits: 1)), "
            + "\(activityTotals.activeCalories) kcal"
    }
}

extension WatchWorkoutMetrics {
    /// These figures, as the phone will read them (issue #278).
    ///
    /// Built from the metrics alone — no store state — so what the wrist sends
    /// is a pure function of what the wrist shows, and can be asserted without
    /// a session.
    ///
    /// `outingStartedAt` comes from `timerBasis`, which is already the instant
    /// the outing's clock would have read zero. Falling back to `now - elapsed`
    /// covers the finished session, where the basis is deliberately cleared so
    /// the recap stops counting.
    func snapshot(at now: Date, isEnded: Bool) -> WatchSessionSnapshot {
        WatchSessionSnapshot(
            sentAt: now,
            outingStartedAt: timerBasis ?? now.addingTimeInterval(-elapsed(at: now)),
            activity: activity,
            steps: steps,
            distanceMeters: distanceMeters,
            activeCalories: activeCalories,
            heartRate: heartRate,
            isEnded: isEnded
        )
    }
}

/// One sport's share of an outing, as the summary states it (issue #265).
struct WatchSportSummary: Equatable, Sendable, Identifiable {
    var activity: SessionActivity
    var totals: WatchActivityTotals

    var id: SessionActivity { activity }

    /// « Marche · 12:04 · 1,2 km · 12'04"/km » (issue #297).
    ///
    /// **The pace of a whole stretch is the honest one.** Over a sortie the
    /// relative error of a wrist-estimated distance averages out and the
    /// duration is exact — which is why this line gets a pace while a live
    /// counter has to earn one (issue #300).
    ///
    /// Built rather than interpolated, because `paceText` says nothing under
    /// 50 m: a stretch too short to divide ends after its distance instead of
    /// carrying an empty separator.
    ///
    /// A plain `String`, and the figure is drawn beside it rather than
    /// interpolated into it. Interpolating a SwiftUI `Image` only works inside
    /// a **single** text literal: concatenate with `+` and it becomes a
    /// `String`, so the image renders as
    /// `SwiftUI.Image(SwiftUI.ImageProviderBox<…>)` — which is exactly what the
    /// first capture of this screen showed.
    var text: String {
        var parts = [
            activity.label,
            totals.elapsed.walkClockText,
            totals.distanceKm.kmText(fractionDigits: 1)
        ]
        if let pace = totals.elapsed.paceText(overKm: totals.distanceKm) { parts.append(pace) }
        return parts.joined(separator: " · ")
    }
}
