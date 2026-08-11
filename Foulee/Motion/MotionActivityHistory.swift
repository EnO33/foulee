import Dependencies
import Foundation

/// CoreMotion's activity **history**, wrapped as a struct-of-closures for DI
/// parity with `Pedometer` and `HealthKitClient` (issue #246).
///
/// A query, not a subscription, and deliberately so. Apple documents that no
/// activity updates are delivered while an app is suspended, and a phone in a
/// pocket is suspended within seconds — a live stream would miss most of a walk
/// and burn battery for the part it caught. `queryActivityStarting(from:to:to:)`
/// keeps seven days and returns every transition after the fact.
///
/// It also opens **no second `CMPedometer`**: `Pedometer+Live` holds a single
/// shared one, and a second `startUpdates` would replace the first's handler
/// while `onTermination` killed both.
struct MotionActivityHistory: Sendable {
    /// Every estimate the device kept for `[from, to]`, in no guaranteed order.
    ///
    /// Returns empty rather than throwing when the query fails or permission is
    /// refused: a session must still be saved when its classification cannot be
    /// read, and « no samples » already means « fall back to walking » one
    /// level up (`ActivitySegmentation`). An error case here would be a second
    /// way to say the same thing, and a second thing for every caller to
    /// handle.
    var samples: @Sendable (_ from: Date, _ to: Date) async -> [MotionHistorySample]
}

extension MotionActivityHistory: DependencyKey {
    /// A mixed outing: walking, then a run in the middle, then walking again.
    /// Enough for a preview to show something other than a single block.
    static let previewValue = MotionActivityHistory(
        samples: { from, to in
            let third = to.timeIntervalSince(from) / 3
            return [
                MotionHistorySample(startDate: from, confidence: .high, walking: true, running: false),
                MotionHistorySample(
                    startDate: from.addingTimeInterval(third),
                    confidence: .high,
                    walking: false,
                    running: true
                ),
                MotionHistorySample(
                    startDate: from.addingTimeInterval(third * 2),
                    confidence: .high,
                    walking: true,
                    running: false
                )
            ]
        }
    )

    /// Says nothing, the way an unavailable device does — so a test that has
    /// not opted in gets the fallback rather than an invented classification.
    static let testValue = MotionActivityHistory(samples: { _, _ in [] })
}

extension DependencyValues {
    var motionActivityHistory: MotionActivityHistory {
        get { self[MotionActivityHistory.self] }
        set { self[MotionActivityHistory.self] = newValue }
    }
}
