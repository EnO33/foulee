import Foundation

/// What one sport added up to inside an outing (issue #318).
public struct SportShare: Equatable, Identifiable, Sendable {
    public var activity: RecordedActivity
    public var duration: TimeInterval
    public var distanceKm: Double

    public var id: RecordedActivity { activity }

    /// « 6'10"/km », or `nil` when the distance is too short to divide —
    /// the same rule, and the same wording, as the watch's legs.
    public var paceText: String? { duration.paceText(overKm: distanceKm) }
}

/// An outing seen sport by sport — the phone's counterpart of the watch
/// recap's per-sport lines (`WatchWorkoutMetrics.perSport`), and the same rule:
/// nothing to show until the outing has mixed sports.
///
/// Pure, so the detail screen only draws what this decided.
public enum OutingBreakdown {
    /// One share per sport, in the order the sports were first done. Empty for
    /// a single-sport row: its totals are already the hero above.
    public static func shares(of summary: WorkoutSummary) -> [SportShare] {
        let activities = summary.activities
        guard activities.count > 1 else { return [] }
        return activities.map { activity in
            let legs = summary.legs.filter { $0.activity == activity }
            return SportShare(
                activity: activity,
                duration: legs.map(\.durationSeconds).reduce(0, +),
                distanceKm: legs.map(\.distanceKm).reduce(0, +)
            )
        }
    }

    /// The leg being done at `date`, for the finger on the timeline or the
    /// heart-rate curve (#319). A boundary belongs to the leg it starts; the
    /// outing's very last instant, to the last leg.
    public static func leg(at date: Date, in legs: [WorkoutSummary]) -> WorkoutSummary? {
        legs.first { $0.startedAt <= date && date < $0.endedAt }
            ?? legs.last.flatMap { $0.endedAt == date ? $0 : nil }
    }

    /// One leg in a line: « 08:10 → 08:18 · 1,50 km · 5'20"/km ».
    public static func legText(_ leg: WorkoutSummary) -> String {
        [leg.timeRangeText, leg.distanceKm.kmText(), leg.durationSeconds.paceText(overKm: leg.distanceKm)]
            .compactMap(\.self)
            .joined(separator: " · ")
    }

    /// The shortest stop between two legs the timeline reads aloud: the
    /// watch's legs touch, a merged outing's parts are minutes apart (#549).
    static let minimumStop: TimeInterval = 60

    /// The timeline read aloud: « Marche, 10 minutes ; course, 8 minutes… »,
    /// leg by leg, in order, with the stops between the parts of a merged
    /// outing: « … ; arrêt de 12 minutes ; marche, 20 minutes ».
    ///
    /// The timeline is colour and length and nothing else, so for VoiceOver it
    /// has to be this sentence or nothing at all — the gap included.
    public static func timelineDescription(of legs: [WorkoutSummary]) -> String {
        legs.enumerated().flatMap { index, leg in
            let label = index == 0 ? leg.activity.label : leg.activity.label.lowercased()
            let part = "\(label), \(minutesText(leg.durationSeconds))"
            guard index > 0 else { return [part] }
            let stop = leg.startedAt.timeIntervalSince(legs[index - 1].endedAt)
            return stop >= minimumStop ? ["arrêt de \(minutesText(stop))", part] : [part]
        }
        .joined(separator: " ; ")
    }

    /// Where to count an outing's steps: each leg's own window, so the steps
    /// of a stop between two parts count for the day, never for the outing
    /// (#553). A single session is its own window.
    public static func stepWindows(of summary: WorkoutSummary) -> [DateInterval] {
        (summary.legs.isEmpty ? [summary] : summary.legs).map { leg in
            DateInterval(start: leg.startedAt, end: max(leg.startedAt, leg.endedAt))
        }
    }

    /// « 1 minute », « 12 minutes »: never « 0 minute », a twelve-second leg
    /// still reads as a minute.
    private static func minutesText(_ duration: TimeInterval) -> String {
        let minutes = max(1, Int((duration / 60).rounded()))
        return "\(minutes) minute\(minutes > 1 ? "s" : "")"
    }
}
