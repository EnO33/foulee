import Foundation

/// What one sport added up to inside an outing (issue #318).
struct SportShare: Equatable, Identifiable, Sendable {
    var activity: RecordedActivity
    var duration: TimeInterval
    var distanceKm: Double

    var id: RecordedActivity { activity }

    /// « 6'10"/km », or `nil` when the distance is too short to divide —
    /// the same rule, and the same wording, as the watch's legs.
    var paceText: String? { duration.paceText(overKm: distanceKm) }
}

/// An outing seen sport by sport — the phone's counterpart of the watch
/// recap's per-sport lines (`WatchWorkoutMetrics.perSport`), and the same rule:
/// nothing to show until the outing has mixed sports.
///
/// Pure, so the detail screen only draws what this decided.
enum OutingBreakdown {
    /// One share per sport, in the order the sports were first done. Empty for
    /// a single-sport row: its totals are already the hero above.
    static func shares(of summary: WorkoutSummary) -> [SportShare] {
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
    static func leg(at date: Date, in legs: [WorkoutSummary]) -> WorkoutSummary? {
        legs.first { $0.startedAt <= date && date < $0.endedAt }
            ?? legs.last.flatMap { $0.endedAt == date ? $0 : nil }
    }

    /// One leg in a line: « 08:10 → 08:18 · 1,50 km · 5'20"/km ».
    static func legText(_ leg: WorkoutSummary) -> String {
        [leg.timeRangeText, leg.distanceKm.kmText(), leg.durationSeconds.paceText(overKm: leg.distanceKm)]
            .compactMap(\.self)
            .joined(separator: " · ")
    }

    /// The timeline read aloud: « Marche, 10 minutes ; course, 8 minutes… »,
    /// leg by leg, in order.
    ///
    /// The timeline is colour and length and nothing else, so for VoiceOver it
    /// has to be this sentence or nothing at all.
    static func timelineDescription(of legs: [WorkoutSummary]) -> String {
        legs.enumerated().map { index, leg in
            let minutes = max(1, Int((leg.durationSeconds / 60).rounded()))
            let label = index == 0 ? leg.activity.label : leg.activity.label.lowercased()
            return "\(label), \(minutes) minute\(minutes > 1 ? "s" : "")"
        }
        .joined(separator: " ; ")
    }
}
