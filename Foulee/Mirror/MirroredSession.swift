import Foundation

/// A workout session running on the paired Watch, as the phone sees it
/// (issue #277).
///
/// **The watch is always the engine, and that is not a design choice.**
/// `startMirroringToCompanionDevice()` exists only on watchOS, and
/// `HKWorkoutSessionType` has exactly two cases — `primary` and `mirrored`.
/// There is no API for the reverse direction and there will not be one, so a
/// session measured by the iPhone cannot be shown on the wrist the same way.
/// `ActiveWalkStore` is the fallback for « no watch », not the other half of a
/// symmetry.
struct MirroredSession: Equatable, Sendable {
    /// When the leg began — **its** start, not the outing's.
    ///
    /// A change of sport ends one session and opens another (issue #265), so
    /// the phone sees a *new* mirror at each switch. Anything that wants the
    /// outing's own clock has to keep it across mirrors rather than read this.
    var startedAt: Date
    var activity: SessionActivity
}

/// What the phone learns about the wrist.
///
/// A stream of events rather than a snapshot, because the interesting moments
/// are the edges: a mirror opening (the wearer started, or changed sport) and a
/// mirror closing.
enum MirroredSessionEvent: Equatable, Sendable {
    case started(MirroredSession)
    case ended
}
