import Foundation

/// One recorded stretch of an outing — its own `HKWorkout` (issues #250, #265).
///
/// It was read from `HKWorkoutActivity` once, when the plan was to segment a
/// single session. HealthKit refuses that (#256), so a stretch is now a
/// **session of its own**, closed and reopened at the boundary — the way Forme
/// does it, and the way Santé ends up with a walk *and* a run rather than one
/// mislabelled outing.
///
/// The values are still measured, not derived: each leg's figures are what its
/// own builder had collected when it closed. The aggregation below stayed
/// exactly as it was, which is the point of having made it a pure function over
/// values in the first place.
struct WatchWorkoutSegment: Equatable, Sendable, Identifiable {
    /// Identifies the leg. Carried because `merged(_:)` folds lists that may
    /// describe the same one.
    var id: UUID
    var activity: SessionActivity
    var start: Date
    /// Nil for the segment in flight.
    var end: Date?
    var steps: Int
    var distanceMeters: Double
    var activeCalories: Int

    /// How long this segment has been recording.
    ///
    /// Derived from the two HealthKit dates rather than read from
    /// `HKWorkoutActivity.duration`, which is nothing to read at all while a
    /// segment is still running — and a clock that came from one formula during
    /// a segment and another the instant it ended would jump on screen. The two
    /// agree here anyway: `duration` differs from wall time only across paused
    /// stretches, and a Foulée session has no pause control.
    func elapsed(at now: Date) -> TimeInterval {
        max(0, (end ?? now).timeIntervalSince(start))
    }

    var distanceKm: Double { distanceMeters / 1_000 }

    /// « 12:04 · 1,2 km · 6'10"/km » — this leg, on one line (issue #276).
    ///
    /// **A function, not a property**, and that is not a style choice: the leg
    /// in flight has no `end`, so both its duration and its pace are functions
    /// of the instant they are read at. A stored property would have frozen the
    /// running leg at whatever second it was first drawn — the same defect
    /// issue #266 fixed on the session clock.
    ///
    /// The pace is dropped rather than shown as a placeholder when the leg is
    /// too short to divide (see `paceText(overKm:)`): a line that ends after
    /// the distance reads as a leg that has not gone far yet, which is true,
    /// while « —'—"/km » reads as a broken counter.
    func lineText(at now: Date) -> String {
        [effortText(at: now), rhythmText(at: now)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// « 12:04 · 1,0 km » — what the leg cost.
    ///
    /// Split from the rhythm because the two together outgrow a 40 mm and wrap
    /// **mid-unit**: the first capture of this row read « 7'37"/ » then « km »,
    /// and « pas/ » then « min ». That is the « pa/s » of issue #261 by another
    /// route. Two short lines each fit; one long line does not.
    func effortText(at now: Date) -> String {
        "\(elapsed(at: now).walkClockText) · \(distanceKm.kmText(fractionDigits: 1))"
    }

    /// « 7'37"/km · 165 pas/min » — how it was run. `nil` when the leg is too
    /// short to divide for either.
    func rhythmText(at now: Date) -> String? {
        let duration = elapsed(at: now)
        let parts = [
            duration.paceText(overKm: distanceKm),
            cadenceText(steps: steps, over: duration)
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Fold several readings of the same session into one list.
    ///
    /// Later lists win per `id`. That is the whole point: the segments are read
    /// from `HKLiveWorkoutBuilder.workoutActivities`, from
    /// `currentWorkoutActivity`, and from what the builder's delegate handed
    /// over as each segment ended — three views of one truth, each of which can
    /// be incomplete on its own. Nothing here bets on which: a fresher copy of
    /// a segment simply replaces an older one, and a segment only one source
    /// knows about survives.
    static func merged(_ lists: [[WatchWorkoutSegment]]) -> [WatchWorkoutSegment] {
        var byID: [UUID: WatchWorkoutSegment] = [:]
        for list in lists {
            for segment in list { byID[segment.id] = segment }
        }
        return byID.values.sorted { $0.start < $1.start }
    }
}

/// Everything measured while doing one activity, across a whole session
/// (issue #250).
///
/// Cumulative, not "since the last switch". On an outing that alternates —
/// which is the one this feature exists for — a per-segment figure would read
/// « Course : 2 min » permanently, resetting every time it got interesting.
/// « Course : 12 min depuis le départ » is the number someone actually wants
/// mid-outing.
struct WatchActivityTotals: Equatable, Sendable {
    var elapsed: TimeInterval = 0
    var steps: Int = 0
    var distanceMeters: Double = 0
    var activeCalories: Int = 0

    var distanceKm: Double { distanceMeters / 1_000 }

    static let zero = WatchActivityTotals()

    /// « 1480 pas  1,8 km  136 kcal ».
    ///
    /// One string rather than three views: laid out as equal-width columns the
    /// three counters split their own labels mid-word on a 40 mm wrist — « pa /
    /// s », « kc / al » — at the default text size, before Dynamic Type entered
    /// into it. A paragraph wraps between words instead.
    ///
    /// Separated by spaces and not by « · », because on that same wrist the
    /// line wraps as a matter of course and a middle dot left dangling at the
    /// end of a line reads as a missing value. Each number carries its unit, so
    /// the grouping survives without a mark.
    ///
    /// One decimal for the distance, not two: this line refreshes with the
    /// session and a second decimal would flicker without saying anything.
    var countersText: String {
        "\(steps) pas  \(distanceKm.kmText(fractionDigits: 1))  \(activeCalories) kcal"
    }

    /// Sum every leg, whatever its sport — the outing's own figures.
    ///
    /// The leg in flight has its own builder counting from its own start, so a
    /// screen reading the builder alone would reset to zero the instant the
    /// sport changed (issue #265).
    static func of(_ segments: [WatchWorkoutSegment], at now: Date) -> WatchActivityTotals {
        segments.reduce(into: .zero) { totals, segment in
            totals.elapsed += segment.elapsed(at: now)
            totals.steps += segment.steps
            totals.distanceMeters += segment.distanceMeters
            totals.activeCalories += segment.activeCalories
        }
    }

    /// Sum every segment of `activity`. Segments of the other one are skipped,
    /// so the two totals never overlap and never double-count.
    static func of(
        _ activity: SessionActivity,
        in segments: [WatchWorkoutSegment],
        at now: Date
    ) -> WatchActivityTotals {
        segments.lazy.filter { $0.activity == activity }.reduce(into: .zero) { totals, segment in
            totals.elapsed += segment.elapsed(at: now)
            totals.steps += segment.steps
            totals.distanceMeters += segment.distanceMeters
            totals.activeCalories += segment.activeCalories
        }
    }
}
