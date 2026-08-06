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

    /// How the two pickers name this activity — « Marche » and « Course », the
    /// same two words `ActivityMode.label` uses in Réglages and in onboarding
    /// (issues #220, #221). One table rather than one per screen: the phone
    /// sheet and the watch screen ask the same question, and a user who picked
    /// « Course » in Réglages must read the same word on the wrist.
    ///
    /// No `init(mode:)` any more. It used to answer "which activity for this
    /// mode?" and had to invent `.walking` for « les deux » — see
    /// `ActivityStartIntent`, which asks instead of inventing.
    var label: String {
        switch self {
        case .walking: "Marche"
        case .running: "Course"
        }
    }

    /// The figure the pickers draw. `ActivityGlyph` rather than `FouleeIcon`
    /// because this file is compiled into the watch app, which has no
    /// DesignSystem — the exact cross-target mismatch `ActivityMode+Icon`
    /// documents.
    var icon: String {
        switch self {
        case .walking: ActivityGlyph.walk
        case .running: ActivityGlyph.run
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
