import Foundation

/// What the phone can ask the wrist to do during a mirrored session
/// (issue #282).
///
/// **A remote control, not a second engine.** The watch owns the session — it
/// is the only device HealthKit lets mirror — so everything here is a request
/// the wrist carries out, never something the phone does itself.
///
/// One case, and the list will stay short. A pause is *not* coming: Foulée has
/// none on the wrist either, and adding one breaks three invariants that are
/// wall-clock throughout (`splitIfDue` compares 15 s of wall time and back-dates
/// the boundary, `MovementClassifier` divides by wall time,
/// `WatchWorkoutSegment.elapsed(at:)` is wall time). That is a session-engine
/// change, not a button.
enum MirrorCommand: String, Codable, Sendable {
    /// End the outing, save it, and show the recap — the whole of
    /// `WatchWorkoutStore.stop()`.
    ///
    /// Deliberately not « end the session ». `stop()` closes the leg in flight,
    /// folds the outing's figures, tells the phone it is over, ends collection,
    /// saves, and keeps the builder alive for « Réessayer » if the save fails.
    /// Ending the session from the phone's side would skip all of that and
    /// leave the wrist holding an outing nobody finished.
    case stop
}
