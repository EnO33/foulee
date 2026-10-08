import Foundation

/// Custom `HKWorkout` metadata keys Foulée writes.
///
/// Shared with the watch target (see Project.swift): since issue #316 both
/// platforms write keys from this list, and one spelling is the only way the
/// phone can be sure to read back what the wrist wrote.
enum FouleeWorkoutMetadata {
    // A walk's *own* measured totals. We don't write step / distance / energy
    // **samples** from the phone (they'd double-count the daily totals the
    // Today screen sums back from HealthKit), so these keys let the résumé and
    // detail show the walk's real numbers without touching any daily sum.
    // Walks from other sources (Watch, Apple Workouts) don't carry them, so
    // readers fall back to the workout's statistics.
    static let steps = "com.eno33.foulee.workout.steps"
    static let distanceMeters = "com.eno33.foulee.workout.distanceMeters"
    static let calories = "com.eno33.foulee.workout.calories"

    // Which outing a watch leg belongs to, and where in it (issue #316). See
    // `OutingLeg`.
    static let outingID = "com.eno33.foulee.workout.outingID"
    static let legIndex = "com.eno33.foulee.workout.legIndex"
}

/// Where one leg sits in its outing (issue #316).
///
/// A change of sport ends one `HKWorkout` and opens another (#265) — HealthKit
/// refuses two sports in one session (#256) — so an outing of five legs is
/// five records in Santé that nothing ties together. Contiguity is not enough
/// to tie them back up: two outings can follow each other within seconds, and
/// a leg lost to a crash leaves a gap inside one. This is the exact link.
struct OutingLeg: Hashable, Sendable {
    /// Drawn once when the outing starts, shared by every leg of it.
    var outingID: UUID
    /// 0 for the first leg, then one more per change of sport.
    var index: Int

    /// Read a leg back from a workout's metadata — `nil` for anything not
    /// stamped by the watch, which is every outing recorded before #316 and
    /// every workout from another app.
    init?(metadata: [String: Any]?) {
        guard let raw = metadata?[FouleeWorkoutMetadata.outingID] as? String,
              let outingID = UUID(uuidString: raw),
              let index = metadata?[FouleeWorkoutMetadata.legIndex] as? Int
        else { return nil }
        self.init(outingID: outingID, index: index)
    }

    init(outingID: UUID, index: Int) {
        self.outingID = outingID
        self.index = index
    }

    /// What the leg's workout is stamped with. HealthKit takes only strings,
    /// numbers, dates and quantities, hence the UUID as a string.
    var metadata: [String: Any] {
        [
            FouleeWorkoutMetadata.outingID: outingID.uuidString,
            FouleeWorkoutMetadata.legIndex: index
        ]
    }
}
