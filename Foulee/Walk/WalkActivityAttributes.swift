import ActivityKit
import Foundation

/// Shape of the data the Live Activity surfaces. Imported by both the
/// iOS app target (which starts/updates/ends the activity) and the
/// FouleeLiveActivity widget extension (which renders Lock Screen +
/// Dynamic Island views).
struct WalkActivityAttributes: ActivityAttributes {
    typealias ContentState = WalkActivityState

    var goalMinutes: Int

    /// Pushed on walk events (start, pause, resume, pedometer samples) —
    /// the clock itself runs system-side off `timerBasis`.
    struct WalkActivityState: Codable, Hashable, Sendable {
        /// Virtual start of the walk: now minus accumulated elapsed,
        /// recomputed on every push so `Text(timerInterval:)` keeps the
        /// clock running while the app is suspended.
        var timerBasis: Date
        /// Set while paused; freezes the system timer via `pauseTime`.
        var pausedAt: Date?
        var elapsed: TimeInterval
        var steps: Int
        var distanceKm: Double
        var activeCalories: Int

        var isPaused: Bool { pausedAt != nil }
    }
}
