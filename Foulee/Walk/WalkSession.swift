import Foundation

/// Immutable-ish snapshot of an in-flight or finished walk. The store mutates
/// a `var` of this; the view reads it directly.
struct WalkSession: Equatable, Sendable {
    var startedAt: Date
    var endedAt: Date?
    var elapsed: TimeInterval = 0
    var steps: Int = 0
    var distanceMeters: Double = 0
    /// Cumulative elevation gain (metres) measured by the barometer.
    var elevationGainMeters: Double = 0

    /// Quick estimate while a Watch HR feed isn't connected: ~0.04 kcal/step
    /// for moderate walking. Replaced by HKWorkout's own computation once the
    /// session is saved.
    var estimatedCalories: Int {
        Int(Double(steps) * 0.04)
    }

    var distanceKm: Double {
        distanceMeters / 1_000
    }
}
