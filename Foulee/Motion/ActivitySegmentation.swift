import Foundation

/// One CoreMotion estimate as the history query hands it over (issue #246).
///
/// No `receivedAt`, unlike the watch's live estimate: a historical query
/// reports what the device concluded and when the activity *began*, not when
/// anyone was told. Freshness is not a question one can ask of the past.
struct MotionHistorySample: Equatable, Sendable {
    /// When the device says this activity began.
    var startDate: Date
    var confidence: MotionActivityConfidence
    var walking: Bool
    var running: Bool
}

/// A stretch of one activity inside a session.
struct ActivitySegment: Equatable, Sendable {
    var activity: SessionActivity
    var start: Date
    var end: Date

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Turns a finished session's CoreMotion history into stretches of walking and
/// running, and names the one that dominates (issue #246).
///
/// Pure, so every case that matters is stated here rather than hoped for on a
/// pavement: a history that starts after the session did, estimates the device
/// could not classify, a session nothing was recorded for at all.
///
/// **Post-hoc, and that is not a compromise.** Apple documents that nothing is
/// delivered while an app is suspended, and a phone in a pocket is suspended
/// within seconds — a live subscription would miss most of a walk and cost
/// battery for the rest. The history query returns the complete list of
/// transitions after the fact, so the segmentation is *more* exact than a live
/// one, for no background work at all.
enum ActivitySegmentation {
    /// Readings below this are not evidence. Same floor as the watch.
    static let minimumConfidence: MotionActivityConfidence = .medium

    /// What an unreadable stretch counts as.
    ///
    /// Walking, always, and the reason is arithmetic rather than aesthetic:
    /// `SessionActivity.kcalPerStep` is 0.04 walking against 0.09 running, and
    /// the phone writes **no energy samples at all**, so this estimate is the
    /// only energy figure the session will ever carry. Guessing walking
    /// under-credits; guessing running invents calories, permanently, on an
    /// immutable `HKWorkout`. Same principle as `GarminSnapshotOverlay`: never
    /// a source of minutes nobody earned.
    static let fallback = SessionActivity.walking

    /// Cut `[from, to]` into stretches, oldest first.
    ///
    /// Every instant of the session belongs to exactly one segment — including
    /// the stretches CoreMotion says nothing about, which become `fallback`.
    /// A partial covering would make the durations below add up to less than
    /// the session, and « dominant » would then be a share of something other
    /// than the outing.
    static func segments(
        _ samples: [MotionHistorySample],
        from: Date,
        to: Date
    ) -> [ActivitySegment] {
        guard to > from else { return [] }
        let ordered = samples.sorted { $0.startDate < $1.startDate }
        var spans: [ActivitySegment] = []

        // The stretch before the first estimate, if the history starts late.
        if let first = ordered.first, first.startDate > from {
            spans.append(ActivitySegment(activity: fallback, start: from, end: min(first.startDate, to)))
        } else if ordered.isEmpty {
            spans.append(ActivitySegment(activity: fallback, start: from, end: to))
        }

        for (index, sample) in ordered.enumerated() {
            let start = max(sample.startDate, from)
            let end = min(index + 1 < ordered.count ? ordered[index + 1].startDate : to, to)
            guard end > start else { continue }
            spans.append(ActivitySegment(activity: activity(of: sample), start: start, end: end))
        }

        return merged(spans)
    }

    /// The activity the session should be recorded as.
    ///
    /// Ties go to walking, for the same reason the fallback does: an outing
    /// split down the middle is not evidence that it was a run, and the wrong
    /// guess is permanent.
    static func dominant(_ segments: [ActivitySegment]) -> SessionActivity {
        let running = duration(of: .running, in: segments)
        let walking = duration(of: .walking, in: segments)
        return running > walking ? .running : .walking
    }

    /// How long `activity` lasted across the session. Also what issue #247
    /// needs to stop applying one calorie rate to a mixed outing.
    static func duration(of activity: SessionActivity, in segments: [ActivitySegment]) -> TimeInterval {
        segments.lazy.filter { $0.activity == activity }.reduce(0) { $0 + $1.duration }
    }

    private static func activity(of sample: MotionHistorySample) -> SessionActivity {
        let reading = MotionActivityReading.of(
            walking: sample.walking,
            running: sample.running,
            confidence: sample.confidence,
            minimumConfidence: minimumConfidence
        )
        switch reading {
        case .activity(let activity): return activity
        case .noEvidence: return fallback
        }
    }

    /// Glue consecutive stretches of the same activity into one.
    ///
    /// CoreMotion re-states its verdict regularly, so a steady walk arrives as
    /// a long run of identical estimates. Left apart they would be dozens of
    /// one-minute segments — the totals would be identical, but issue #247 has
    /// to reason about stretches, and « 43 segments » describes the sampling
    /// rate rather than the outing.
    private static func merged(_ spans: [ActivitySegment]) -> [ActivitySegment] {
        var result: [ActivitySegment] = []
        for span in spans {
            if var last = result.last, last.activity == span.activity, last.end >= span.start {
                last.end = max(last.end, span.end)
                result[result.count - 1] = last
            } else {
                result.append(span)
            }
        }
        return result
    }
}
