import Foundation

/// What a session Foulée records *is* — the write-side counterpart of
/// `WorkoutActivityFilter` (which is read-side, and deliberately wider).
///
/// Two cases, not three: `ActivityMode.both` is a preference about the app's
/// scope, never a property of a session in flight. Every session that reaches
/// HealthKit is one thing or the other, and Santé keeps that stamp forever —
/// issue #223 exists because until now the stamp was the literal `.walking`,
/// for every session the app has ever written, run or walk. That past is not
/// fixable retroactively: `HKWorkout` is immutable and Foulée cannot rewrite
/// samples it already saved.
///
/// Shared with the watch target (see Project.swift): the watch writes its own
/// workouts and needs the same vocabulary.
enum SessionActivity: String, Codable, Sendable, CaseIterable {
    case walking
    case running

    /// The activity to record for a user in `mode`, when nothing more specific
    /// is known.
    ///
    /// `.both` falls back to `.walking` on purpose and only for now: there is
    /// no per-session picker yet, and issue #224 is what adds one (on the
    /// phone's start screen *and* on the watch's home screen). Until it lands,
    /// a "les deux" user gets the app's historical behaviour rather than a
    /// coin flip — a wrong stamp is permanent, so the conservative default is
    /// the one that matches what they already have in Santé. #224 only has to
    /// pass its `SessionActivity` in explicitly; nothing here needs to move.
    init(mode: ActivityMode) {
        switch mode {
        case .walking, .both: self = .walking
        case .running: self = .running
        }
    }

    /// Kilocalories per step used by `WalkSession.estimatedCalories`.
    ///
    /// The phone deliberately writes no `activeEnergyBurned` samples (they
    /// would double-count the daily total — see `HealthKitClient+Live`), so for
    /// a phone-recorded session this estimate is the *only* energy figure that
    /// will ever exist: it is stored as workout metadata and read back by
    /// `WorkoutSummary.init(workout:)`. A single constant would therefore have
    /// stamped every run with a walking figure, permanently (issue #223).
    ///
    /// Both numbers are order-of-magnitude estimates, not measurements — the
    /// walking one is the pre-existing 0.04 kcal/step, kept exactly as it was
    /// so no walk anyone has already recorded changes value. Running is
    /// derived the same way: ≈1 kcal/kg/km against walking's ≈0.5, over a
    /// stride roughly 1.4× longer, which lands near 0.09 kcal/step for a
    /// ~70 kg runner. A watch-recorded session ignores this entirely — it
    /// measures real energy, and `WorkoutSummary` now prefers that.
    var kcalPerStep: Double {
        switch self {
        case .walking: 0.04
        case .running: 0.09
        }
    }
}
