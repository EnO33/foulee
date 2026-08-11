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

    /// True while `activity` is a placeholder the detection replaces at the end
    /// (issue #246).
    ///
    /// Only « les deux » produces it: the mode says the user does both, the
    /// phone no longer asks which, and nothing is knowable until the session's
    /// CoreMotion history can be read — which is at `stop()`. Everywhere it
    /// matters the app says « Ta sortie » rather than naming a sport it is
    /// about to overwrite.
    ///
    /// A flag rather than an optional `activity`: `estimatedCalories` needs a
    /// rate at every instant, and the honest provisional rate is walking's —
    /// the lower of the two, so a session read mid-flight under-credits rather
    /// than inventing.
    var isActivityUndecided: Bool = false

    /// Steps measured over each activity's own stretches (issue #247).
    ///
    /// `nil` when the outing was never segmented — an install where motion
    /// recognition is unavailable or refused, or a session that predates it.
    /// The estimate below then falls back to exactly what it always was.
    var stepsByActivity: [SessionActivity: Int]?

    /// Quick estimate while a Watch HR feed isn't connected — kilocalories per
    /// step, at the rate of the activity those steps were taken at (see
    /// `SessionActivity.kcalPerStep`).
    ///
    /// Not "replaced by HKWorkout's own computation once the session is saved",
    /// as this comment used to claim: the phone writes no energy samples at
    /// all, so this value goes into the workout's metadata and is what the
    /// résumé and detail sheets show forever. Only a session recorded with real
    /// energy samples — the watch, Forme, Garmin — carries a measurement to
    /// prefer over it (`WorkoutSummary.init(workout:)`).
    ///
    /// **Priced per stretch since issue #247**, and that is strictly better
    /// than the single rate it replaces — with or without automatic detection.
    /// A rate of 0.04 against 0.09 means a genuinely mixed outing was out by up
    /// to 2.25× whichever way it was labelled, and the picker of #224 could not
    /// help: ten minutes of walking then twenty of running is neither.
    ///
    /// A homogeneous outing lands on exactly the figure it always did — one
    /// stretch, one rate, the same multiplication.
    var estimatedCalories: Int {
        guard let stepsByActivity, !stepsByActivity.isEmpty else {
            return Int(Double(steps) * activity.kcalPerStep)
        }
        return Int(stepsByActivity.reduce(0) { total, entry in
            total + Double(entry.value) * entry.key.kcalPerStep
        })
    }

    var distanceKm: Double {
        distanceMeters / 1_000
    }
}
