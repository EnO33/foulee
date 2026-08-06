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

    /// What this session is, and what Santé will record it as (issue #223).
    /// Defaults to `.walking`: it is what every session the app ever wrote was
    /// stamped with, so a caller that doesn't set it keeps the old behaviour
    /// rather than getting a surprise. `ActiveWalkStore.start` sets it from the
    /// user's `ActivityMode`.
    var activity: SessionActivity = .walking

    /// Quick estimate while a Watch HR feed isn't connected — a fixed number of
    /// kilocalories per step, which depends on the activity (see
    /// `SessionActivity.kcalPerStep`).
    ///
    /// Not "replaced by HKWorkout's own computation once the session is saved",
    /// as this comment used to claim: the phone writes no energy samples at
    /// all, so this value goes into the workout's metadata and is what the
    /// résumé and detail sheets show forever. Only a session recorded with real
    /// energy samples — the watch, Forme, Garmin — carries a measurement to
    /// prefer over it (`WorkoutSummary.init(workout:)`).
    var estimatedCalories: Int {
        Int(Double(steps) * activity.kcalPerStep)
    }

    var distanceKm: Double {
        distanceMeters / 1_000
    }
}
