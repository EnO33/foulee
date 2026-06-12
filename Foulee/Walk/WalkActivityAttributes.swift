import ActivityKit
import Foundation

/// Shape of the data the Live Activity surfaces. Imported by both the
/// iOS app target (which starts/updates/ends the activity) and the
/// FouleeLiveActivity widget extension (which renders Lock Screen +
/// Dynamic Island views).
struct WalkActivityAttributes: ActivityAttributes {
    typealias ContentState = WalkActivityState

    var goalMinutes: Int

    /// Updated every tick from the app.
    struct WalkActivityState: Codable, Hashable, Sendable {
        var elapsed: TimeInterval
        var steps: Int
        var distanceKm: Double
        var activeCalories: Int
        var isPaused = false

        static let zero = WalkActivityState(
            elapsed: 0,
            steps: 0,
            distanceKm: 0,
            activeCalories: 0
        )
    }
}
